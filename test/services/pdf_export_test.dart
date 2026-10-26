import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:letopis/core/crypto.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/core/store.dart';
import 'package:letopis/core/vault.dart';
import 'package:letopis/services/pdf_export.dart';

const fastKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

PdfFonts fonts() {
  Uint8List f(String n) => File('assets/fonts/$n').readAsBytesSync();
  return PdfFonts(
    regular: f('PT_Serif-Web-Regular.ttf'),
    bold: f('PT_Serif-Web-Bold.ttf'),
    italic: f('PT_Serif-Web-Italic.ttf'),
    emoji: f('NotoEmoji.ttf'),
  );
}

Uint8List photo(int seed) {
  final im = img.Image(width: 640, height: 420);
  img.fill(im, color: img.ColorRgb8(90 + seed * 40, 150, 220 - seed * 30));
  img.fillCircle(im, x: 320, y: 200, radius: 90, color: img.ColorRgb8(255, 230, 160));
  return Uint8List.fromList(img.encodeJpg(im));
}

final text = PdfText(
  month: (t) => 'Месяц ${t.month}.${t.year}',
  date: (t) => '${t.day}.${t.month}.${t.year} · ${t.hour}:${t.minute.toString().padLeft(2, '0')}',
  mood: (m) => 'Настроение: $m из 5',
  attachment: (a) => '${a.type.name} · ${a.name}',
);

void main() {
  test('builds a book with formatting, photos, emoji and a page-long entry', () async {
    final long = List.generate(60, (i) => 'Очень длинный абзац номер $i, в котором много слов о жизни, море и звёздах.').join(' ');
    final entries = [
      PdfEntry(
        month: 'Октябрь 2026',
        date: 'понедельник, 26 октября 2026 · 08:15',
        title: 'Утро у моря',
        body: '# Заголовок\n\nПроснулся **раньше** будильника и пошёл к *морю*. ~~Шумно~~ Тихо 🌊🙂.\n\n'
            '> Главное — не торопиться.\n\n- [x] Собрать сумку\n- [ ] Позвонить родителям\n\n1. Раз\n2. Два\n\n'
            '![фото](att:p1)\n\nТекст после фото и `код`.\n\n| Что | Сколько |\n|---|---|\n| Кофе | 2 |\n\n---\n\n#утро',
        mood: 'Настроение: хорошо',
        tags: ['утро', 'море'],
        images: {'p1': photo(1), 'p2': photo(2), 'p3': photo(3)},
        gallery: ['p2', 'p3'],
        files: ['Голосовая запись · Голос 18:40.m4a · 0:42'],
      ),
      PdfEntry(month: 'Октябрь 2026', date: '27 октября 2026 · 23:05', title: '', body: long),
      PdfEntry(month: 'Ноябрь 2026', date: '1 ноября 2026 · 10:00', title: 'Без текста', body: ''),
    ];
    final bytes = await buildPdf(
      PdfBook(title: 'Летопись', subtitle: '2026', note: '3 записи · 26.10.2026', entries: entries, fonts: fonts()),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final pages = RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length;
    expect(pages, greaterThanOrEqualTo(4), reason: 'cover + entries + the long one spans pages');
    if (Platform.environment['PDF_PREVIEW'] != null) {
      File('build/pdf-preview.pdf').writeAsBytesSync(bytes);
    }
  });

  test('prepares entries from the store: photos optional, other files listed, oldest first', () async {
    final dir = await Directory.systemTemp.createTemp('pdf');
    final (vault, box) = await VaultFile.create('pw', kdf: fastKdf);
    await EntryStore.writeVault(dir, vault);
    final store = EntryStore(dir, CryptoBox(box.keyBytes));
    await store.load();
    final src = File('${dir.path}/a.jpg')..writeAsBytesSync(photo(1));
    final voice = File('${dir.path}/v.m4a')..writeAsBytesSync(List.filled(100, 1));
    final newer = Entry.create(at: DateTime(2026, 10, 26, 8, 15))
      ..title = 'Новая'
      ..mood = 4
      ..attachments.add(await store.importMedia(src));
    final older = Entry.create(at: DateTime(2025, 1, 2, 9))
      ..body = 'Старая ![](att:x) #тег'
      ..attachments.add(await store.importMedia(voice, name: 'Голос.m4a'));
    await store.save(newer);
    await store.save(older);

    final withPhotos = await preparePdfEntries(store, [newer, older], photos: true, text: text);
    expect(withPhotos.map((e) => e.title), ['', 'Новая']);
    expect(withPhotos[0].files, ['audio · Голос.m4a']);
    expect(withPhotos[0].tags, ['тег']);
    expect(withPhotos[1].images, hasLength(1));
    expect(withPhotos[1].gallery, hasLength(1));
    expect(withPhotos[1].mood, 'Настроение: 4 из 5');

    final noPhotos = await preparePdfEntries(store, [newer], photos: false, text: text);
    expect(noPhotos.single.images, isEmpty);
    expect(noPhotos.single.gallery, isEmpty);
  });
}
