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
  Streak _streak = const Streak();
  List<DailyTask> _tasksToday = const [];
  List<Subject> _subjects = const [];

  Profile? get profile => _profile;
  Goal? get goal => _goal;
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
        // Independent reads — run them together rather than four round-trips.
        final results = await Future.wait([
          _profiles.getMyProfile(),
          _goals.getActiveGoal(),
          _tasks.getTodayTasks(),
          _game.getStreak(),
        ]);
        _profile = results[0] as Profile?;
        _goal = results[1] as Goal?;
        _tasksToday = results[2] as List<DailyTask>;
        _streak = results[3] as Streak;

        final goalId = _goal?.id;
        _subjects =
            goalId == null ? const [] : await _goals.getSubjects(goalId);
      });

  Future<void> refresh() async {
    _tasksToday = await _tasks.getTodayTasks();
    notifyListeners();
  }

  /// Flips a checkbox optimistically, then persists. Reverts on failure so the
  /// UI never claims a write succeeded when it didn't.
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
      // Completing a task counts toward the day's activity and streak.
      if (next) await _game.logActivity(tasks: 1, minutes: task.durationMin ?? 0);
    });

    if (!ok) {
      _tasksToday = before;
      notifyListeners();
    } else if (next) {
      _streak = await _game.getStreak();
      notifyListeners();
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
