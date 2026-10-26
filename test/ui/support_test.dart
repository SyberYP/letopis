import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/l10n/strings.dart';
import 'package:letopis/main.dart';
import 'package:letopis/services/channel.dart';
import 'package:letopis/services/support.dart';
import 'package:letopis/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

class FakeSupport implements SupportStore {
  FakeSupport({this.error, this.payError});
  final String? error;
  final String? payError;
  final paid = <String>[];
  var signIns = 0;

  @override
  Future<List<SupportOption>> options() async {
    if (error != null && signIns == 0) throw SupportException(error!);
    return const [
      SupportOption(id: 'support_99', title: 'Кофе', price: '99 ₽', amount: 9900),
      SupportOption(id: 'support_299', title: 'Обед', price: '299 ₽', amount: 29900),
    ];
  }

  @override
  Future<SupportResult> pay(String id, {required bool dark}) async {
    if (payError != null) throw SupportException(payError!);
    paid.add(id);
    return SupportResult.thanks;
  }

  @override
  Future<void> signIn() async => signIns++;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    buildChannel = '';
    supportStore = RuStoreSupport();
  });

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

  testWidgets('Google Play build has no support button', (tester) async {
    buildChannel = 'play';
    await openSettings(tester);
    expect(find.text(tr('support')), findsNothing);
  });

  testWidgets('site build explains CloudTips before leaving the app', (tester) async {
    buildChannel = 'site';
    await openSettings(tester);
    await tester.tap(find.text(tr('support')));
    await tester.pumpAndSettle();
    expect(find.text(tr('support_site_body')), findsOneWidget);
    await tester.tap(find.text(tr('cancel')));
    await tester.pumpAndSettle();
    expect(find.text(tr('support_site_body')), findsNothing);
  });

  testWidgets('RuStore build: pick an amount, pay, get a thank-you', (tester) async {
    buildChannel = 'rustore';
    final fake = FakeSupport();
    supportStore = fake;
    await openSettings(tester);
    await tester.tap(find.text(tr('support')));
    await tester.pumpAndSettle();
    expect(find.text(tr('support_store_body')), findsOneWidget);
    expect(find.text('99 ₽'), findsOneWidget);
    await tester.tap(find.text('299 ₽'));
    await tester.pumpAndSettle();
    expect(fake.paid, ['support_299']);
    expect(find.text(tr('support_thanks')), findsOneWidget);
    expect(find.byType(RuStoreSupportSheet), findsNothing);
  });

  testWidgets('RuStore build: not signed in offers to sign in, then shows amounts', (tester) async {
    buildChannel = 'rustore';
    final fake = FakeSupport(error: 'unauthorized');
    supportStore = fake;
    await openSettings(tester);
    await tester.tap(find.text(tr('support')));
    await tester.pumpAndSettle();
    expect(find.text(tr('support_err_unauthorized')), findsOneWidget);
    await tester.tap(find.text(tr('support_sign_in')));
    await tester.pumpAndSettle();
    expect(fake.signIns, 1);
    expect(find.text('99 ₽'), findsOneWidget);
  });

  testWidgets('RuStore build: a failed payment says so and keeps the sheet open', (tester) async {
    buildChannel = 'rustore';
    supportStore = FakeSupport(payError: 'failed');
    await openSettings(tester);
    await tester.tap(find.text(tr('support')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('99 ₽'));
    await tester.pumpAndSettle();
    expect(find.text(tr('support_err_failed')), findsOneWidget);
    expect(find.text(tr('support_retry')), findsOneWidget);
  });
}
