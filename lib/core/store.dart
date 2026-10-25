import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'crypto.dart';
import 'entry.dart';
import 'markdown_io.dart';
import 'vault.dart';

/// Encrypted files on disk, the same layout as the encrypted git mirror:
///
///   vault.json, settings.enc, tombstones.enc, sync.enc (device only)
///   `entries/<id>.md.enc`, `media/<id>.enc`, `thumbs/<id>.enc`
///
/// All entries are decrypted into memory on unlock; media stays encrypted until opened.
class EntryStore {
  EntryStore(this.root, this.box, {Directory? tempDir}) : tempDir = tempDir ?? Directory('${root.path}/.tmp');

  final Directory root;
  final CryptoBox box;

  /// Decrypted media for playback; emptied on lock.
  final Directory tempDir;

  final Map<String, Entry> _entries = {};
  final Map<String, DateTime> _tombstones = {};
  final Map<String, Uint8List> _thumbCache = {};
  final Map<String, File> _openCache = {};

  static File vaultFile(Directory root) => File('${root.path}/vault.json');

  static Future<VaultFile?> readVault(Directory root) async {
    final f = vaultFile(root);
    if (!await f.exists()) return null;
    return VaultFile.decode(await f.readAsString());
  }

  static Future<void> writeVault(Directory root, VaultFile v) async {
    await root.create(recursive: true);
    await _atomicWrite(vaultFile(root), utf8.encode(v.encode()));
  }

  // ---- paths -------------------------------------------------------------------------------

  static String entryPath(String id) => 'entries/$id.md.enc';
  static String mediaPath(String id) => 'media/$id.enc';
  static String thumbPath(String id) => 'thumbs/$id.enc';

  /// The context bound into each ciphertext: the path without the extension.
  static String contextFor(String relPath) => relPath.replaceAll(RegExp(r'(\.md)?\.enc$'), '');

  File file(String relPath) => File('${root.path}/$relPath');

  // ---- entries -----------------------------------------------------------------------------

  /// Entries, newest first.
  List<Entry> get entries => _entries.values.toList()..sort((a, b) => b.created.compareTo(a.created));

  Entry? byId(String id) => _entries[id];
  Map<String, DateTime> get tombstones => Map.unmodifiable(_tombstones);
  int get count => _entries.length;

  /// On-device index (`index.enc`, never synced): every entry with the size and mtime of its
  /// file, so unlock decrypts one file instead of thousands. Files that changed since (sync,
  /// another app version) are decrypted individually and the index is refreshed.
  Map<String, Map<String, dynamic>> _index = {};
  Timer? _indexTimer;
  bool _indexDirty = false;

  Future<void> load() async {
    _entries.clear();
    final cached = ((await readJson('index'))?['files'] as Map?) ?? const {};
    final fresh = <String, Map<String, dynamic>>{};
    var dirty = false;
    final dir = Directory('${root.path}/entries');
    if (await dir.exists()) {
      final files = await dir.list().where((f) => f.path.endsWith('.md.enc')).cast<File>().toList();
      for (var i = 0; i < files.length; i += 32) {
        final batch = files.skip(i).take(32);
        final loaded = await Future.wait(
          batch.map((f) async {
            final id = f.uri.pathSegments.last.replaceAll('.md.enc', '');
            final stat = await f.stat();
            final c = cached[id];
            if (c is Map && c['m'] == stat.modified.millisecondsSinceEpoch && c['s'] == stat.size) {
              try {
                return (Entry.fromJson(c['e'] as Map), stat, false);
              } catch (_) {
                // fall through to the file
              }
            }
            return (await _readEntryFile(f), stat, true);
          }),
        );
        for (final (e, stat, changed) in loaded) {
          if (e == null) continue;
          _entries[e.id] = e;
          fresh[e.id] = _indexItem(e, stat);
          dirty |= changed;
        }
      }
    }
    _index = fresh;
    if (dirty || cached.length != fresh.length) await flushIndex(force: true);
    _tombstones.clear();
    final t = await readJson('tombstones');
    t?.forEach((k, v) {
      final d = DateTime.tryParse('$v');
      if (d != null) _tombstones[k] = d;
    });
  }

