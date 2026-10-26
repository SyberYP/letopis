import 'package:flutter/services.dart' show appFlavor;

/// Where this build is distributed — the Android product flavor:
/// - `site`: APK on letopis.recalltwin.com — "Check for updates" and support via CloudTips;
/// - `rustore`: RuStore — support as a one-off RuStore payment, updates come from the store;
/// - `play`: Google Play — neither (store rules; payouts to Russian accounts are closed).
/// Not `const` so tests can switch it.
String buildChannel = appFlavor ?? '';

bool get siteBuild => buildChannel == 'site';
bool get rustoreBuild => buildChannel == 'rustore';
