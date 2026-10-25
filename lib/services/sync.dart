import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/entry.dart';
import '../core/markdown_io.dart';
import '../core/store.dart';
import '../core/vault.dart';
import 'git_remote.dart';

class SyncException implements Exception {
  SyncException(this.code, [this.detail = '']);

  /// `other_vault`: the repo holds a different diary; `remote`: host error.
  final String code;
  final String detail;
  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

class SyncReport {
  int uploaded = 0;
  int downloaded = 0;
  int deletedLocal = 0;
  int deletedRemote = 0;
  int conflicts = 0;
  final List<String> skipped = [];

  /// Entry ids changed on this device by the sync (to refresh the UI).
  final Set<String> changedEntries = {};
  bool vaultChanged = false;

  bool get nothing => uploaded + downloaded + deletedLocal + deletedRemote == 0;

  @override
  String toString() => '↑$uploaded ↓$downloaded ✕${deletedLocal + deletedRemote} ⚡$conflicts';
}

/// Remembered per repository: blob ids at the last sync (the merge base) and a hash cache.
class SyncState {
  SyncState({this.key = '', Map<String, String>? base, Map<String, List>? hashes, this.lastSync})
    : base = base ?? {},
      hashes = hashes ?? {};

  String key;
  Map<String, String> base;

  /// path → [size, mtime ms, sha]: avoids re-hashing big media on every sync.
  Map<String, List> hashes;
  DateTime? lastSync;

  Map<String, dynamic> toJson() => {
    'key': key,
    'base': base,
    'hashes': hashes,
    if (lastSync != null) 'last': lastSync!.toIso8601String(),
  };

  factory SyncState.fromJson(Map<String, dynamic>? j) => j == null
      ? SyncState()
      : SyncState(
          key: (j['key'] as String?) ?? '',
          base: Map<String, String>.from((j['base'] as Map?) ?? {}),
          hashes: {for (final e in ((j['hashes'] as Map?) ?? {}).entries) '${e.key}': e.value as List},
          lastSync: DateTime.tryParse('${j['last']}'),
        );
}

const _readme = '''# Летопись

Зашифрованный дневник приложения «Летопись». Файлы `*.enc` — AES-256-GCM, ключ открывается только
паролем владельца (`vault.json`: Argon2id). Не редактируйте файлы вручную.

Encrypted diary of the Letopis app. Files are AES-256-GCM encrypted; do not edit them by hand.
''';

/// Two-way sync of the encrypted store, or a push-only plain Markdown mirror.
class SyncEngine {
  SyncEngine({required this.store, required this.remote, required this.config, required this.device});

  final EntryStore store;
  final RemoteRepo remote;
  final GitHubConfig config;
  final String device;

  String get _prefix => config.dir.isEmpty ? '' : '${config.dir.replaceAll(RegExp(r'^/+|/+$'), '')}/';

  Future<SyncState> _loadState() async {
    final s = SyncState.fromJson(await store.readJson('sync'));
    if (s.key != config.key) return SyncState(key: config.key);
    return s;
  }

  Future<SyncReport> run() async {
    for (var attempt = 0; ; attempt++) {
      try {
        return config.plain ? await _mirror() : await _sync();
      } on RemoteException catch (e) {
        // Another device pushed between our snapshot and commit: start over on the new head.
        if (e.isConflict && attempt < 2) continue;
        throw SyncException('remote', e.toString());
      }
    }
  }

  // ---- encrypted two-way sync --------------------------------------------------------------

