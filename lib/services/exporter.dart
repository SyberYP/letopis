import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../core/store.dart';
import 'sync.dart';

/// Writes a plain (unencrypted) ZIP: the same layout as the plain git mirror.
Future<File> exportZip(EntryStore store, Directory outDir) async {
  final archive = Archive();
  for (final e in store.entries) {
    final atts = {for (final a in e.attachments) a.id: a};
    final md = utf8.encode(SyncEngine.plainMarkdown(e, atts));
    archive.addFile(ArchiveFile(SyncEngine.plainEntryPath(e), md.length, md));
    for (final a in e.attachments) {
      if (!store.hasMedia(a.id)) continue;
      final bytes = await store.mediaBytes(a.id);
      archive.addFile(ArchiveFile.noCompress(SyncEngine.plainMediaPath(a), bytes.length, bytes));
    }
  }
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  await outDir.create(recursive: true);
  final out = File('${outDir.path}/letopis-${now.year}-${two(now.month)}-${two(now.day)}.zip');
  await out.writeAsBytes(ZipEncoder().encode(archive));
  return out;
}
