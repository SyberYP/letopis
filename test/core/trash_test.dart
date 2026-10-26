import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/crypto.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/core/store.dart';

void main() {
  late Directory dir;
  late CryptoBox box;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('trash');
    box = CryptoBox(randomBytes(32));
  });
  tearDown(() => dir.delete(recursive: true));

  File f(String rel) => File('${dir.path}/$rel');

  Future<(EntryStore, Entry, Attachment)> withPhoto() async {
    final s = EntryStore(dir, box);
    final src = File('${dir.path}/note.txt')..writeAsStringSync('вложение');
    final a = await s.importMedia(src);
    final e = Entry.create()
      ..body = 'запись'
      ..attachments.add(a);
    await s.save(e);
    return (s, e, a);
  }

  test('delete moves to trash, restore brings entry and media back', () async {
    final (s, e, a) = await withPhoto();
    await s.delete(e.id);
    expect(s.entries, isEmpty);
    expect(f(EntryStore.entryPath(e.id)).existsSync(), isFalse);
    expect(f('trash/${EntryStore.entryPath(e.id)}').existsSync(), isTrue);
    expect(f('trash/${EntryStore.mediaPath(a.id)}').existsSync(), isTrue);
    // Trash is not synced: the sync listing never sees it.
    expect(await s.listSyncable(), isEmpty);

    // Survives a restart.
    final s2 = EntryStore(dir, box);
    await s2.load();
    expect(s2.trash.single.$1.id, e.id);

    final back = await s2.restore(e.id);
    expect(back?.body, 'запись');
    expect(s2.entries.single.id, e.id);
    expect(s2.trash, isEmpty);
    expect(s2.tombstones, isEmpty);
    expect(await s2.mediaBytes(a.id), utf8.encode('вложение'));
  });

  test('purge and empty delete for good', () async {
    final (s, e, a) = await withPhoto();
    await s.delete(e.id);
    await s.purge(e.id);
    expect(s.trash, isEmpty);
    expect(f('trash/${EntryStore.entryPath(e.id)}').existsSync(), isFalse);
    expect(f('trash/${EntryStore.mediaPath(a.id)}').existsSync(), isFalse);

    final e2 = Entry.create()..body = 'ещё';
    await s.save(e2);
    await s.delete(e2.id);
    await s.emptyTrash();
    expect(s.trash, isEmpty);
    expect(Directory('${dir.path}/trash').existsSync(), isFalse);
  });

  test('entries older than the limit are purged on load', () async {
    final s = EntryStore(dir, box);
    final e = Entry.create()..body = 'старое';
    await s.save(e);
    await s.delete(e.id);
    // Pretend it was deleted long ago.
    final j = (await s.readJson('trash'))!;
    (j['items'] as Map)[e.id]['d'] = DateTime.now().subtract(const Duration(days: 31)).toIso8601String();
    await s.writeJson('trash', j);
    final s2 = EntryStore(dir, box);
    await s2.load();
    expect(s2.trash, isEmpty);
    expect(f('trash/${EntryStore.entryPath(e.id)}').existsSync(), isFalse);
  });

  test('media shared with a live entry (conflict copy) is not taken away', () async {
    final (s, e, a) = await withPhoto();
    final copy = Entry.create()
      ..body = 'копия'
      ..attachments.add(a);
    await s.save(copy);
    await s.delete(e.id);
    expect(f(EntryStore.mediaPath(a.id)).existsSync(), isTrue);
    await s.purge(e.id);
    expect(await s.mediaBytes(a.id), utf8.encode('вложение'));
    // Old behaviour lost it on a permanent delete too.
    final other = Entry.create()
      ..body = 'третья'
      ..attachments.add(a);
    await s.save(other);
    await s.delete(other.id, toTrash: false);
    expect(f(EntryStore.mediaPath(a.id)).existsSync(), isTrue);
  });
}
