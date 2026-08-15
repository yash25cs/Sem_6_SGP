import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';

/// Roadmap tab — a vertical timeline of weekly milestones with day tasks.
class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RoadmapStore>().load();
    });
  }

  /// Milestone accent colours cycle through the palette in timeline order, so
  /// each week reads distinctly without needing a colour stored per row.
  Color _accent(BuildContext context, Milestone m, int index) {
    final p = context.p;
    if (m.state == MilestoneState.done) return p.green;
    final cycle = [p.primary, p.coral, p.amber, p.primary2];
    return cycle[index % cycle.length];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<RoadmapStore>();
    final goal = store.goal;

    final subtitle = goal == null
        ? 'No goal set yet'
        : [
            goal.name,
            if (goal.daysLeft != null) '${goal.daysLeft} days left',
          ].join(' · ');

    return RefreshIndicator(
      color: p.primary,
      onRefresh: () => context.read<RoadmapStore>().load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your roadmap',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink2, fontSize: 13.5)),
                  ],
                ),
              ),
              RoundIconButton(Symbols.tune, plain: false),
            ],
          ),
          const SizedBox(height: 16),

          if (store.error != null)
            ErrorNotice(
              message: store.error!,
              onRetry: () => context.read<RoadmapStore>().load(),
            ),

          // overall progress
          if (store.totalTasks > 0) ...[
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Overall progress',
                          style: TextStyle(
                              color: p.ink2,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(
                          '${store.doneTasks} / ${store.totalTasks} topics',
                          style: TextStyle(
                              color: p.ink3,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ProgressTrack(store.overallProgress,
                      color: p.primary, height: 8),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (store.loading && !store.loaded) ...[
            const LoadingBlock(height: 150),
            const LoadingBlock(height: 150),
          ] else if (store.isEmpty)
            EmptyState(
              icon: Symbols.route,
              title: goal == null ? 'No roadmap yet' : 'Roadmap is empty',
              message: goal == null
                  ? 'Set your exam goal and StudyTrail will plan the weeks for you.'
                  : 'Generate a roadmap from your syllabus to see weekly milestones here.',
            )
          else
            for (var i = 0; i < store.milestones.length; i++)
              _MilestoneTile(
                milestone: store.milestones[i],
                color: _accent(context, store.milestones[i], i),
                last: i == store.milestones.length - 1,
                onToggle: (task) => context
                    .read<RoadmapStore>()
                    .toggleTask(store.milestones[i], task),
              ),
        ],
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.milestone,
    required this.color,
    required this.onToggle,
    this.last = false,
  });

  final Milestone milestone;
  final Color color;
  final ValueChanged<MilestoneTask> onToggle;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final active = milestone.state == MilestoneState.active;
    final done = milestone.state == MilestoneState.done;
    final tasks = milestone.tasks;

    final header = milestone.weekLabel ?? 'Milestone';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // timeline rail
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: active || done ? color : p.card,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: active || done ? color : p.line2, width: 2.4),
                  boxShadow: active ? p.glow : null,
                ),
                child: Icon(
                    done
                        ? Symbols.check
                        : active
                            ? Symbols.bolt
                            : Symbols.lock_clock,
                    color: active || done ? Colors.white : p.ink3,
                    size: 18,
                    weight: done ? 700 : 400,
                    fill: active ? 1 : 0),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2.4,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: done ? color.withValues(alpha: 0.5) : p.line2,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // milestone card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: AppCard(
                color: active ? null : p.card,
                gradient: active
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                            color.withValues(alpha: 0.10),
                            p.card,
                          ])
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(header.toUpperCase(),
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 5),
                    Text(milestone.title,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800)),
                    if (tasks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (var i = 0; i < tasks.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _MiniTask(
                          task: tasks[i],
                          color: color,
                          onTap: () => onToggle(tasks[i]),
                        ),
                      ],
                    ],
                    if (active && milestone.doneCount < tasks.length) ...[
                      const SizedBox(height: 14),
                      ProgressTrack(milestone.progress,
                          color: color, height: 6),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTask extends StatelessWidget {
  const _MiniTask({
    required this.task,
    required this.color,
    required this.onTap,
  });

  final MilestoneTask task;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final done = task.done;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(done ? Symbols.check_circle : Symbols.circle,
                color: done ? color : p.line2,
                fill: done ? 1 : 0,
                size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(task.name,
                  style: TextStyle(
                      color: done ? p.ink3 : p.ink2,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null)),
            ),
          ],
        ),
      ),
    );
  }
}
