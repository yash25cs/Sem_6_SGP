import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';

/// Names an exam, its date, pace and subjects, then creates the `goals` row
/// (plus a `subjects` row per chip) that the rest of the app hangs off.
///
/// Serves two entry points: onboarding step 3, and "New goal" from Home or
/// Settings — a student keeps one goal per exam. [stepLabel] and [title] are
/// what distinguish them; the write is identical, and `create_goal` retires the
/// previously active goal, so the new one is the one the app works against.
class SetTargetScreen extends StatefulWidget {
  const SetTargetScreen({
    super.key,
    this.onDone,
    this.onBack,
    this.stepLabel = 'Step 3 of 3',
    this.title = 'Set your target',
  });

  final VoidCallback? onDone;
  final VoidCallback? onBack;

  /// Top-right progress hint. Meaningless outside onboarding, where callers pass
  /// something like 'New goal' instead.
  final String stepLabel;
  final String title;

  @override
  State<SetTargetScreen> createState() => _SetTargetScreenState();
}

class _SetTargetScreenState extends State<SetTargetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  Pace _pace = Pace.steady;
  DateTime? _examDate;

  /// Pre-filled with the usual CSPIT semester subjects; all removable.
  final _subjects = <String>['DBMS', 'OS', 'Networks'];

  static const _paceHours = {
    Pace.relaxed: '1 hr/day',
    Pace.steady: '2 hrs/day',
    Pace.intense: '4 hrs/day',
  };

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _chipTones = [
    ChipTone.primary,
    ChipTone.coral,
    ChipTone.green,
    ChipTone.amber,
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Rough roadmap length shown in the hint card — days to the exam, or a
  /// pace-based default until a date is chosen.
  int get _estimatedDays {
    final exam = _examDate;
    if (exam == null) {
      return switch (_pace) {
        Pace.relaxed => 45,
        Pace.steady => 30,
        Pace.intense => 21,
      };
    }
    final now = DateTime.now();
    final days = DateTime(exam.year, exam.month, exam.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    return days < 1 ? 1 : days;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: 'Exam date',
    );
    if (picked != null) setState(() => _examDate = picked);
  }

  Future<void> _addSubject() async {
    final controller = TextEditingController();
    final p = context.p;

    final name = await showModalBottomSheet<String>(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a subject',
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: p.ink, fontSize: 14.5),
                onSubmitted: (v) => Navigator.of(sheetContext).pop(v.trim()),
                decoration: InputDecoration(
                  hintText: 'e.g. Data Structures',
                  hintStyle: TextStyle(color: p.ink3, fontSize: 14),
                  filled: true,
                  fillColor: p.card2,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: p.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: p.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: p.primary, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PillButton('Add',
                  icon: Symbols.add,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(controller.text.trim())),
            ],
          ),
        ),
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty || !mounted) return;
    if (_subjects.any((s) => s.toLowerCase() == name.toLowerCase())) return;
    setState(() => _subjects.add(name));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final store = context.read<OnboardingStore>();
    final ok = await store.createGoal(
      name: _name.text.trim(),
      examDate: _examDate,
      pace: _pace,
      subjects: _subjects,
    );
    if (!mounted) return;

    if (ok) {
      widget.onDone?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.error ?? 'Could not save your goal')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<OnboardingStore>();
    final exam = _examDate;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 4),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: widget.onBack),
                const Spacer(),
                Text(widget.stepLabel,
                    style: TextStyle(
                        color: p.ink3, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6)),
                  const SizedBox(height: 8),
                  Text('We’ll pace your roadmap to hit this date.',
                      style: TextStyle(color: p.ink2, fontSize: 14, height: 1.5)),
                  const SizedBox(height: 22),

                  if (store.error != null)
                    ErrorNotice(
                      message: store.error!,
                      onRetry: () =>
                          context.read<OnboardingStore>().clearError(),
                    ),

                  _Label('Exam / goal name'),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: p.ink, fontSize: 14.5),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'Give your goal a name'
                        : null,
                    decoration: _fieldDecoration(context,
                        hint: 'e.g. DBMS Semester Final', icon: Symbols.flag),
                  ),
                  const SizedBox(height: 18),

                  _Label('Exam date'),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 15),
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.line, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Icon(Symbols.event, color: p.ink3, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                                exam == null
                                    ? 'Pick a date'
                                    : '${_months[exam.month - 1]} ${exam.day}, ${exam.year}',
                                style: TextStyle(
                                    color: exam == null ? p.ink3 : p.ink,
                                    fontSize: 14.5,
                                    fontWeight: exam == null
                                        ? FontWeight.w400
                                        : FontWeight.w700)),
                          ),
                          Icon(Symbols.expand_more, color: p.ink3, size: 22),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  _Label('Daily study pace'),
                  Row(
                    children: [
                      for (final (i, pace) in Pace.values.indexed) ...[
                        Expanded(
                          child: _PaceCard(
                            label: pace.label,
                            hours: _paceHours[pace] ?? '',
                            selected: _pace == pace,
                            onTap: () => setState(() => _pace = pace),
                          ),
                        ),
                        if (i < Pace.values.length - 1)
                          const SizedBox(width: 10),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),

                  _Label('Focus subjects'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (i, subject) in _subjects.indexed)
                        _SubjectChip(
                          label: subject,
                          tone: _chipTones[i % _chipTones.length],
                          onRemove: () =>
                              setState(() => _subjects.remove(subject)),
                        ),
                      SoftChip('+ Add',
                          icon: Symbols.add,
                          tone: ChipTone.neutral,
                          onTap: _addSubject),
                    ],
                  ),
                  const SizedBox(height: 20),

                  AppCard(
                    color: p.primarySoft,
                    shadow: false,
                    child: Row(
                      children: [
                        Icon(Symbols.auto_awesome, color: p.primary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                              'StudyTrail will generate a ~$_estimatedDays-day roadmap with daily tasks and weekly checkpoints.',
                              style: TextStyle(
                                  color: p.onPrimarySoft,
                                  fontSize: 12.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          FooterBar(
            child: PillButton(
                store.busy ? 'Saving…' : 'Generate my roadmap',
                icon: Symbols.auto_awesome,
                onTap: store.busy ? null : _save),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context,
    {required String hint, IconData? icon}) {
  final p = context.p;
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: p.ink3, fontSize: 14.5),
    prefixIcon: icon == null ? null : Icon(icon, color: p.ink3, size: 20),
    filled: true,
    fillColor: p.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: border(p.line, 1.2),
    enabledBorder: border(p.line, 1.2),
    focusedBorder: border(p.primary, 1.6),
    errorBorder: border(p.error, 1.2),
    focusedErrorBorder: border(p.error, 1.6),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: TextStyle(
                color: context.p.ink2,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
}

/// A focus-subject chip with an inline remove button.
class _SubjectChip extends StatelessWidget {
  const _SubjectChip(
      {required this.label, required this.tone, required this.onRemove});
  final String label;
  final ChipTone tone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (bg, fg) = switch (tone) {
      ChipTone.primary => (p.primarySoft, p.onPrimarySoft),
      ChipTone.coral => (p.coralSoft, p.coralInk),
      ChipTone.green => (p.greenSoft, p.green),
      ChipTone.amber => (p.amberSoft, p.onAmber),
      ChipTone.error => (p.errorSoft, p.onError),
      ChipTone.neutral => (p.card2, p.ink2),
    };

    return Container(
      padding: const EdgeInsets.only(left: 14, right: 6, top: 6, bottom: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Symbols.close, size: 15, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceCard extends StatelessWidget {
  const _PaceCard(
      {required this.label,
      required this.hours,
      required this.selected,
      this.onTap});
  final String label, hours;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? p.primary : p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? p.primary : p.line, width: 1.4),
          boxShadow: selected ? p.glow : null,
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? p.onPrimary : p.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(hours,
                style: TextStyle(
                    color: selected
                        ? p.onPrimary.withValues(alpha: 0.8)
                        : p.ink3,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
