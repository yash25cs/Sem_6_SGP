import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Builds the light/dark [ThemeData] for StudyTrail using Plus Jakarta Sans and
/// the Stitch color tokens carried in [AppPalette].
class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    );

    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      splashColor: p.primary.withValues(alpha: 0.06),
      highlightColor: p.primary.withValues(alpha: 0.04),
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.primary,
        onPrimary: p.onPrimary,
        secondary: p.coral,
        onSecondary: Colors.white,
        tertiary: p.amber,
        onTertiary: p.onAmber,
        error: p.error,
        onError: Colors.white,
        surface: p.card,
        onSurface: p.ink,
        surfaceContainerHighest: p.card3,
        outline: p.line2,
      ),
      extensions: [p],
    );
  }
}

/// Sugar: `context.p` → the active [AppPalette]. Keeps screen code terse.
extension PaletteX on BuildContext {
  AppPalette get p => Theme.of(this).extension<AppPalette>()!;
}
