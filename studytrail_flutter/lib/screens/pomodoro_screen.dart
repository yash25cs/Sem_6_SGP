import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../theme/subject_style.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';

/// Pomodoro focus timer with a circular progress ring.
///
/// The countdown itself lives in [PomodoroStore] rather than this widget, so
/// leaving the screen mid-block doesn't cancel the session.
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PomodoroStore>().load();
    });
  }

  /// Lets the student tag the block with a subject, so the logged session
  /// shows up under the right subject in Progress.
  Future<void> _pickSubject() async {
    final store = context.read<PomodoroStore>();
    final p = context.p;

    if (store.subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add subjects to your goal to tag focus sessions.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text('Focus on',
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: Icon(Symbols.blur_on, color: p.ink3),
              title: Text('No subject',
                  style: TextStyle(color: p.ink2, fontSize: 14.5)),
              trailing: store.subjectId == null
                  ? Icon(Symbols.check, color: p.primary)
                  : null,
              onTap: () {
                store.selectSubject(null);
                Navigator.of(sheetContext).pop();
              },
            ),
            for (final s in store.subjects)
              Builder(builder: (_) {
                final style = SubjectStyle.of(context, name: s.name);
                return ListTile(
                  leading: Icon(style.icon, color: style.color),
                  title: Text(s.name,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  trailing: store.subjectId == s.id
                      ? Icon(Symbols.check, color: p.primary)
                      : null,
                  onTap: () {
                    store.selectSubject(s.id);
                    Navigator.of(sheetContext).pop();
                  },
                );
              }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Duration presets — the "…" menu in the header.
  Future<void> _configure() async {
    final store = context.read<PomodoroStore>();
    final p = context.p;

    const presets = <(String, int, int)>[
      ('Classic · 25 / 5', 25, 5),
      ('Deep work · 50 / 10', 50, 10),
      ('Short burst · 15 / 3', 15, 3),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('Session length',
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                  store.running
                      ? 'Applies from the next block — this one keeps running.'
                      : 'Focus and break minutes.',
                  style: TextStyle(color: p.ink3, fontSize: 12.5)),
            ),
            for (final (label, focus, brk) in presets)
              ListTile(
                leading: Icon(Symbols.timer, color: p.primary),
                title: Text(label,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                trailing: store.focusMinutes == focus
                    ? Icon(Symbols.check, color: p.primary)
                    : null,
                onTap: () {
                  store.configure(focus: focus, shortBreak: brk);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<PomodoroStore>();

    final subject = store.selectedSubject;
    final subjectStyle =
        subject == null ? null : SubjectStyle.of(context, name: subject.name);

    // Breaks get the coral accent so a glance at the ring says which half of
    // the cycle is running.
    final accent = store.isFocus ? p.primary : p.coral;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const StatusStrip(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: widget.onBack),
                const SizedBox(width: 8),
                Text('Focus session',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                RoundIconButton(Symbols.more_horiz,
                    plain: false, onTap: _configure),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // subject chip
                  SoftChip(subject?.name ?? 'Pick a subject',
                      icon: subjectStyle?.icon ?? Symbols.add,
                      tone: subject == null
                          ? ChipTone.neutral
                          : ChipTone.primary,
                      onTap: _pickSubject),
                  const SizedBox(height: 8),
                  const Spacer(),

                  // timer ring
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          height: 260,
                          child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOut,
                            tween: Tween(begin: 0, end: store.progress),
                            builder: (context, value, _) =>
                                CircularProgressIndicator(
                              value: value,
                              strokeWidth: 14,
                              strokeCap: StrokeCap.round,
                              backgroundColor: p.card3,
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(store.display,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ])),
                            const SizedBox(height: 4),
                            Text(store.phaseLabel,
                                style: TextStyle(
                                    color: p.ink3,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),

                  // session dots — one per focus block in the cycle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < store.roundsBeforeLongBreak; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < store.roundInCycle - 1 ||
                                    (!store.isFocus &&
                                        i == store.roundInCycle - 1)
                                ? p.primary
                                : p.card3,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'Session ${store.roundInCycle} of '
                      '${store.roundsBeforeLongBreak} · ${store.nextUpLabel}',
                      style: TextStyle(color: p.ink3, fontSize: 12.5)),
                  const Spacer(),

                  // controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CircleControl(Symbols.refresh, p.card, p.ink2,
                          size: 56, onTap: store.reset),
                      const SizedBox(width: 22),
                      _CircleControl(
                          store.running ? Symbols.pause : Symbols.play_arrow,
                          accent,
                          p.onPrimary,
                          size: 82,
                          glow: true,
                          onTap: store.toggle),
                      const SizedBox(width: 22),
                      _CircleControl(Symbols.skip_next, p.card, p.ink2,
                          size: 56, onTap: store.skip),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                          child: _MiniInfo(
                              Symbols.timer,
                              '${store.sessionsToday}',
                              'Sessions today',
                              p.primary)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _MiniInfo(Symbols.hourglass_bottom,
                              store.minutesTodayLabel, 'Focused', p.coral)),
                    ],
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

class _CircleControl extends StatelessWidget {
  const _CircleControl(this.icon, this.bg, this.fg,
      {required this.size, this.glow = false, this.onTap});
  final IconData icon;
  final Color bg, fg;
  final double size;
  final bool glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          boxShadow: glow ? p.glow : p.shadowSm,
          border: glow ? null : Border.all(color: p.line),
        ),
        child: Icon(icon, color: fg, size: size * 0.42, fill: 1),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo(this.icon, this.value, this.label, this.color);
  final IconData icon;
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: p.shadowSm,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              Text(label,
                  style: TextStyle(color: p.ink3, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}
