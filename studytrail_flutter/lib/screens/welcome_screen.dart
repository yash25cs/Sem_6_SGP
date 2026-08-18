import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';

/// First-run welcome carousel — three swipeable panels, then into signup.
///
/// The Stitch mock draws a single welcome frame but describes the screen as a
/// "welcome carousel", and its header already carries three page dots. Those
/// dots were static decoration; here they track the live page. Panel 1 keeps
/// the mock's illustration and copy exactly; panels 2 and 3 add scenes in the
/// same painted language (28px gradient card, tilted white cards, soft glow).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.onDone});

  /// Fired when the student finishes or skips the tour.
  final VoidCallback? onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  static const List<_Panel> _panels = [
    _Panel(
      headline: 'Turn your exams\ninto a plan.',
      body: 'Upload your syllabus, notes, or videos and let StudyTrail '
          'build your roadmap.',
      art: _PlanArt(),
    ),
    _Panel(
      headline: 'Your roadmap,\nbuilt for you.',
      body: 'StudyTrail breaks the syllabus into weekly milestones and a '
          'day-by-day list you can actually finish.',
      art: _RoadmapArt(),
    ),
    _Panel(
      headline: 'Show up daily,\nsee it add up.',
      body: 'Flashcards, quizzes, and streaks keep it stuck — and progress '
          'shows you where you stand before exam day.',
      art: _ProgressArt(),
    ),
  ];

  bool get _isLast => _index == _panels.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onDone?.call();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
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
                      for (var i = 0; i < _panels.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        _Dot(active: i == _index),
                      ],
                    ],
                  ),
                  const SizedBox(height: 26),
                  // The button and Skip sit outside the PageView so only the
                  // art and copy travel when swiping.
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (i) => setState(() => _index = i),
                      children: _panels,
                    ),
                  ),
                  const SizedBox(height: 20),
                  PillButton(_isLast ? 'Get started' : 'Next',
                      trailingIcon: Symbols.arrow_forward, onTap: _next),
                  const SizedBox(height: 14),
                  // Kept in the tree on the last panel so the column height
                  // doesn't shift under the button as pages change.
                  Opacity(
                    opacity: _isLast ? 0 : 1,
                    child: GestureDetector(
                      onTap: _isLast ? null : widget.onDone,
                      behavior: HitTestBehavior.opaque,
                      child: Text('Skip',
                          style: TextStyle(
                              color: p.ink3,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
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
}

/// One carousel panel. The art expands to absorb the leftover height, and the
/// copy block is pinned so the art doesn't resize between panels.
class _Panel extends StatelessWidget {
  const _Panel({required this.headline, required this.body, required this.art});

  final String headline;
  final String body;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      children: [
        Expanded(child: art),
        const SizedBox(height: 20),
        Text(headline,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink,
                fontSize: 30,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.9)),
        const SizedBox(height: 12),
        SizedBox(
          height: 68,
          child: Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink2, fontSize: 15, height: 1.5)),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      width: active ? 22 : 8,
      height: 6,
      decoration: BoxDecoration(
          color: active ? p.primary : p.card3,
          borderRadius: BorderRadius.circular(99)),
    );
  }
}

/// Shared canvas for the three scenes — the mock's gradient hero card.
///
/// Deliberately unclipped: every scene stays inside the frame, and clipping
/// would shave the soft glow off the orbs that sit near the right edge.
class _ArtFrame extends StatelessWidget {
  const _ArtFrame({required this.children});
  final List<Widget> children;

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
      child: Stack(children: children),
    );
  }
}

/// White card the scenes float, tilted like the mock's plan card.
class _FloatCard extends StatelessWidget {
  const _FloatCard({
    required this.width,
    required this.height,
    required this.angle,
    required this.child,
    this.padding = const EdgeInsets.all(10),
  });

  final double width, height, angle;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x2E191C1F), blurRadius: 20, offset: Offset(0, 8))
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Panel 1 — the mock's scene: a glowing mascot and a "weekly plan" tablet.
class _PlanArt extends StatelessWidget {
  const _PlanArt();

  @override
  Widget build(BuildContext context) {
    return _ArtFrame(children: [
      Positioned(
        left: 20,
        bottom: 26,
        child: _FloatCard(
          width: 150,
          height: 104,
          angle: -0.07,
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              _Sw(Color(0xFFCFE0FF)),
              _Sw(Color(0xFFFFD9C9)),
              _Sw(Color(0xFFD6F5DF)),
              _Sw(Color(0xFFE6DBFF)),
              _Sw(Color(0xFFD6F5DF)),
              _Sw(Color(0xFFFFE7B0)),
            ],
          ),
        ),
      ),
      const Positioned(right: 30, top: 44, child: _Mascot()),
    ]);
  }
}

