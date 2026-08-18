import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
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
  /// Held in a field because [dispose] runs after the element is detached, when
  /// `context.read` is no longer legal.
  PomodoroStore? _store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _store = context.read<PomodoroStore>()
        ..load()
        // Suppresses the global focus bar while the full dial is on screen.
        ..setOnTimerScreen(true);
    });
  }

  @override
  void dispose() {
    final store = _store;
    if (store != null) {
      // Deferred: notifying listeners during this frame's teardown would mark
      // the overlay dirty while the tree is being unmounted.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => store.setOnTimerScreen(false));
    }
    super.dispose();
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// The preset list — the "…" menu in the header.
  ///
  /// Only reachable between blocks: changing the length of a block already
  /// running left the dial and the round counter describing something other
  /// than what was being timed.
  Future<void> _configure() async {
    final store = context.read<PomodoroStore>();
    final p = context.p;

    if (!store.canConfigure) {
      _toast('Pause the timer to change its length.');
      return;
    }

    final picked = await showModalBottomSheet<TimerPreset>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text('Session length',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text('Focus / break minutes and rounds per long break.',
                    style: TextStyle(color: p.ink3, fontSize: 12.5)),
              ),
              for (final preset in store.savedPresets)
                ListTile(
                  leading: Icon(
                      preset.isBuiltIn ? Symbols.timer : Symbols.tune,
                      color: p.primary),
                  title: Text(preset.label,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      preset.description == null
                          ? preset.summary
                          : '${preset.summary} · ${preset.description}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink3, fontSize: 12)),
                  trailing: store.preset.id == preset.id
                      ? Icon(Symbols.check, color: p.primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(preset),
                  // Long-press to delete keeps the row a single tap target for
                  // the common case; built-ins ship with the app and stay.
                  onLongPress: preset.isBuiltIn
                      ? null
                      : () => Navigator.of(sheetContext)
                          .pop(_deleteSentinel(preset.id)),
                ),
              ListTile(
                leading: Icon(Symbols.add, color: p.coral),
                title: Text('Custom timer…',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                subtitle: Text('Your own durations, with an optional note',
                    style: TextStyle(color: p.ink3, fontSize: 12)),
                onTap: () => Navigator.of(sheetContext).pop(_customSentinel),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;

    if (picked.id == _customSentinel.id) {
      await _createCustomPreset();
      return;
    }
    if (picked.id.startsWith(_deletePrefix)) {
      await store.deleteCustomPreset(picked.id.substring(_deletePrefix.length));
      _toast('Timer deleted');
      return;
    }
    final applied = await store.applyPreset(picked);
    if (!applied) _toast('Pause the timer to change its length.');
  }

  /// Sentinels let the sheet report the row that was tapped through a single
  /// `pop` value instead of mutating the store from inside the sheet's context.
  static const _customSentinel = TimerPreset(
    id: '__custom__',
    label: 'Custom',
    focusMinutes: 25,
    shortBreakMinutes: 5,
    longBreakMinutes: 15,
    rounds: 4,
  );
  static const _deletePrefix = '__delete__';

  static TimerPreset _deleteSentinel(String id) => TimerPreset(
        id: '$_deletePrefix$id',
        label: 'Delete',
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        rounds: 4,
      );

  /// The custom-timer form. The description is genuinely optional — no
  /// validator — so a student who just wants 40/8 isn't made to name it.
  Future<void> _createCustomPreset() async {
    final store = context.read<PomodoroStore>();
    final p = context.p;
    final current = store.preset;

    final label = TextEditingController();
    final note = TextEditingController();
    final focus = TextEditingController(text: '${current.focusMinutes}');
    final shortBreak =
        TextEditingController(text: '${current.shortBreakMinutes}');
    final longBreak =
        TextEditingController(text: '${current.longBreakMinutes}');
    final rounds = TextEditingController(text: '${current.rounds}');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Custom timer',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    'Minutes between ${TimerPreset.minMinutes} and '
                    '${TimerPreset.maxMinutes}.',
                    style: TextStyle(color: p.ink3, fontSize: 12.5)),
                const SizedBox(height: 14),
                _TimerField(controller: label, label: 'Name'),
                _TimerField(
                    controller: note,
                    label: 'Description (optional)',
                    maxLines: 2),
                Row(
                  children: [
                    Expanded(
                        child: _TimerField(
                            controller: focus,
                            label: 'Focus',
                            numeric: true)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _TimerField(
                            controller: shortBreak,
                            label: 'Short break',
                            numeric: true)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: _TimerField(
                            controller: longBreak,
                            label: 'Long break',
                            numeric: true)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _TimerField(
                            controller: rounds,
                            label: 'Rounds',
                            numeric: true)),
                  ],
                ),
                const SizedBox(height: 8),
                PillButton('Save timer',
                    onTap: () => Navigator.of(sheetContext).pop(true)),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      // A fresh id each time, so saving twice gives two presets rather than
      // silently overwriting the first. `sanitized()` in the store clamps the
      // numbers, so a blank or nonsense field can't produce an unrunnable timer.
      final preset = TimerPreset(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        label: label.text.trim().isEmpty ? 'My timer' : label.text.trim(),
        description: note.text.trim().isEmpty ? null : note.text.trim(),
        focusMinutes: int.tryParse(focus.text) ?? current.focusMinutes,
        shortBreakMinutes:
            int.tryParse(shortBreak.text) ?? current.shortBreakMinutes,
        longBreakMinutes:
            int.tryParse(longBreak.text) ?? current.longBreakMinutes,
        rounds: int.tryParse(rounds.text) ?? current.rounds,
      );
      final applied = await store.saveCustomPreset(preset);
      _toast(applied
          ? 'Timer saved'
          : 'Timer saved — it applies from the next block.');
    }

    label.dispose();
    note.dispose();
    focus.dispose();
    shortBreak.dispose();
    longBreak.dispose();
    rounds.dispose();
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
          const TopInset(),
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
                    plain: false,
                    // Greyed rather than hidden, so the menu doesn't vanish
                    // mid-session — tapping it explains why it won't open.
                    color: store.canConfigure ? null : p.ink3.withValues(alpha: 0.5),
                    onTap: _configure),
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
                            color: i < store.completedInCycle
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
                  if (store.preset.description case final note?) ...[
                    const SizedBox(height: 4),
                    Text('${store.preset.label} · $note',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink3, fontSize: 11.5)),
                  ],
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

/// Labelled field for the custom-timer form. Numeric fields get the number
/// keyboard; the name and description are plain text.
class _TimerField extends StatelessWidget {
  const _TimerField({
    required this.controller,
    required this.label,
    this.numeric = false,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool numeric;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: p.line),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        textCapitalization:
            numeric ? TextCapitalization.none : TextCapitalization.sentences,
        style: TextStyle(color: p.ink, fontSize: 14.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: p.ink3, fontSize: 13.5),
          filled: true,
          fillColor: p.card2,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: p.primary, width: 1.6),
          ),
        ),
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