  Future<Entry?> _readEntryFile(File f) async {
    final id = f.uri.pathSegments.last.replaceAll('.md.enc', '');
    try {
      final clear = await box.decrypt(await f.readAsBytes(), context: 'entries/$id');
      return entryFromMarkdown(utf8.decode(clear), fallbackId: id);
    } on DecryptionException {
      return null; // a damaged file must not lock the user out of the rest
    }
  }

  static Map<String, dynamic> _indexItem(Entry e, FileStat stat) => {
    'm': stat.modified.millisecondsSinceEpoch,
    's': stat.size,
    'e': e.toJson(),
  };

  Future<void> _indexChanged(String id) async {
    final e = _entries[id];
    if (e == null) {
      _index.remove(id);
    } else {
      _index[id] = _indexItem(e, await file(entryPath(id)).stat());
    }
    _indexDirty = true;
    _indexTimer?.cancel();
    _indexTimer = Timer(const Duration(seconds: 3), () => flushIndex().catchError((_) {}));
  }

  /// Writes the index if it changed; called on a timer and before lock.
  Future<void> flushIndex({bool force = false}) async {
    _indexTimer?.cancel();
    if (!force && !_indexDirty) return;
    _indexDirty = false;
    await writeJson('index', {'v': 1, 'files': _index});
  }

  /// Re-reads one entry from disk (after sync replaced the file).
  Future<Entry?> reload(String id) async {
    final f = file(entryPath(id));
    if (!await f.exists()) {
      _entries.remove(id);
      await _indexChanged(id);
      return null;
    }
    final e = await _readEntryFile(f);
    if (e != null) {
      _entries[id] = e;
      await _indexChanged(id);
    }
    return e;
  }

  Future<void> save(Entry e, {bool touch = true}) async {
    if (touch) e.updated = DateTime.now();
    final clear = utf8.encode(entryToMarkdown(e));
    await _writeEncrypted(entryPath(e.id), clear);
    _entries[e.id] = e.copy();
    await _indexChanged(e.id);
  }

  /// Deletes the entry, its media, and remembers a tombstone so sync deletes it elsewhere.
  Future<void> delete(String id) async {
    final e = _entries.remove(id);
    await _deleteIfExists(entryPath(id));
    await _indexChanged(id);
    for (final a in e?.attachments ?? const <Attachment>[]) {
      await deleteMedia(a.id);
    }
    _tombstones[id] = DateTime.now();
    await writeJson('tombstones', {for (final t in _tombstones.entries) t.key: t.value.toIso8601String()});
  }

  /// Applies a tombstone received from sync.
  Future<void> applyTombstone(String id, DateTime at) async {
    final e = _entries[id];
    if (e != null && e.updated.isAfter(at)) return; // edited here after the delete: keep it
    if (e != null) await delete(id);
    _tombstones[id] = at;
    await writeJson('tombstones', {for (final t in _tombstones.entries) t.key: t.value.toIso8601String()});
  }