/// Panel 2 — a milestone trail beside a stack of generated cards.
class _RoadmapArt extends StatelessWidget {
  const _RoadmapArt();

  @override
  Widget build(BuildContext context) {
    return _ArtFrame(children: [
      // Week list: two milestones done, one in progress, one waiting.
      Positioned(
        left: 22,
        top: 40,
        child: _FloatCard(
          width: 168,
          height: 150,
          angle: -0.05,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _TrailRow(color: Color(0xFF6BCB8B), done: true, barWidth: 96),
              _TrailRow(color: Color(0xFF6BCB8B), done: true, barWidth: 74),
              _TrailRow(color: Color(0xFF7C8BFF), done: false, barWidth: 104),
              _TrailRow(color: Color(0xFFD8DDF5), done: false, barWidth: 62),
            ],
          ),
        ),
      ),
      // Soft glow behind the day chip, echoing the mascot's halo.
      Positioned(
        right: 24,
        bottom: 34,
        child: _FloatCard(
          width: 96,
          height: 96,
          angle: 0.08,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Symbols.route,
                  color: Color(0xFF24389C), size: 30, fill: 1),
              const SizedBox(height: 8),
              Container(
                height: 6,
                width: 46,
                decoration: BoxDecoration(
                    color: const Color(0xFFCFD6FF),
                    borderRadius: BorderRadius.circular(99)),
              ),
              const SizedBox(height: 5),
              Container(
                height: 6,
                width: 30,
                decoration: BoxDecoration(
                    color: const Color(0xFFE6DBFF),
                    borderRadius: BorderRadius.circular(99)),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// Panel 3 — weekly bars with a streak badge riding on top.
class _ProgressArt extends StatelessWidget {
  const _ProgressArt();

  @override
  Widget build(BuildContext context) {
    return _ArtFrame(children: [
      Positioned(
        left: 24,
        bottom: 30,
        child: _FloatCard(
          width: 164,
          height: 116,
          angle: -0.05,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _Bar(0.42, Color(0xFFCFE0FF)),
              _Bar(0.66, Color(0xFFAEB8FF)),
              _Bar(0.34, Color(0xFFCFE0FF)),
              _Bar(0.86, Color(0xFF7C8BFF)),
              _Bar(0.58, Color(0xFFAEB8FF)),
              _Bar(1.0, Color(0xFF7C8BFF)),
              _Bar(0.5, Color(0xFFCFE0FF)),
            ],
          ),
        ),
      ),
      // Streak badge, in the coral end of the palette so it reads as the
      // reward rather than more chart.
      Positioned(
        right: 26,
        top: 34,
        child: Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(-0.3, -0.4),
              colors: [Color(0xFFFFF0E6), Color(0xFFFFC2A1), Color(0xFFFF8A5B)],
              stops: [0, 0.7, 1],
            ),
            boxShadow: [
              BoxShadow(
                  color: Color(0x80FF8A5B),
                  blurRadius: 30,
                  offset: Offset(0, 12)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Symbols.local_fire_department,
                  color: Colors.white, size: 30, fill: 1),
              SizedBox(height: 2),
              Text('7 days',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// One milestone row: state dot plus a bar standing in for the title.
class _TrailRow extends StatelessWidget {
  const _TrailRow(
      {required this.color, required this.done, required this.barWidth});

  final Color color;
  final bool done;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: done
              ? const Icon(Symbols.check, color: Colors.white, size: 10, weight: 700)
              : null,
        ),
        const SizedBox(width: 8),
        Container(
          width: barWidth,
          height: 7,
          decoration: BoxDecoration(
              color: const Color(0xFFE8EBF7),
              borderRadius: BorderRadius.circular(99)),
        ),
      ],
    );
  }
}

/// A single weekly-activity bar, sized as a fraction of the card's height.
class _Bar extends StatelessWidget {
  const _Bar(this.fraction, this.color);
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: fraction,
      child: Container(
        width: 12,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

/// The onboarding mascot — a glowing orb with a halo and a calm face.
class _Mascot extends StatelessWidget {
  const _Mascot();

  @override
  Widget build(BuildContext context) {
    return Container(
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
          BoxShadow(
              color: Color(0x807C8BFF), blurRadius: 30, offset: Offset(0, 12)),
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
                  children: [_eye(), const SizedBox(width: 20), _eye()],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 22,
                  height: 11,
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Color(0xFF24389C), width: 3)),
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(40)),
                  ),
                ),
              ],
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
          color: const Color(0xFF24389C),
          borderRadius: BorderRadius.circular(99)));
}

class _Sw extends StatelessWidget {
  const _Sw(this.c);
  final Color c;
  @override
  Widget build(BuildContext context) => Container(
      decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(5)));
}
