import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../theme/subject_style.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';

/// Home / dashboard tab — greeting, streak, today's plan, and subject progress.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred: the store notifies listeners, which can't happen during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<HomeStore>().load();
    });
  }

  /// "Good morning" / "afternoon" / "evening" by local clock.
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<HomeStore>();
    final profile = store.profile;
    final goal = store.goal;

    final firstName = (profile?.fullName ?? '').trim().split(' ').first;

    return RefreshIndicator(
      color: p.primary,
      onRefresh: () => context.read<HomeStore>().load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          // greeting header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_greeting,
                        style: TextStyle(color: p.ink2, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(firstName.isEmpty ? 'Hey 👋' : '$firstName 👋',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6)),
                  ],
                ),
              ),
              RoundIconButton(Symbols.notifications, plain: false),
              const SizedBox(width: 10),
              GradAvatar(profile?.initial ?? '?', size: 46),
            ],
          ),
          const SizedBox(height: 18),

          if (store.error != null)
            ErrorNotice(
              message: store.error!,
              onRetry: () => context.read<HomeStore>().load(),
            ),

          // hero streak / progress card
          if (store.loading && !store.loaded)
            const LoadingBlock(height: 230)
          else if (goal == null)
            EmptyState(
              icon: Symbols.flag,
              title: 'No exam goal yet',
              message:
                  'Set a target exam and StudyTrail will build your roadmap.',
            )
          else
            _HeroCard(goal: goal, store: store),
          const SizedBox(height: 22),

          // today's plan
          CardHeader(
            'Today’s plan',
            action: Text(
              '${store.tasks.length} task${store.tasks.length == 1 ? '' : 's'}',
              style: TextStyle(
                  color: p.ink3, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          if (store.loading && !store.loaded)
            const LoadingBlock(height: 74)
          else if (store.tasks.isEmpty)
            EmptyState(
              icon: Symbols.checklist,
              title: 'Nothing scheduled',
              message: goal == null
                  ? 'Set a goal to get a daily plan.'
                  : 'Your plan for today is clear. Add a task to get going.',
            )
          else
            for (final task in store.tasks)
              _TaskTile(
                task: task,
                onToggle: () => context.read<HomeStore>().toggleTask(task),
              ),
          const SizedBox(height: 20),

          // subject progress
          if (store.subjects.isNotEmpty) ...[
            CardHeader('Subjects'),
            AppCard(
              child: Column(
                children: [
                  for (var i = 0; i < store.subjects.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _SubjectRow(store.subjects[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.goal, required this.store});

  final Goal goal;
  final HomeStore store;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final percent = goal.overallPercent / 100;
    final streak = store.streak.currentStreak;
    final daysLeft = goal.daysLeft;

    return AppCard(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.primary, p.primary2]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Symbols.local_fire_department,
                      color: Color(0xFFFFC773), size: 18, fill: 1),
                  const SizedBox(width: 5),
                  Text(
                      streak == 0
                          ? 'Start your streak'
                          : '$streak-day streak',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
              const Spacer(),
              if ((goal.roadmapDays ?? 0) > 0)
                Text('Day ${goal.currentDay} / ${goal.roadmapDays}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          Text(goal.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('You’re ${goal.overallPercent.round()}% through your roadmap',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC773)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeroStat('${store.doneCount}', 'Done today'),
              _HeroStat('${store.tasks.length}', 'Tasks today'),
              _HeroStat(daysLeft == null ? '—' : '$daysLeft', 'Days left'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onToggle});

  final DailyTask task;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final style = SubjectStyle.of(context, name: task.subjectName ?? '');
    final done = task.done;

    // Tag colour follows the task's state, matching the original design.
    final (tagBg, tagFg) = switch (task.tag) {
      TaskTag.done => (p.greenSoft, p.green),
      TaskTag.quiz => (p.amberSoft, p.onAmber),
      TaskTag.now => (p.coralSoft, p.coralInk),
    };

    final meta = [
      if ((task.subjectName ?? '').isNotEmpty) task.subjectName!,
      if (task.durationLabel.isNotEmpty) task.durationLabel,
    ].join(' · ');

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: p.shadowSm,
        ),
        child: Row(
          children: [
            IconTile(
              done ? Symbols.check : style.icon,
              bg: done ? p.card2 : style.color.withValues(alpha: 0.14),
              fg: done ? p.ink3 : style.color,
              size: 46,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      style: TextStyle(
                          color: done ? p.ink3 : p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          decoration:
                              done ? TextDecoration.lineThrough : null)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(meta,
                        style: TextStyle(color: p.ink3, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            Tag(task.tag.label, bg: tagBg, fg: tagFg),
          ],
        ),
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow(this.subject);

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final style = SubjectStyle.of(
      context,
      name: subject.name,
      iconKey: subject.iconKey,
      colorKey: subject.colorKey,
    );
    final value = (subject.progress / 100).clamp(0.0, 1.0);

    return Row(
      children: [
        IconTile(style.icon,
            bg: style.color.withValues(alpha: 0.14),
            fg: style.color,
            size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Text('${subject.progress.round()}%',
                      style: TextStyle(
                          color: p.ink2,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 7),
              ProgressTrack(value, color: style.color, height: 7),
            ],
          ),
        ),
      ],
    );
  }
}