  Future<SyncReport> _sync() async {
    final report = SyncReport();
    final state = await _loadState();
    final snap = await remote.snapshot();
    final remoteFiles = <String, String>{
      for (final e in snap.files.entries)
        if (e.key.startsWith(_prefix)) e.key.substring(_prefix.length): e.value,
    };

    // The remote must hold this diary or nothing yet.
    final localVault = await File('${store.root.path}/vault.json').readAsBytes();
    final remoteVaultSha = remoteFiles['vault.json'];
    if (remoteVaultSha != null && remoteVaultSha != gitBlobSha(localVault)) {
      final theirs = VaultFile.decode(utf8.decode(await remote.readBlob(remoteVaultSha)));
      final mine = VaultFile.decode(utf8.decode(localVault));
      if (theirs.id != mine.id) throw SyncException('other_vault');
    }

    final local = await _localHashes(state);
    final put = <String, Uint8List>{};
    final remove = <String>{};
    final paths = {
      ...local.keys,
      ...remoteFiles.keys,
      ...state.base.keys,
    }.where((p) => p.endsWith('.enc') || p == 'vault.json').toSet();

    for (final path in paths) {
      final l = local[path], r = remoteFiles[path], b = state.base[path];
      if (l == r) {
        if (l == null) {
          state.base.remove(path);
        } else {
          state.base[path] = l;
        }
        continue;
      }
      final localChanged = l != b;
      final remoteChanged = r != b;
      if (localChanged && !remoteChanged) {
        if (l == null) {
          remove.add(path);
          report.deletedRemote++;
        } else {
          put[path] = await store.file(path).readAsBytes();
          report.uploaded++;
        }
      } else if (!localChanged && remoteChanged) {
        await _takeRemote(path, r, report);
      } else {
        // Both sides changed.
        await _resolveConflict(path, l, r, put, report);
      }
    }

    if (put.isNotEmpty || remove.isNotEmpty) {
      final full = {for (final e in put.entries) '$_prefix${e.key}': e.value};
      if (!snap.files.containsKey('${_prefix}README.md')) {
        full['${_prefix}README.md'] = Uint8List.fromList(utf8.encode(_readme));
      }
      await remote.commit(snap, put: full, remove: {for (final p in remove) '$_prefix$p'}, message: _message(report));
      for (final e in put.entries) {
        state.base[e.key] = gitBlobSha(e.value);
      }
      remove.forEach(state.base.remove);
    }
    // Files taken from the remote now match it.
    for (final path in paths) {
      final r = remoteFiles[path];
      if (!put.containsKey(path) && !remove.contains(path)) {
        if (r == null) {
          state.base.remove(path);
        } else {
          state.base[path] = r;
        }
      }
    }
    state.lastSync = DateTime.now();
    await store.writeJson('sync', state.toJson());
    return report;
  }

  Future<void> _takeRemote(String path, String? r, SyncReport report) async {
    final id = _entryId(path);
    if (r == null) {
      final f = store.file(path);
      if (await f.exists()) await f.delete();
      if (id != null) {
        await store.reload(id);
        report.changedEntries.add(id);
      }
      report.deletedLocal++;
      return;
    }
    final bytes = await remote.readBlob(r);
    if (path == 'vault.json') {
      await File('${store.root.path}/vault.json').writeAsBytes(bytes, flush: true);
      report.vaultChanged = true;
    } else {
      await store.writeRaw(path, bytes);
    }
    if (id != null) {
      await store.reload(id);
      report.changedEntries.add(id);
    }
    report.downloaded++;
  }

  Future<void> _resolveConflict(
    String path,
    String? l,
    String? r,
    Map<String, Uint8List> put,
    SyncReport report,
  ) async {
    final id = _entryId(path);
    if (l == null || r == null) {
      // Deleted on one side, edited on the other: the edit wins.
      if (l == null) {
        await _takeRemote(path, r, report);
      } else {
        put[path] = await store.file(path).readAsBytes();
        report.uploaded++;
      }
      return;
    }
    if (id == null) {
      // Media and thumbnails never change after creation; vault: keep this device's.
      put[path] = await store.file(path).readAsBytes();
      report.uploaded++;
      return;
    }
    final mine = store.byId(id);
    final theirsBytes = await remote.readBlob(r);
    final theirs = entryFromMarkdown(
      utf8.decode(await store.box.decrypt(theirsBytes, context: EntryStore.contextFor(path))),
    );
    if (mine == null) {
      await store.writeRaw(path, theirsBytes);
      await store.reload(id);
      report.downloaded++;
      return;
    }
    if (mine.sameContent(theirs)) {
      // Same text, different encryption: just align with the remote.
      await store.writeRaw(path, theirsBytes);
      await store.reload(id);
      return;
    }
    report.conflicts++;
    final (winner, loser) = theirs.updated.isAfter(mine.updated) ? (theirs, mine) : (mine, theirs);
    if (identical(winner, theirs)) {
      await store.writeRaw(path, theirsBytes);
      await store.reload(id);
      report.downloaded++;
    } else {
      put[path] = await store.file(path).readAsBytes();
      report.uploaded++;
    }
    // Nothing is lost: the other version becomes its own entry.
    final copy = loser.copy();
    final conflict = Entry(
      id: newId(),
      created: copy.created,
      updated: DateTime.now(),
      title: '⚡ ${copy.displayTitle}',
      body: copy.body,
      tags: [...copy.tags, 'конфликт'],
      attachments: copy.attachments,
      mood: copy.mood,
    );
    await store.save(conflict, touch: false);
    final cp = EntryStore.entryPath(conflict.id);
    put[cp] = await store.file(cp).readAsBytes();
    report.uploaded++;
    report.changedEntries
      ..add(id)
      ..add(conflict.id);
  }

