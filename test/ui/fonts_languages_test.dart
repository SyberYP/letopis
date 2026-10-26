import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/l10n/strings.dart';
import 'package:letopis/main.dart';
import 'package:letopis/state/app_state.dart';
import 'package:letopis/ui/settings/settings_screen.dart';
import 'package:letopis/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    Lang.code = 'ru';
    Fonts.current = AppFont.classic;
  });

  Future<AppState> openSettings(WidgetTester tester) async {
    final app = (await tester.runAsync(makeApp))!;
    await tester.runAsync(() => app.createVault('pw-pw-pw'));
    await tester.runAsync(() => app.saveAll([Entry.create(at: DateTime(2026, 10, 26))..body = 'запись']));
    await tester.pumpWidget(LetopisApp(state: app));
    await settle(tester);
    tester.state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await tester.pumpAndSettle();
    return app;
  }

  test('every font has a theme and PDF files', () {
    for (final f in AppFont.values) {
      final theme = buildTheme(Brightness.light, 0, f);
      final face = fontChoices[f]!;
      expect(theme.textTheme.bodyLarge?.fontFamily, face.body ?? isNot('Caveat'), reason: f.name);
      expect(face.pdf.$1, endsWith('.ttf'));
    }
    expect(buildTheme(Brightness.light, 0, AppFont.classic).textTheme.titleLarge?.fontFamily, 'serif');
    expect(buildTheme(Brightness.light, 0, AppFont.hand).textTheme.bodyLarge!.fontSize,
        greaterThan(buildTheme(Brightness.light, 0).textTheme.bodyLarge!.fontSize!));
  });

  testWidgets('font picker changes the whole app and is remembered', (tester) async {
    final app = await openSettings(tester);
    await tester.tap(find.text(tr('font')));
    await tester.pumpAndSettle();
    for (final f in AppFont.values) {
      expect(find.text(tr('font_${f.name}')), findsWidgets);
    }
    await tester.tap(find.text(tr('font_hand')).last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(app.prefs.font, AppFont.hand);
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).textTheme.bodyLarge?.fontFamily, 'Caveat');
    expect((await tester.runAsync(Prefs.load))!.font, AppFont.hand);
  });

  testWidgets('language picker lists 15 languages; Arabic turns the app right to left', (tester) async {
    final app = await openSettings(tester);
    expect(languages, hasLength(15));
    await tester.tap(find.text(tr('language')));
    await tester.pumpAndSettle();
    expect(find.text('中文（简体）'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('العربية'), 100, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(app.prefs.language, 'ar');
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(SettingsScreen))), TextDirection.rtl);

    await tester.tap(find.text('اللغة'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Deutsch'), 100, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(SettingsScreen))), TextDirection.ltr);

    // The home screen underneath follows the language too.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.text('Neuer Eintrag'), findsOneWidget);
    expect(find.text('Kalender'), findsOneWidget);
  });
}
