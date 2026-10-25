import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/strings.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState()..init();
  runApp(LetopisApp(state: app));
}

class LetopisApp extends StatelessWidget {
  const LetopisApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: Consumer<AppState>(
        builder: (context, app, _) {
          if (!app.ready) {
            return const MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold());
          }
          final p = app.prefs;
          return MaterialApp(
            title: tr('app_name'),
            debugShowCheckedModeBanner: false,
            navigatorKey: _Gate.navigatorKey,
            theme: buildTheme(Brightness.light, p.accent),
            darkTheme: buildTheme(Brightness.dark, p.accent),
            themeMode: switch (p.themeMode) {
              ThemeModeSetting.system => ThemeMode.system,
              ThemeModeSetting.light => ThemeMode.light,
              ThemeModeSetting.dark => ThemeMode.dark,
            },
            locale: Locale(p.language),
            supportedLocales: const [Locale('ru'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const _Gate(),
          );
        },
      ),
    );
  }
}

/// Setup → lock → home. On lock every route above home is closed, so nothing decrypted
/// stays on screen.
class _Gate extends StatefulWidget {
  const _Gate();
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _wasUnlocked = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_wasUnlocked && !app.unlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _Gate.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      });
    }
    _wasUnlocked = app.unlocked;
    final Widget child;
    if (!app.hasVault) {
      child = const SetupScreen(key: ValueKey('setup'));
    } else if (!app.unlocked) {
      child = const LockScreen(key: ValueKey('lock'));
    } else {
      child = const HomeScreen(key: ValueKey('home'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child);
  }
}