  static String? _entryId(String path) {
    final m = RegExp(r'^entries/([^/]+)\.md\.enc$').firstMatch(path);
    return m?.group(1);
  }

  Future<Map<String, String>> _localHashes(SyncState state) async {
    final out = <String, String>{};
    final paths = [...await store.listSyncable(), 'vault.json'];
    final seen = <String>{};
    for (final p in paths) {
      final f = p == 'vault.json' ? File('${store.root.path}/vault.json') : store.file(p);
      if (!await f.exists()) continue;
      final stat = await f.stat();
      final cached = state.hashes[p];
      final mtime = stat.modified.millisecondsSinceEpoch;
      if (cached != null && cached[0] == stat.size && cached[1] == mtime) {
        out[p] = cached[2] as String;
      } else {
        final sha = gitBlobSha(await f.readAsBytes());
        state.hashes[p] = [stat.size, mtime, sha];
        out[p] = sha;
      }
      seen.add(p);
    }
    state.hashes.removeWhere((k, _) => !seen.contains(k));
    return out;
  }

  String _message(SyncReport r) {
    final parts = <String>[
      if (r.uploaded > 0) '↑${r.uploaded}',
      if (r.deletedRemote > 0) '✕${r.deletedRemote}',
      if (r.conflicts > 0) '⚡${r.conflicts}',
    ];
    return 'Летопись: ${parts.join(' ')} ($device)';
  }

  // ---- plain Markdown mirror ---------------------------------------------------------------

  /// Path of an entry in the plain mirror: `entries/2026/10/2026-10-25-0941-утро.md`.
  static String plainEntryPath(Entry e) {
    final t = e.created.toLocal();
    return 'entries/${t.year}/${t.month.toString().padLeft(2, '0')}/${entrySlug(e)}.md';
  }

  static String plainMediaPath(Attachment a) => 'media/${a.id}.${a.extension}';

  /// Plain Markdown of an entry with `att:` links rewritten to relative media paths.
  static String plainMarkdown(Entry e, Map<String, Attachment> attachments) {
    final out = e.copy()
      ..body = rewriteAttachmentLinks(e.body, (id) {
        final a = attachments[id];
        return a == null ? 'att:$id' : '../../../${plainMediaPath(a)}';
      });
    return entryToMarkdown(out);
  }

  Future<SyncReport> _mirror() async {
    final report = SyncReport();
    final state = await _loadState();
    final snap = await remote.snapshot();
    final want = <String, Uint8List>{};
    final mediaSha = <String, String>{}; // from cache: media never changes
    for (final e in store.entries) {
      final atts = {for (final a in e.attachments) a.id: a};
      want[plainEntryPath(e)] = Uint8List.fromList(utf8.encode(plainMarkdown(e, atts)));
      for (final a in e.attachments) {
        final p = plainMediaPath(a);
        final known = state.hashes['plain:$p'];
        if (known != null && snap.files['$_prefix$p'] == known[2]) {
          mediaSha[p] = known[2] as String;
        } else if (store.hasMedia(a.id)) {
          final bytes = await store.mediaBytes(a.id);
          if (bytes.length > GitHubRepo.maxBlobBytes) {
            report.skipped.add(a.name);
            continue;
          }
          want[p] = bytes;
          state.hashes['plain:$p'] = [bytes.length, 0, gitBlobSha(bytes)];
        }
      }
    }
    final put = <String, Uint8List>{};
    for (final e in want.entries) {
      if (snap.files['$_prefix${e.key}'] != gitBlobSha(e.value)) {
        put['$_prefix${e.key}'] = e.value;
        report.uploaded++;
      }
    }
    final remove = <String>{};
    for (final p in snap.files.keys) {
      if (!p.startsWith(_prefix)) continue;
      final rel = p.substring(_prefix.length);
      final managed = rel.startsWith('entries/') || rel.startsWith('media/');
      if (managed && !want.containsKey(rel) && !mediaSha.containsKey(rel)) {
        remove.add(p);
        report.deletedRemote++;
      }
    }
    if (put.isNotEmpty || remove.isNotEmpty) {
      await remote.commit(snap, put: put, remove: remove, message: 'Летопись: ${report.uploaded} файлов ($device)');
    }
    state.lastSync = DateTime.now();
    await store.writeJson('sync', state.toJson());
    return report;
  }
}
