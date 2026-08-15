import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';

/// Onboarding welcome — the hero illustration, headline, and Next action.
/// Mirrors the Stitch "Turn your exams into a plan." screen.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.onNext});
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const StatusStrip(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: 'Study',
                            style: TextStyle(
                                color: p.primary2,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                        TextSpan(
                            text: 'Trail',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                      ])),
                      const Spacer(),
                      _dot(22, p.primary),
                      const SizedBox(width: 6),
                      _dot(8, p.card3),
                      const SizedBox(width: 6),
                      _dot(8, p.card3),
                    ],
                  ),
                  const SizedBox(height: 26),
                  // Hero illustration — a calm study scene rendered with soft
                  // gradients, a floating mascot, and a tablet.
                  Expanded(child: _HeroArt()),
                  const SizedBox(height: 20),
                  Text('Turn your exams\ninto a plan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.9)),
                  const SizedBox(height: 12),
                  Text(
                      'Upload your syllabus, notes, or videos and let StudyTrail build your roadmap.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.ink2, fontSize: 15, height: 1.5)),
                  const Spacer(),
                  PillButton('Next',
                      trailingIcon: Symbols.arrow_forward, onTap: onNext),
                  const SizedBox(height: 14),
                  Text('Skip',
                      style: TextStyle(
                          color: p.ink3, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(double w, Color c) => Container(
      width: w, height: 6, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(99)));
}

/// The onboarding hero — a soft-gradient scene with a glowing mascot and a
/// small "weekly plan" tablet, painted rather than photographed.
class _HeroArt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBE6D8), Color(0xFFE9ECFB), Color(0xFFDFE3FF)],
          stops: [0, 0.55, 1],
        ),
        boxShadow: context.p.shadow,
      ),
      child: Stack(
        children: [
          // little floating plan card
          Positioned(
            left: 20,
            bottom: 26,
            child: Transform.rotate(
              angle: -0.07,
              child: Container(
                width: 150,
                height: 104,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Color(0x2E191C1F), blurRadius: 20, offset: Offset(0, 8))
                  ],
                ),
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    _Sw(Color(0xFFCFE0FF)), _Sw(Color(0xFFFFD9C9)), _Sw(Color(0xFFD6F5DF)),
                    _Sw(Color(0xFFE6DBFF)), _Sw(Color(0xFFD6F5DF)), _Sw(Color(0xFFFFE7B0)),
                  ],
                ),
              ),
            ),
          ),
          // glowing mascot
          Positioned(
            right: 30,
            top: 44,
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [Color(0xFFEEF1FF), Color(0xFFAEB8FF), Color(0xFF7C8BFF)],
                  stops: [0, 0.7, 1],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0x807C8BFF), blurRadius: 30, offset: Offset(0, 12)),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // halo
                  Positioned(
                    top: -9,
                    child: Container(
                      width: 56,
                      height: 12,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCFD6FF), width: 3),
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                  ),
                  // face
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _eye(), const SizedBox(width: 20), _eye(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 22,
                          height: 11,
                          decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: Color(0xFF24389C), width: 3)),
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eye() => Container(
      width: 9,
      height: 14,
      decoration: BoxDecoration(
          color: const Color(0xFF24389C), borderRadius: BorderRadius.circular(99)));
}

class _Sw extends StatelessWidget {
  const _Sw(this.c);
  final Color c;
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5)));
}
