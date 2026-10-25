import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letopis/core/crypto.dart';
import 'package:letopis/state/app_state.dart';

const fastKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

/// No plugins in widget tests: biometrics off, secrets in memory.
class FakeDevice extends DeviceServices {
  final secrets = <String, String>{};
  bool biometricResult = true;

  @override
  Future<bool> canUseBiometrics() async => true;
  @override
  Future<bool> authenticate(String reason) async => biometricResult;
  @override
  Future<String?> readSecret(String key) async => secrets[key];
  @override
  Future<void> writeSecret(String key, String value) async => secrets[key] = value;
  @override
  Future<void> deleteSecret(String key) async => secrets.remove(key);
  @override
  Future<void> setSecureScreen(bool on) async {}
  @override
  String get deviceName => 'test';
}

Future<AppState> makeApp({String language = 'ru', ThemeModeSetting theme = ThemeModeSetting.light}) async {
  final dir = await Directory.systemTemp.createTemp('letopis_ui');
  final app = AppState(platform: FakeDevice(), kdf: fastKdf);
  await app.init(
    withPrefs: Prefs(language: language, themeMode: theme, secureScreen: false),
    dataDir: Directory('${dir.path}/data'),
    tempDir: Directory('${dir.path}/tmp'),
  );
  return app;
}

/// Real fonts so screenshots are readable (the test default draws boxes).
Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      if (File(f).existsSync()) loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
  await family('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold', 'Light', 'Italic', 'BoldItalic']) '$dir/Roboto-$w.ttf',
  ]);
  await family('MaterialIcons', ['$dir/MaterialIcons-Regular.otf']);
  await family('serif', [
    '/usr/share/fonts/truetype/noto/NotoSerif-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf',
    '/usr/share/fonts/truetype/noto/NotoSerif-SemiBold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf',
  ]);
}

/// Lets real IO and isolates finish, then renders. With [until], keeps going (up to ~5 s)
/// until the condition holds.
Future<void> settle(WidgetTester tester, {bool Function()? until, int rounds = 4}) async {
  for (var i = 0; i < (until == null ? rounds : 50); i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
    if (until != null && until()) break;
  }
  await tester.pump(const Duration(milliseconds: 400));
}
