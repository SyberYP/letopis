import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../core/store.dart';
import 'sync.dart';

/// Writes a plain (unencrypted) ZIP with the same layout as the plain git mirror. Media is
/// decrypted one file at a time into [outDir] and streamed into the archive.
Future<File> exportZip(EntryStore store, Directory outDir) async {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  await outDir.create(recursive: true);
  final out = File('${outDir.path}/letopis-${now.year}-${two(now.month)}-${two(now.day)}.zip');
  final zip = ZipFileEncoder()..create(out.path);
  try {
    final paths = SyncEngine.plainEntryPaths(store.entries);
    for (final e in store.entries) {
      final atts = {for (final a in e.attachments) a.id: a};
      final md = utf8.encode(SyncEngine.plainMarkdown(e, atts));
      zip.addArchiveFile(ArchiveFile(paths[e.id]!, md.length, md));
      for (final a in e.attachments) {
        if (!store.hasMedia(a.id)) continue;
        final tmp = File('${outDir.path}/${a.id}.part');
        await store.box.decryptFile(store.file(EntryStore.mediaPath(a.id)), tmp, context: 'media/${a.id}');
        await zip.addFile(tmp, SyncEngine.plainMediaPath(a), 0);
        await tmp.delete();
      }
    }
  } finally {
    await zip.close();
  }
  return out;
}
