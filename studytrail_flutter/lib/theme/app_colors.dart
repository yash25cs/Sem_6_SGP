import 'package:flutter/material.dart';

/// StudyTrail "Cognitive Calm / Soft-Minimalist" palette.
///
/// The exact tokens from the Stitch design system — indigo primary, coral
/// secondary, amber tertiary — expressed as light/dark [AppPalette]s that ride
/// along on [ThemeData] via a [ThemeExtension] so widgets read semantic roles
/// rather than raw hex.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.plane,
    required this.card,
    required this.card2,
    required this.card3,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.line2,
    required this.primary,
    required this.primary2,
    required this.primarySoft,
    required this.onPrimarySoft,
    required this.coral,
    required this.coralSoft,
    required this.coralInk,
    required this.amber,
    required this.amberSoft,
    required this.onAmber,
    required this.green,
    required this.greenSoft,
    required this.onGreen,
    required this.error,
    required this.errorSoft,
    required this.onError,
    required this.heat1,
    required this.heat3,
    required this.heat4,
    required this.shadow,
    required this.shadowSm,
    required this.glow,
    required this.coralGlow,
  });

  final Color bg, plane, card, card2, card3;
  final Color ink, ink2, ink3, line, line2;
  final Color primary, primary2, primarySoft, onPrimarySoft;
  final Color coral, coralSoft, coralInk;
  final Color amber, amberSoft, onAmber;
  final Color green, greenSoft, onGreen;
  final Color error, errorSoft, onError;
  final Color heat1, heat3, heat4;
  final List<BoxShadow> shadow, shadowSm, glow, coralGlow;

  static const light = AppPalette(
    bg: Color(0xFFF8F9FD),
    plane: Color(0xFFEEF0F7),
    card: Color(0xFFFFFFFF),
    card2: Color(0xFFF2F3F7),
    card3: Color(0xFFE7E8EC),
    ink: Color(0xFF191C1F),
    ink2: Color(0xFF454652),
    ink3: Color(0xFF757684),
    line: Color(0xFFE1E2E6),
    line2: Color(0xFFD5D6DE),
    primary: Color(0xFF24389C),
    primary2: Color(0xFF3F51B5),
    primarySoft: Color(0xFFDEE0FF),
    onPrimarySoft: Color(0xFF00105C),
    coral: Color(0xFFFE6F42),
    coralSoft: Color(0xFFFFDBD0),
    coralInk: Color(0xFFAC3509),
    amber: Color(0xFFFABD00),
    amberSoft: Color(0xFFFFDF9E),
    onAmber: Color(0xFF5B4300),
    green: Color(0xFF1F8F4E),
    greenSoft: Color(0xFFC9F0D6),
    onGreen: Color(0xFF0B3D21),
    error: Color(0xFFBA1A1A),
    errorSoft: Color(0xFFFFDAD6),
    onError: Color(0xFF93000A),
    heat1: Color(0xFFC7CDF3),
    heat3: Color(0xFF5A6CD0),
    heat4: Color(0xFF24389C),
    shadow: [BoxShadow(color: Color(0x14191C1F), blurRadius: 24, offset: Offset(0, 4))],
    shadowSm: [BoxShadow(color: Color(0x0F191C1F), blurRadius: 10, offset: Offset(0, 2))],
    glow: [BoxShadow(color: Color(0x4724389C), blurRadius: 24, offset: Offset(0, 8))],
    coralGlow: [BoxShadow(color: Color(0x52FE6F42), blurRadius: 22, offset: Offset(0, 8))],
  );

  static const dark = AppPalette(
    bg: Color(0xFF12141C),
    plane: Color(0xFF0B0D13),
    card: Color(0xFF1B1E2A),
    card2: Color(0xFF232634),
    card3: Color(0xFF2C3040),
    ink: Color(0xFFEEF1F5),
    ink2: Color(0xFFB6B8C4),
    ink3: Color(0xFF83869A),
    line: Color(0xFF2B2F3D),
    line2: Color(0xFF363B4D),
    primary: Color(0xFFBAC3FF),
    primary2: Color(0xFF8B9BFF),
    primarySoft: Color(0xFF293CA0),
    onPrimarySoft: Color(0xFFDEE0FF),
    coral: Color(0xFFFF7D54),
    coralSoft: Color(0xFF4A2418),
    coralInk: Color(0xFFFF9F80),
    amber: Color(0xFFFABD00),
    amberSoft: Color(0xFF3D2F00),
    onAmber: Color(0xFFFFDF9E),
    green: Color(0xFF5CD08A),
    greenSoft: Color(0xFF123528),
    onGreen: Color(0xFFA9F0C4),
    error: Color(0xFFFFB4AB),
    errorSoft: Color(0xFF3A1512),
    onError: Color(0xFFFFB4AB),
    heat1: Color(0xFF2B3468),
    heat3: Color(0xFF5566CF),
    heat4: Color(0xFF8B9BFF),
    shadow: [BoxShadow(color: Color(0x80000000), blurRadius: 28, offset: Offset(0, 6))],
    shadowSm: [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 2))],
    glow: [BoxShadow(color: Color(0x596D7CFF), blurRadius: 30, offset: Offset(0, 10))],
    coralGlow: [BoxShadow(color: Color(0x59FF7D54), blurRadius: 22, offset: Offset(0, 8))],
  );

  /// White in light mode, deep navy in dark mode — the "on primary" ink that
  /// sits on a filled primary button (primary is pale in dark mode).
  Color get onPrimary => primary.computeLuminance() > 0.5 ? const Color(0xFF12141C) : Colors.white;

  @override
  AppPalette lerp(AppPalette? other, double t) => other ?? this;

  @override
  AppPalette copyWith() => this;
}
