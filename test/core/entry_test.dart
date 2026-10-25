import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/crypto.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/core/markdown_io.dart';
import 'package:letopis/core/store.dart';

void main() {
  group('hashtags', () {
    test('finds Cyrillic and Latin tags, ignores headings, code, links, numbers', () {
      const md = '# Заголовок\nСегодня #Семья и #work_life, #дочь-2026.\n'
          '`#code` ```\n#block\n``` [x](http://a.b/#anchor) #1 a#b #дочь-2026';
      expect(extractHashtags(md), ['семья', 'work_life', 'дочь-2026']);
    });
    test('normalizeTag', () {
      expect(normalizeTag(' #Новый Год '), 'новый_год');
      expect(normalizeTag('###'), isNull);
      expect(normalizeTag('мысль!'), 'мысль');
    });
    test('allTags merges explicit and body tags without duplicates', () {
      final e = Entry.create()
        ..tags = ['семья']
        ..body = 'текст #семья #работа';
      expect(e.allTags, ['семья', 'работа']);
    });
  });

  group('markdown io', () {
    test('round trip keeps every field', () {
      final e = Entry.create(at: DateTime(2026, 10, 25, 9, 41))
        ..title = 'Утро: "кофе" и --- тире'
        ..body = '**Жирный** текст\n\n---\n\nещё #тег'
        ..tags = ['семья', 'дочь']
        ..mood = 4
        ..attachments = [
          Attachment(id: newId(), type: AttachmentType.photo, name: 'IMG 1.jpg', mime: 'image/jpeg', size: 10),
          Attachment(id: newId(), type: AttachmentType.audio, name: 'voice.m4a', mime: 'audio/mp4', durationMs: 4200),
        ];
      final md = entryToMarkdown(e);
      final back = entryFromMarkdown(md);
      expect(back.id, e.id);
      expect(back.title, e.title);
      expect(back.body, e.body);
      expect(back.tags, e.tags);
      expect(back.mood, 4);
      expect(back.created.isAtSameMomentAs(e.created), isTrue);
      expect(back.attachments.map((a) => a.toJson()).toList(), e.attachments.map((a) => a.toJson()).toList());
      expect(back.sameContent(e), isTrue);
    });

    test('plain markdown without front matter', () {
      final t = DateTime(2020, 1, 2, 3, 4);
      final e = entryFromMarkdown('Просто текст\n---\nи линия', fallbackTime: t);
      expect(e.body, 'Просто текст\n---\nи линия');
      expect(e.created, t);
    });

    test('foreign front matter: date and comma tags', () {
      final e = entryFromMarkdown('---\ndate: 2024-05-01 10:00\ntags: a, Б\n---\nhi');
      expect(e.created, DateTime(2024, 5, 1, 10));
      expect(e.tags, ['a', 'б']);
      expect(e.body, 'hi');
    });

    test('isoWithOffset parses back to the same moment', () {
      final t = DateTime.now();
      expect(DateTime.parse(isoWithOffset(t)).difference(t).inSeconds.abs() < 1, isTrue);
    });

    test('slug and preview', () {
      final e = Entry.create(at: DateTime(2026, 10, 25, 9, 5))..body = '## Привет, мир!\nтекст';
      expect(entrySlug(e), '2026-10-25-0905-привет-мир');
      expect(e.displayTitle, 'Привет, мир!');
      expect(plainText('**a** [b](c) ![](att:x)'), 'a b ');
    });
  });

  group('store', () {
    late Directory dir;
    late CryptoBox box;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('store');
      box = CryptoBox(randomBytes(32));
    });
    tearDown(() => dir.delete(recursive: true));

    test('save, reload from disk, delete with tombstone', () async {
      final s = EntryStore(dir, box);
      final e = Entry.create()..body = 'секрет #тег';
      await s.save(e);
      final raw = await File('${dir.path}/${EntryStore.entryPath(e.id)}').readAsBytes();
      expect(utf8.decode(raw, allowMalformed: true).contains('секрет'), isFalse);

      final s2 = EntryStore(dir, box);
      await s2.load();
      expect(s2.entries.single.body, 'секрет #тег');
      expect(s2.tagCounts().single.key, 'тег');

      await s2.delete(e.id);
      final s3 = EntryStore(dir, box);
      await s3.load();
      expect(s3.entries, isEmpty);
      expect(s3.tombstones.keys, [e.id]);
    });

    test('media: encrypt, thumbnail, open, clear temp', () async {
      final s = EntryStore(dir, box);
      // 1x1 PNG
      final png = base64.decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
      final src = File('${dir.path}/p.png')..writeAsBytesSync(png);
      final a = await s.importMedia(src);
      expect(a.type, AttachmentType.photo);
      expect(a.mime, 'image/png');
      expect(await s.thumbnail(a.id), isNotNull);
      final open = await s.openMedia(a);
      expect(open.readAsBytesSync(), png);
      expect(await s.mediaBytes(a.id), png);
      expect(await s.listSyncable(), [EntryStore.mediaPath(a.id), EntryStore.thumbPath(a.id)]);
      await s.clearTemp();
      expect(open.existsSync(), isFalse);
    });

    test('damaged entry is skipped, not fatal', () async {
      final s = EntryStore(dir, box);
      await s.save(Entry.create()..body = 'ok');
      File('${dir.path}/entries/${newId()}.md.enc').writeAsBytesSync([1, 2, 3]);
      final s2 = EntryStore(dir, box);
      await s2.load();
      expect(s2.count, 1);
    });

    test('json settings', () async {
      final s = EntryStore(dir, box);
      await s.writeJson('settings', {'a': 1});
      expect(await s.readJson('settings'), {'a': 1});
      expect(await EntryStore(dir, CryptoBox(randomBytes(32))).readJson('settings'), isNull);
    });
  });
}
