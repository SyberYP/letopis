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

  /// `other_vault`: the repo holds a different diary (or a key file that doesn't open this one);
  /// `public_repo`: plain mirror into a public repository; `remote`: host error.
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
    // Only files this app writes: a repository is shared space, and a path like
    // `settings.enc` or `../x.enc` must never reach the local folder.
    final remoteFiles = <String, String>{
      for (final e in snap.files.entries)
        if (e.key.startsWith(_prefix) && isSyncPath(e.key.substring(_prefix.length)))
          e.key.substring(_prefix.length): e.value,
    };

    // The remote must hold this diary or nothing yet.
    final localVault = await File('${store.root.path}/vault.json').readAsBytes();
    final remoteVaultSha = remoteFiles['vault.json'];
    if (remoteVaultSha != null && remoteVaultSha != gitBlobSha(localVault)) {
      final VaultFile theirs;
      try {
        theirs = VaultFile.decode(utf8.decode(await remote.readBlob(remoteVaultSha)));
      } on FormatException {
        throw SyncException('other_vault');
      }
      final mine = VaultFile.decode(utf8.decode(localVault));
      if (theirs.id != mine.id) throw SyncException('other_vault');
      // A changed key file (new password on another device) must still wrap this diary's key;
      // otherwise taking it would lock the user out of their own entries.
      final probe = await theirs.unlockWithKey(store.box.keyBytes);
      if (probe == null) throw SyncException('other_vault');
      probe.wipe();
    }

    final local = await _localHashes(state);
    final put = <String, BlobSource>{};
    final remove = <String>{};
    final paths = {
      ...local.keys,
      ...remoteFiles.keys,
      ...state.base.keys,
    }.where(isSyncPath).toSet();

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
          put[path] = _fileSource(path);
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
        full['${_prefix}README.md'] = bytesSource(utf8.encode(_readme));
      }
      await remote.commit(snap, put: full, remove: {for (final p in remove) '$_prefix$p'}, message: _message(report));
      // The base is what was actually uploaded, even if the file changed again meanwhile.
      for (final path in put.keys) {
        final sha = _uploaded[path];
        if (sha != null) state.base[path] = sha;
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
    Map<String, BlobSource> put,
    SyncReport report,
  ) async {
    final id = _entryId(path);
    if (l == null || r == null) {
      // Deleted on one side, edited on the other: the edit wins.
      if (l == null) {
        await _takeRemote(path, r, report);
      } else {
        put[path] = _fileSource(path);
        report.uploaded++;
      }
      return;
    }
    if (id == null) {
      // Media and thumbnails never change after creation; vault: keep this device's.
      put[path] = _fileSource(path);
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
      put[path] = _fileSource(path);
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
    put[cp] = _fileSource(cp);
    report.uploaded++;
    report.changedEntries
      ..add(id)
      ..add(conflict.id);
  }

  /// Blob ids of uploaded files, recorded when their bytes are read for the upload.
  final Map<String, String> _uploaded = {};

  BlobSource _fileSource(String path) => () async {
    final f = path == 'vault.json' ? File('${store.root.path}/vault.json') : store.file(path);
    final bytes = await f.readAsBytes();
    _uploaded[path] = gitBlobSha(bytes);
    return bytes;
  };

  static final _syncPath = RegExp(r'^(vault\.json|entries/[A-Za-z0-9_-]{1,64}\.md\.enc|(media|thumbs)/[A-Za-z0-9_-]{1,64}\.enc)$');

  /// Paths the encrypted sync may read or write (relative to the diary folder).
  static bool isSyncPath(String p) => _syncPath.hasMatch(p);

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
        final sha = await gitBlobShaFile(f);
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

  /// Paths of entries in the plain mirror: `entries/2026/10/2026-10-25-0941-утро.md`. Entries that
  /// would share a path (same minute and title) get `-2`, `-3`… in creation order, so none is lost.
  static Map<String, String> plainEntryPaths(Iterable<Entry> entries) {
    final sorted = entries.toList()
      ..sort((a, b) => a.created != b.created ? a.created.compareTo(b.created) : a.id.compareTo(b.id));
    final used = <String>{};
    final out = <String, String>{};
    for (final e in sorted) {
      final t = e.created.toLocal();
      final base = 'entries/${t.year}/${t.month.toString().padLeft(2, '0')}/${entrySlug(e)}';
      var path = '$base.md';
      for (var n = 2; !used.add(path); n++) {
        path = '$base-$n.md';
      }
      out[e.id] = path;
    }
    return out;
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
    // Plain Markdown in a public repository would publish the diary: refuse every time, the
    // repository may have been made public after it was connected.
    if (!await remote.isPrivate()) throw SyncException('public_repo');
    final report = SyncReport();
    final state = await _loadState();
    final snap = await remote.snapshot();
    final texts = <String, Uint8List>{};
    final media = <String, BlobSource>{};
    final keep = <String>{};
    final paths = plainEntryPaths(store.entries);
    for (final e in store.entries) {
      final atts = {for (final a in e.attachments) a.id: a};
      texts[paths[e.id]!] = Uint8List.fromList(utf8.encode(plainMarkdown(e, atts)));
      for (final a in e.attachments) {
        final p = plainMediaPath(a);
        keep.add(p);
        // Media never changes: once uploaded (and still there), it is not decrypted again.
        final known = state.hashes['plain:$p'];
        if (known != null && snap.files['$_prefix$p'] == known[2]) continue;
        if (!store.hasMedia(a.id)) continue;
        if (a.size > GitHubRepo.maxBlobBytes) {
          report.skipped.add(a.name);
          continue;
        }
        media[p] = () async {
          final bytes = await store.mediaBytes(a.id);
          state.hashes['plain:$p'] = [bytes.length, 0, gitBlobSha(bytes)];
          return bytes;
        };
      }
    }
    final put = <String, BlobSource>{};
    for (final e in texts.entries) {
      if (snap.files['$_prefix${e.key}'] != gitBlobSha(e.value)) {
        put['$_prefix${e.key}'] = bytesSource(e.value);
        report.uploaded++;
      }
    }
    for (final e in media.entries) {
      put['$_prefix${e.key}'] = e.value;
      report.uploaded++;
    }
    final remove = <String>{};
    for (final p in snap.files.keys) {
      if (!p.startsWith(_prefix)) continue;
      final rel = p.substring(_prefix.length);
      final managed = rel.startsWith('entries/') || rel.startsWith('media/');
      if (managed && !texts.containsKey(rel) && !keep.contains(rel)) {
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
