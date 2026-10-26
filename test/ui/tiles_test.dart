import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/l10n/strings.dart';
import 'package:letopis/main.dart';
import 'package:letopis/ui/entry_screen.dart';
import 'package:letopis/ui/settings/stats_screen.dart';
import 'package:letopis/ui/widgets/entry_card.dart';
import 'package:letopis/ui/widgets/entry_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('timeline switches between cards and tiles, the choice is remembered', (tester) async {
    final app = (await tester.runAsync(makeApp))!;
    await tester.runAsync(() async {
      await app.createVault('pw-pw-pw');
      await app.saveAll([
        Entry.create(at: DateTime(2026, 10, 1, 9))
          ..title = 'Море'
          ..body = 'И солнце #отдых'
          ..mood = 5,
        Entry.create(at: DateTime(2026, 10, 2, 9))..body = 'Работа над игрой',
      ]);
    });
    await tester.pumpWidget(LetopisApp(state: app));
    await settle(tester);
    expect(find.byType(EntryCard), findsNWidgets(2));
    expect(find.byType(EntryTile), findsNothing);

    await tester.tap(find.byTooltip(tr('view_tiles')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(EntryTile), findsNWidgets(2));
    expect(find.byType(EntryCard), findsNothing);
    expect(find.text('Море'), findsOneWidget);
    expect(find.text('#отдых'), findsOneWidget);
    expect(app.prefs.tiles, isTrue);
    expect((await tester.runAsync(SharedPreferences.getInstance))!.getBool('tiles'), isTrue);

    await tester.tap(find.text('Море'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('deleted entry can be brought back with Undo', (tester) async {
    final app = (await tester.runAsync(makeApp))!;
    late Entry e;
    await tester.runAsync(() async {
      await app.createVault('pw-pw-pw');
      e = Entry.create()..body = 'не удаляй меня';
      await app.saveAll([e]);
    });
    await tester.pumpWidget(LetopisApp(state: app));
    await settle(tester);
    await tester.tap(find.textContaining('не удаляй'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tr('delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, tr('delete')));
    await settle(tester, until: () => find.text(tr('moved_to_trash')).evaluate().isNotEmpty);
    expect(app.entries, isEmpty);
    expect(find.text(tr('moved_to_trash')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // snack bar slides in
    await tester.tap(find.text(tr('undo')));
    await settle(tester, until: () => app.entries.isNotEmpty && !app.busy);
    expect(app.entries.single.body, 'не удаляй меня');
    await tester.runAsync(app.lock); // flushes the index timer
    await tester.pump(const Duration(seconds: 5));
  });

  test('stats: totals, current and longest streak', () {
    Entry at(int m, int d) => Entry.create(at: DateTime(2026, m, d, 10))..body = 'раз два три';
    final s = DiaryStats.of([
      at(10, 1), at(10, 2), at(10, 3), // 3 days in a row
      at(10, 10), at(10, 10), // same day twice
      at(10, 24), at(10, 25),
    ], today: DateTime(2026, 10, 25, 20));
    expect(s.entries, 7);
    expect(s.words, 21);
    expect(s.days, 6);
    expect(s.longestStreak, 3);
    expect(s.streak, 2);
    expect(s.perMonth[DateTime(2026, 10)], 7);
    expect(s.first, DateTime(2026, 10, 1, 10));
  });
}
