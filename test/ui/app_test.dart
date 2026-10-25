import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/l10n/strings.dart';
import 'package:letopis/main.dart';
import 'package:letopis/ui/editor_screen.dart';
import 'package:letopis/ui/home_screen.dart';
import 'package:letopis/ui/lock_screen.dart';

import 'harness.dart';

void main() {
  testWidgets('setup → write an entry → it is in the timeline → lock → unlock', (tester) async {
    final app = (await tester.runAsync(makeApp))!;
    await tester.pumpWidget(LetopisApp(state: app));
    await tester.pump();
    expect(find.byType(SetupScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'секретная фраза');
    await tester.enterText(find.byType(TextField).at(1), 'секретная фраза');
    await tester.tap(find.text(tr('create_diary')));
    await settle(tester, until: () => app.unlocked);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(tr('empty_title')), findsOneWidget);

    await tester.tap(find.text(tr('new_entry')));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Первая запись');
    await tester.enterText(find.byType(TextField).at(1), 'Сегодня было **хорошо**. #семья');
    await tester.pump(const Duration(seconds: 2)); // autosave debounce
    await settle(tester, until: () => app.entries.isNotEmpty);
    expect(app.entries.single.title, 'Первая запись');
    expect(app.entries.single.allTags, ['семья']);

    await Navigator.of(tester.element(find.byType(EditorScreen))).maybePop();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Первая запись'), findsOneWidget);
    expect(find.text('#семья'), findsOneWidget);

    // Lock from the app bar, unlock with the password.
    await tester.tap(find.byTooltip(tr('lock_now')).first);
    await settle(tester, until: () => !app.unlocked);
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'не тот');
    await tester.tap(find.text(tr('unlock')));
    await settle(tester, until: () => find.text(tr('wrong_password')).evaluate().isNotEmpty);
    expect(find.text(tr('wrong_password')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'секретная фраза');
    await tester.tap(find.text(tr('unlock')));
    await settle(tester, until: () => app.unlocked);
    await tester.pumpAndSettle();
    expect(find.text('Первая запись'), findsOneWidget);
  });

  testWidgets('lock while editing saves the text and closes the editor', (tester) async {
    final app = (await tester.runAsync(makeApp))!;
    await tester.runAsync(() => app.createVault('pw-pw-pw'));
    await tester.pumpWidget(LetopisApp(state: app));
    await settle(tester);
    await tester.tap(find.text(tr('new_entry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'не потерять');
    await tester.runAsync(() => app.lock());
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect(find.byType(LockScreen), findsOneWidget);
    await tester.runAsync(() => app.unlock('pw-pw-pw'));
    expect(app.entries.single.body, 'не потерять');
  });

  testWidgets('search and tag filter narrow the timeline', (tester) async {
    final app = (await tester.runAsync(makeApp))!;
    await tester.runAsync(() async {
      await app.createVault('pw-pw-pw');
      await app.saveAll([
        Entry.create(at: DateTime(2026, 10, 1, 9))..body = 'Море и солнце #отдых',
        Entry.create(at: DateTime(2026, 10, 2, 9))..body = 'Работа над игрой #darkage',
      ]);
    });
    await tester.pumpWidget(LetopisApp(state: app));
    await settle(tester);
    expect(find.textContaining('Море'), findsOneWidget);
    expect(find.textContaining('Работа'), findsOneWidget);

    await tester.tap(find.byTooltip(tr('search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'игр');
    await tester.pumpAndSettle();
    expect(find.textContaining('Море'), findsNothing);
    expect(find.textContaining('игр', findRichText: true), findsWidgets);

    await tester.tap(find.byTooltip(tr('search')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('#отдых', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('Море'), findsOneWidget);
    expect(find.textContaining('Работа'), findsNothing);
  });

  test('every UI string exists in both languages', () {
    expect(strings['en']!.keys.toSet(), strings['ru']!.keys.toSet());
  });

  test('Russian plurals', () {
    Lang.code = 'ru';
    expect(plural('entries', 1), '1 запись');
    expect(plural('entries', 3), '3 записи');
    expect(plural('entries', 11), '11 записей');
    expect(plural('entries', 22), '22 записи');
    expect(plural('years_ago', 5), '5 лет назад');
  });
}