  /// All tags with the number of entries using them, most used first.
  List<MapEntry<String, int>> tagCounts() {
    final counts = <String, int>{};
    for (final e in _entries.values) {
      for (final t in e.allTags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts.entries.toList()
      ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  }

  // ---- media -------------------------------------------------------------------------------

  /// Encrypts [source] into the store. Photos also get an encrypted thumbnail.
  Future<Attachment> importMedia(
    File source, {
    String? name,
    String? mime,
    int? durationMs,
    bool deleteSource = false,
  }) async {
    final id = newId();
    final fileName = name ?? source.uri.pathSegments.last;
    final type = mime ?? mimeFromName(fileName);
    final size = await source.length();
    await Directory('${root.path}/media').create(recursive: true);
    await box.encryptFile(source, file(mediaPath(id)), context: 'media/$id');
    final a = Attachment(
      id: id,
      type: AttachmentType.fromMime(type),
      name: fileName,
      mime: type,
      size: size,
      durationMs: durationMs,
    );
    if (a.type == AttachmentType.photo) {
      final thumb = await makeThumbnail(await source.readAsBytes());
      if (thumb != null) {
        await _writeEncrypted(thumbPath(id), thumb);
        _thumbCache[id] = thumb;
      }
    }
    if (deleteSource) await source.delete();
    return a;
  }

  Future<void> deleteMedia(String id) async {
    await _deleteIfExists(mediaPath(id));
    await _deleteIfExists(thumbPath(id));
    _thumbCache.remove(id);
    final open = _openCache.remove(id);
    if (open != null && await open.exists()) await open.delete();
  }

  bool hasMedia(String id) => file(mediaPath(id)).existsSync();

  /// Decrypts an attachment into the temp folder (cached until lock) and returns the file.
  Future<File> openMedia(Attachment a) async {
    final cached = _openCache[a.id];
    if (cached != null && await cached.exists()) return cached;
    await tempDir.create(recursive: true);
    final out = File('${tempDir.path}/${a.id}.${a.extension}');
    await box.decryptFile(file(mediaPath(a.id)), out, context: 'media/${a.id}');
    _openCache[a.id] = out;
    return out;
  }

  /// Decrypted media bytes (for photos shown in full).
  Future<Uint8List> mediaBytes(String id) async =>
      box.decrypt(await file(mediaPath(id)).readAsBytes(), context: 'media/$id');

  Uint8List? cachedThumbnail(String id) => _thumbCache[id];

  Future<Uint8List?> thumbnail(String id) async {
    final cached = _thumbCache[id];
    if (cached != null) return cached;
    final f = file(thumbPath(id));
    if (!await f.exists()) return null;
    try {
      final bytes = await box.decrypt(await f.readAsBytes(), context: 'thumbs/$id');
      _thumbCache[id] = bytes;
      return bytes;
    } on DecryptionException {
      return null;
    }
  }

  /// Wipes decrypted temp files and caches (on lock).
  Future<void> clearTemp() async {
    _thumbCache.clear();
    _openCache.clear();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }

  // ---- small encrypted json files -----------------------------------------------------------

  Future<Map<String, dynamic>?> readJson(String name) async {
    final f = file('$name.enc');
    if (!await f.exists()) return null;
    try {
      final clear = await box.decrypt(await f.readAsBytes(), context: name);
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } on DecryptionException {
      return null;
    }
  }

  Future<void> writeJson(String name, Map<String, dynamic> data) =>
      _writeEncrypted('$name.enc', utf8.encode(jsonEncode(data)));

  // ---- raw access for sync -----------------------------------------------------------------

  /// Relative paths of every syncable file (entries, media, thumbs, tombstones).
  Future<List<String>> listSyncable() async {
    final out = <String>[];
    for (final d in ['entries', 'media', 'thumbs']) {
      final dir = Directory('${root.path}/$d');
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.enc')) out.add('$d/${f.uri.pathSegments.last}');
      }
    }
    return out..sort();
  }

  Future<void> writeRaw(String relPath, List<int> bytes) async {
    await _atomicWrite(file(relPath), bytes);
    if (relPath.startsWith('thumbs/')) _thumbCache.remove(relPath.substring(7).replaceAll('.enc', ''));
  }

  Future<void> _writeEncrypted(String relPath, List<int> clear) async {
    final blob = await box.encrypt(clear, context: contextFor(relPath));
    await _atomicWrite(file(relPath), blob);
  }

  Future<void> _deleteIfExists(String relPath) async {
    final f = file(relPath);
    if (await f.exists()) await f.delete();
  }

  static Future<void> _atomicWrite(File f, List<int> bytes) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }
}

const _mimes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  '3gp': 'video/3gpp',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'mp3': 'audio/mpeg',
  'ogg': 'audio/ogg',
  'opus': 'audio/opus',
  'wav': 'audio/wav',
  'flac': 'audio/flac',
  'md': 'text/markdown',
  'txt': 'text/plain',
  'pdf': 'application/pdf',
};

String mimeFromName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return 'application/octet-stream';
  return _mimes[name.substring(dot + 1).toLowerCase()] ?? 'application/octet-stream';
}

/// JPEG thumbnail ≤ [maxSide] px, made in a background isolate. Null if the image can't be read.
Future<Uint8List?> makeThumbnail(Uint8List bytes, {int maxSide = 480}) => Isolate.run(() {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final w = oriented.width, h = oriented.height;
  final scaled = w >= h
      ? img.copyResize(oriented, width: w > maxSide ? maxSide : w)
      : img.copyResize(oriented, height: h > maxSide ? maxSide : h);
  return Uint8List.fromList(img.encodeJpg(scaled, quality: 80));
});
