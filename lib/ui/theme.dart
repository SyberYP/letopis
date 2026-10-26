import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../state/app_state.dart' show AppFont;
export '../state/app_state.dart' show AppFont;

/// Accent seeds offered in the settings.
const accents = <Color>[
  Color(0xFF5B5BD6), // indigo
  Color(0xFF8C6A3F), // parchment / sepia
  Color(0xFF2F8F83), // teal
  Color(0xFFC2185B), // rose
  Color(0xFF3E7D3A), // forest
  Color(0xFF455A87), // slate
];

/// What each [AppFont] means. All bundled faces cover Latin and Cyrillic (SIL OFL 1.1, licenses in
/// `assets/fonts/`); other scripts fall back to the system fonts.
class FontChoice {
  const FontChoice({this.body, this.heading, this.scale = 1, required this.pdf});

  /// null = the platform default (Roboto on Android).
  final String? body;

  /// Dates and titles. null = same as [body].
  final String? heading;

  /// Some faces look smaller than Roboto at the same size.
  final double scale;

  /// Files for the PDF export: regular, bold, italic.
  final (String, String, String) pdf;
}

const _ptSerifPdf = ('PT_Serif-Web-Regular.ttf', 'PT_Serif-Web-Bold.ttf', 'PT_Serif-Web-Italic.ttf');

const fontChoices = <AppFont, FontChoice>{
  // Android ships Noto Serif as `serif`: titles get the "chronicle" feel.
  AppFont.classic: FontChoice(heading: 'serif', pdf: _ptSerifPdf),
  AppFont.system: FontChoice(pdf: _ptSerifPdf),
  AppFont.serif: FontChoice(body: 'PT Serif', pdf: _ptSerifPdf),
  AppFont.lora: FontChoice(body: 'Lora', pdf: ('Lora-Regular.ttf', 'Lora-Bold.ttf', 'Lora-Italic.ttf')),
  AppFont.rounded: FontChoice(
    body: 'Comfortaa',
    scale: 0.95,
    pdf: ('Comfortaa-Regular.ttf', 'Comfortaa-Bold.ttf', 'Comfortaa-Regular.ttf'),
  ),
  AppFont.hand: FontChoice(
    body: 'Caveat',
    scale: 1.22,
    pdf: ('Caveat-Regular.ttf', 'Caveat-Bold.ttf', 'Caveat-Regular.ttf'),
  ),
  AppFont.mono: FontChoice(
    body: 'PT Mono',
    scale: 0.92,
    pdf: ('PTMono-Regular.ttf', 'PTMono-Regular.ttf', 'PTMono-Regular.ttf'),
  ),
};

/// The font picked in the settings; set by the app before the theme is built.
class Fonts {
  static AppFont current = AppFont.classic;
  static FontChoice get choice => fontChoices[current]!;
}

/// Face for dates and titles (null keeps the body font).
String? get serif => Fonts.choice.heading ?? Fonts.choice.body;

/// Mood emoji. Phones fall back to the system emoji font anyway; naming it lets the screenshot
/// tests (which have no system fonts) draw real emoji instead of boxes.
const emojiFallback = ['Noto Color Emoji'];

ThemeData buildTheme(Brightness brightness, int accent, [AppFont font = AppFont.classic]) {
  final face = fontChoices[font]!;
  final heading = face.heading ?? face.body;
  final scheme = ColorScheme.fromSeed(
    seedColor: accents[accent.clamp(0, accents.length - 1)],
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness, fontFamily: face.body);
  final text = face.scale == 1 ? base.textTheme : _scaled(base.textTheme, face.scale);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(fontFamily: heading, fontWeight: FontWeight.w600),
      headlineMedium: text.headlineMedium?.copyWith(fontFamily: heading, fontWeight: FontWeight.w600),
      headlineSmall: text.headlineSmall?.copyWith(fontFamily: heading, fontWeight: FontWeight.w600),
      titleLarge: text.titleLarge?.copyWith(fontFamily: heading, fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.55, fontSize: 17 * face.scale),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
    ).apply(fontFamilyFallback: emojiFallback),
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

/// ThemeData keeps the sizes apart (they are merged in per locale), so they are taken from the
/// Material 3 geometry and set explicitly. copyWith keeps `inherit`, so theme changes still animate.
TextTheme _scaled(TextTheme t, double k) {
  final g = Typography.material2021().englishLike;
  TextStyle? s(TextStyle? style, TextStyle? size) => style?.copyWith(fontSize: (size?.fontSize ?? 14) * k);
  return TextTheme(
    displayLarge: s(t.displayLarge, g.displayLarge),
    displayMedium: s(t.displayMedium, g.displayMedium),
    displaySmall: s(t.displaySmall, g.displaySmall),
    headlineLarge: s(t.headlineLarge, g.headlineLarge),
    headlineMedium: s(t.headlineMedium, g.headlineMedium),
    headlineSmall: s(t.headlineSmall, g.headlineSmall),
    titleLarge: s(t.titleLarge, g.titleLarge),
    titleMedium: s(t.titleMedium, g.titleMedium),
    titleSmall: s(t.titleSmall, g.titleSmall),
    bodyLarge: s(t.bodyLarge, g.bodyLarge),
    bodyMedium: s(t.bodyMedium, g.bodyMedium),
    bodySmall: s(t.bodySmall, g.bodySmall),
    labelLarge: s(t.labelLarge, g.labelLarge),
    labelMedium: s(t.labelMedium, g.labelMedium),
    labelSmall: s(t.labelSmall, g.labelSmall),
  );
}
