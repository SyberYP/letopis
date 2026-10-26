import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/l10n/strings.dart';
import 'package:letopis/main.dart';
import 'package:letopis/services/update_check.dart';
import 'package:letopis/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => siteBuild = false);

  Future<void> openSettings(WidgetTester tester) async {
    final app = (await tester.runAsync(makeApp))!;
    await tester.runAsync(() => app.createVault('pw-pw-pw'));
    await tester.pumpWidget(LetopisApp(state: app));
    await settle(tester);
    tester.state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(tr('licenses')), 300, scrollable: find.byType(Scrollable).last);
  }

  testWidgets('store builds have no update button', (tester) async {
    siteBuild = false;
    await openSettings(tester);
    expect(find.text(tr('update_check')), findsNothing);
  });

  testWidgets('site build checks only on tap and reports a failed check', (tester) async {
    siteBuild = true;
    await openSettings(tester);
    expect(find.text(tr('update_check')), findsOneWidget);
    // The test binding answers every HTTP request with 400: the check must fail politely.
    await tester.tap(find.text(tr('update_check')));
    await settle(tester, until: () => find.text(tr('update_error')).evaluate().isNotEmpty);
    expect(find.text(tr('update_error')), findsOneWidget);
  });
}
