import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Roadmap screen — milestones with their task checklists, plus the
/// overall percentage shown at the top.
class RoadmapStore extends AsyncStore {
  RoadmapStore({RoadmapRepository? roadmap, GoalRepository? goals})
      : _roadmap = roadmap ?? const RoadmapRepository(),
        _goals = goals ?? const GoalRepository();

  final RoadmapRepository _roadmap;
  final GoalRepository _goals;

  Goal? _goal;
  List<Milestone> _milestones = const [];

  Goal? get goal => _goal;
  List<Milestone> get milestones => _milestones;

  bool get isEmpty => loaded && _milestones.isEmpty;

  int get totalTasks =>
      _milestones.fold(0, (sum, m) => sum + m.tasks.length);

  int get doneTasks => _milestones.fold(0, (sum, m) => sum + m.doneCount);

  double get overallProgress =>
      totalTasks == 0 ? 0 : doneTasks / totalTasks;

  Future<void> load() => runLoad(() async {
        _goal = await _goals.getActiveGoal();
        final goalId = _goal?.id;
        _milestones =
            goalId == null ? const [] : await _roadmap.getMilestones(goalId);
      });

  /// Optimistic checkbox flip. On success the milestone's derived state
  /// (upcoming / active / done) comes back from the repository.
  Future<void> toggleTask(Milestone milestone, MilestoneTask task) async {
    final next = !task.done;
    final before = _milestones;

    _milestones = [
      for (final m in _milestones)
        m.id != milestone.id
            ? m
            : m.copyWith(
                tasks: [
                  for (final t in m.tasks)
                    t.id == task.id ? t.copyWith(done: next) : t,
                ],
              ),
    ];
    notifyListeners();

    final ok = await runMutation(() async {
      final state = await _roadmap.toggleTask(milestone.id, task.id, next);
      _milestones = [
        for (final m in _milestones)
          m.id == milestone.id ? m.copyWith(state: state) : m,
      ];
      final goalId = _goal?.id;
      if (goalId != null) await _roadmap.recomputeGoalProgress(goalId);
    });

    if (!ok) {
      _milestones = before;
      notifyListeners();
    }
  }
}
