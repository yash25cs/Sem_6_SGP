import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Home screen: greeting, active goal, today's checklist, focus
/// subjects, and the streak chip.
class HomeStore extends AsyncStore {
  HomeStore({
    ProfileRepository? profiles,
    GoalRepository? goals,
    TaskRepository? tasks,
    GamificationRepository? game,
  })  : _profiles = profiles ?? const ProfileRepository(),
        _goals = goals ?? const GoalRepository(),
        _tasks = tasks ?? const TaskRepository(),
        _game = game ?? const GamificationRepository();

  final ProfileRepository _profiles;
  final GoalRepository _goals;
  final TaskRepository _tasks;
  final GamificationRepository _game;

  Profile? _profile;
  Goal? _goal;
  List<Goal> _allGoals = const [];
  Streak _streak = const Streak();
  List<DailyTask> _tasksToday = const [];
  List<Subject> _subjects = const [];

  Profile? get profile => _profile;

  /// The goal every other read on this screen is scoped to.
  Goal? get goal => _goal;

  /// Every goal the student has, newest first — the switcher's list. A student
  /// can keep several (one per exam) but the app works against one at a time.
  List<Goal> get allGoals => _allGoals;

  Streak get streak => _streak;
  List<DailyTask> get tasks => _tasksToday;
  List<Subject> get subjects => _subjects;

  /// Subjects the student marked as focus, for the "Focus areas" row.
  List<Subject> get focusSubjects =>
      _subjects.where((s) => s.isFocus).toList();

  int get doneCount => _tasksToday.where((t) => t.done).length;

  double get todayProgress =>
      _tasksToday.isEmpty ? 0 : doneCount / _tasksToday.length;

  Future<void> load() => runLoad(() async {
        // Independent reads — run them together rather than five round-trips.
        final results = await Future.wait([
          _profiles.getMyProfile(),
          _goals.getGoals(),
          _tasks.getTodayTasks(),
          _game.getStreak(),
        ]);
        _profile = results[0] as Profile?;
        _allGoals = results[1] as List<Goal>;
        _tasksToday = results[2] as List<DailyTask>;
        _streak = results[3] as Streak;

        // Derived from the full list rather than a separate `getActiveGoal()`
        // round-trip. Same rule as that query: newest active row wins, so a
        // half-finished switch still resolves to one goal.
        _goal = _allGoals.where((g) => g.isActive).firstOrNull;

        final goalId = _goal?.id;
        _subjects =
            goalId == null ? const [] : await _goals.getSubjects(goalId);
      });

  /// Switches which goal the app works against, then reloads everything scoped
  /// to it — tasks stay global, but subjects and the hero card follow the goal.
  Future<bool> switchGoal(String goalId) async {
    if (goalId == _goal?.id) return true;
    final ok = await runMutation(() => _goals.setActiveGoal(goalId));
    if (ok) await load();
    return ok;
  }

  Future<void> refresh() async {
    _tasksToday = await _tasks.getTodayTasks();
    notifyListeners();
  }

  /// Flips a checkbox optimistically, then persists. Reverts on failure so the
  /// UI never claims a write succeeded when it didn't.
  ///
  /// Activity, XP, the streak, and any badge it earns are all rolled into the
  /// `complete_task` RPC, so there's nothing to log from here.
  Future<void> toggleTask(DailyTask task) async {
    final next = !task.done;
    final before = _tasksToday;
    _tasksToday = [
      for (final t in _tasksToday)
        t.id == task.id
            ? t.copyWith(done: next, tag: next ? TaskTag.done : TaskTag.now)
            : t,
    ];
    notifyListeners();

    final ok = await runMutation(() async {
      final saved = await _tasks.setDone(task, next);
      _tasksToday = [
        for (final t in _tasksToday) t.id == saved.id ? saved : t,
      ];
    });

    if (!ok) {
      _tasksToday = before;
      notifyListeners();
    } else if (next) {
      // The RPC rolled the streak forward; re-read it for the header chip.
      // Guarded because this sits outside the mutation — the tick is already
      // saved, and `toggleTask` returns void, so a throw here would surface as
      // an unhandled async error rather than as a failed write.
      try {
        _streak = await _game.getStreak();
        notifyListeners();
      } catch (_) {
        // Header chip stays on the previous count until the next load.
      }
    }
  }

  Future<bool> addTask({
    required String title,
    String? subjectId,
    int? durationMin,
  }) =>
      runMutation(() async {
        final created = await _tasks.createTask(
          title: title,
          goalId: _goal?.id,
          subjectId: subjectId,
          durationMin: durationMin,
        );
        _tasksToday = [..._tasksToday, created];
      });

  Future<bool> deleteTask(DailyTask task) => runMutation(() async {
        await _tasks.deleteTask(task.id);
        _tasksToday = _tasksToday.where((t) => t.id != task.id).toList();
      });
}
