// Renders store-style screenshots into docs/screenshots/. Opt-in:
//   SCREENSHOTS=1 flutter test test/ui/screenshots_test.dart --update-goldens
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:letopis/core/entry.dart';
import 'package:letopis/main.dart';
import 'package:letopis/state/app_state.dart';
import 'package:letopis/ui/calendar_view.dart';
import 'package:letopis/ui/editor_screen.dart';
import 'package:letopis/ui/entry_screen.dart';
import 'package:letopis/ui/settings/settings_screen.dart';
import 'package:letopis/ui/tags_view.dart';

import 'harness.dart';

final enabled = Platform.environment['SCREENSHOTS'] != null;

/// A soft "photo": sky gradient, sun and sea.
Uint8List fakePhoto(int seed) {
  final r = Random(seed);
  final im = img.Image(width: 900, height: 600);
  final top = [r.nextInt(80) + 120, r.nextInt(60) + 140, 230];
  final bottom = [250, r.nextInt(80) + 150, r.nextInt(60) + 90];
  for (var y = 0; y < 600; y++) {
    final t = y / 600;
    final c = img.ColorRgb8(
      (top[0] + (bottom[0] - top[0]) * t).round(),
      (top[1] + (bottom[1] - top[1]) * t).round(),
      (top[2] + (bottom[2] - top[2]) * t).round(),
    );
    img.drawLine(im, x1: 0, y1: y, x2: 899, y2: y, color: c);
  }
  img.fillCircle(im, x: 300 + r.nextInt(300), y: 330, radius: 70, color: img.ColorRgb8(255, 236, 170));
  img.fillRect(im, x1: 0, y1: 400, x2: 899, y2: 599, color: img.ColorRgb8(40, 90 + r.nextInt(40), 150));
  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}

Future<AppState> seeded({ThemeModeSetting theme = ThemeModeSetting.light, String lang = 'ru'}) async {
  final app = await makeApp(theme: theme, language: lang);
  await app.createVault('screenshot');
  final now = DateTime.now();
  final dir = await Directory.systemTemp.createTemp('shots');
  Future<Attachment> photo(int seed) async {
    final f = File('${dir.path}/p$seed.jpg')..writeAsBytesSync(fakePhoto(seed));
    return app.store!.importMedia(f, name: 'IMG_$seed.jpg');
  }

  Future<Attachment> voice() async {
    final f = File('${dir.path}/v.m4a')..writeAsBytesSync(List.filled(2000, 1));
    return app.store!.importMedia(f, name: 'Голос 18:40.m4a', durationMs: 42000);
  }

  DateTime d(int daysAgo, int h, int m) => DateTime(now.year, now.month, now.day - daysAgo, h, m);
  final entries = [
    Entry.create(at: d(0, 8, 15))
      ..title = 'Утро у моря'
      ..body =
          'Проснулся раньше будильника и пошёл к морю. Вода спокойная, почти никого. '
          'Думал о том, как изменится жизнь через пару недель.\n\n> Главное — не торопиться.\n\n#утро #море'
      ..attachments.addAll([await photo(1), await photo(2)]),
    Entry.create(at: d(0, 21, 40))
      ..title = 'План на неделю'
      ..body = '- [x] Собрать сумку в роддом\n- [ ] Позвонить родителям\n- [ ] Дописать главу\n\n#семья #планы'
      ..tags = ['планы'],
    Entry.create(at: d(1, 18, 40))
      ..body =
          'Записал голосовую заметку по дороге домой — идея для игры: карточки событий, которые '
          'меняют правила матча. #идеи #игра'
      ..attachments.add(await voice()),
    Entry.create(at: d(3, 23, 5))
      ..title = 'Звёзды'
      ..body = 'Небо сегодня невероятно ясное. Видно Млечный Путь. Хочется однажды показать это дочери. #космос'
      ..attachments.add(await photo(3)),
    Entry.create(at: d(9, 12, 0))
      ..title = 'Прочитал главу о Римской империи'
      ..body = 'История повторяется не буквально, а рифмами. #книги #история',
    Entry.create(at: DateTime(now.year - 3, now.month, now.day, 19, 30))
      ..title = 'Первый день в новом городе'
      ..body = 'Снял комнату, вышел на набережную. Всё впереди.'
      ..attachments.add(await photo(4)),
    Entry.create(at: DateTime(now.year - 7, now.month, now.day, 22, 10))
      ..body = 'Сдал последний экзамен. Красный диплом — мой. #учёба',
  ];
  await app.saveAll(entries);
  return app;
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, rounds: 8);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../docs/screenshots/$name.png'));
}

void main() {
  setUpAll(loadFonts);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
  }

  testWidgets('screenshots', (tester) async {
    debugDisableShadows = false;
    phone(tester);
    final app = (await tester.runAsync(seeded))!;
    await tester.pumpWidget(LetopisApp(state: app));
    await shot(tester, '1-timeline');

    final first = app.entries.first;
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => EntryScreen(entryId: app.entries[1].id)));
    await shot(tester, '2-entry');
    nav.pop();
    await tester.pumpAndSettle();

    nav.push(MaterialPageRoute(builder: (_) => EditorScreen(entry: first)));
    await shot(tester, '3-editor');
    nav.pop();
    await tester.pumpAndSettle();

    nav.push(
      MaterialPageRoute(
        builder: (_) => Scaffold(body: CalendarView(onTag: (_) {})),
      ),
    );
    await shot(tester, '4-calendar');
    nav.pop();
    await tester.pumpAndSettle();

    nav.push(
      MaterialPageRoute(
        builder: (_) => Scaffold(body: TagsView(onTag: (_) {})),
      ),
    );
    await shot(tester, '5-tags');
    nav.pop();
    await tester.pumpAndSettle();

    nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await shot(tester, '6-settings');
    nav.pop();
    await tester.pumpAndSettle();

    await tester.runAsync(() => app.lock());
    await shot(tester, '7-lock');
    debugDisableShadows = true;
    addTearDown(tester.view.reset);
  }, skip: !enabled);

  testWidgets('dark screenshots', (tester) async {
    debugDisableShadows = false;
    phone(tester);
    final app = (await tester.runAsync(() => seeded(theme: ThemeModeSetting.dark)))!;
    await tester.pumpWidget(LetopisApp(state: app));
    await shot(tester, '8-timeline-dark');
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => EntryScreen(entryId: app.entries.first.id)));
    await shot(tester, '9-entry-dark');
    debugDisableShadows = true;
    addTearDown(tester.view.reset);
  }, skip: !enabled);
}
