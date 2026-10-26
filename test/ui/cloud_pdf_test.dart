import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/entry.dart';
import 'package:letopis/l10n/strings.dart';
import 'package:letopis/main.dart';
import 'package:letopis/services/git_remote.dart';
import 'package:letopis/services/webdav_remote.dart';
import 'package:letopis/state/app_state.dart';
import 'package:letopis/ui/settings/cloud_settings_screen.dart';
import 'package:letopis/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppState> openSettings(WidgetTester tester) async {
    final app = (await tester.runAsync(makeApp))!;
    await tester.runAsync(() => app.createVault('pw-pw-pw'));
    await tester.runAsync(() => app.saveAll([
      Entry.create(at: DateTime(2025, 3, 1))..body = 'старая',
      Entry.create(at: DateTime(2026, 10, 26))..body = 'новая',
    ]));
    await tester.pumpWidget(LetopisApp(state: app));
    await settle(tester);
    tester.state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('cloud: presets, HTTPS only, connecting switches GitHub off', (tester) async {
    final app = await openSettings(tester);
    app.git = const GitHubConfig(owner: 'o', repo: 'r', token: 't');
    await tester.scrollUntilVisible(find.text(tr('dav_title')), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(tr('dav_title')));
    await tester.pumpAndSettle();
    expect(find.byType(CloudSettingsScreen), findsOneWidget);
    expect(find.text(tr('dav_replaces_git')), findsOneWidget);
    expect(find.text('https://webdav.yandex.ru'), findsOneWidget); // Yandex is the default

    await tester.tap(find.text(tr('dav_p_other')));
    await tester.pumpAndSettle();
    expect(find.text(tr('dav_help_other')), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'http://cloud.example.com/dav');
    await tester.pumpAndSettle();
    expect(find.text(tr('dav_err_https_only')), findsOneWidget);

    await tester.enterText(fields.at(0), 'https://cloud.example.com/dav');
    await tester.enterText(fields.at(1), 'me');
    await tester.enterText(fields.at(2), 'app-password');
    await tester.pumpAndSettle();
    expect(find.text(tr('dav_err_https_only')), findsNothing);

    // Leaving the screen saves: one sync target at a time.
    Navigator.of(tester.element(find.byType(CloudSettingsScreen))).pop();
    await tester.pumpAndSettle();
    // The settings file is written for real; then the list rebuilds.
    await settle(tester, rounds: 8);
    expect(app.dav.isConfigured, isTrue);
    expect(app.dav.url, 'https://cloud.example.com/dav');
    expect(app.git.isConfigured, isFalse);
    expect(app.syncTarget, isA<WebDavConfig>());
    expect(find.textContaining('cloud.example.com'), findsOneWidget);
  });

  testWidgets('PDF: choose the period and photos, entry count follows', (tester) async {
    await openSettings(tester);
    await tester.scrollUntilVisible(find.text(tr('pdf')), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(tr('pdf')));
    await tester.pumpAndSettle();
    expect(find.text(tr('pdf_all')), findsOneWidget);
    expect(find.text(plural('entries', 2)), findsOneWidget);
    expect(find.text(tr('pdf_warning')), findsOneWidget);

    await tester.tap(find.text(tr('pdf_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025').last);
    await tester.pumpAndSettle();
    expect(find.text(plural('entries', 1)), findsOneWidget);

    await tester.tap(find.text(tr('cancel')));
    await tester.pumpAndSettle();
    expect(find.text(tr('pdf_warning')), findsNothing);
  });
}
