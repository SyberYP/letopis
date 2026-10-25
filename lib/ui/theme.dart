import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Accent seeds offered in the settings.
const accents = <Color>[
  Color(0xFF5B5BD6), // indigo
  Color(0xFF8C6A3F), // parchment / sepia
  Color(0xFF2F8F83), // teal
  Color(0xFFC2185B), // rose
  Color(0xFF3E7D3A), // forest
  Color(0xFF455A87), // slate
];

/// Serif face for dates and titles: gives the "chronicle" feel. Android ships Noto Serif as
/// `serif`; elsewhere the platform default serif is used.
const serif = 'serif';

ThemeData buildTheme(Brightness brightness, int accent) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accents[accent.clamp(0, accents.length - 1)],
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(fontFamily: serif, fontWeight: FontWeight.w600),
      headlineMedium: text.headlineMedium?.copyWith(fontFamily: serif, fontWeight: FontWeight.w600),
      headlineSmall: text.headlineSmall?.copyWith(fontFamily: serif, fontWeight: FontWeight.w600),
      titleLarge: text.titleLarge?.copyWith(fontFamily: serif, fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.55, fontSize: 17),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
      backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.6),
      labelStyle: text.labelLarge?.copyWith(color: scheme.onSecondaryContainer, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      height: 68,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
