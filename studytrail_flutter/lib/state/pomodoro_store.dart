import 'dart:async';

import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Which half of the Pomodoro cycle is running.
enum PomodoroPhase { focus, shortBreak, longBreak }

/// Backs the Pomodoro screen. The timer is local (a 1-second `Timer.periodic`);
/// only completed focus blocks are persisted, so a paused or abandoned session
/// never inflates the study log.
class PomodoroStore extends AsyncStore {
  PomodoroStore({GamificationRepository? game, GoalRepository? goals})
      : _game = game ?? const GamificationRepository(),
        _goals = goals ?? const GoalRepository();

  final GamificationRepository _game;
  final GoalRepository _goals;

  Timer? _ticker;

  int _focusMinutes = 25;
  int _shortBreakMinutes = 5;
  int _longBreakMinutes = 15;

  /// A long break replaces the short one after this many focus blocks.
  int _roundsBeforeLongBreak = 4;

  PomodoroPhase _phase = PomodoroPhase.focus;
  int _secondsLeft = 25 * 60;
  bool _running = false;
  int _completedFocusBlocks = 0;
  String? _subjectId;

  List<Subject> _subjects = const [];
  int _sessionsToday = 0;
  int _minutesToday = 0;

  int get focusMinutes => _focusMinutes;
  int get shortBreakMinutes => _shortBreakMinutes;
  int get longBreakMinutes => _longBreakMinutes;
  int get roundsBeforeLongBreak => _roundsBeforeLongBreak;

  PomodoroPhase get phase => _phase;
  int get secondsLeft => _secondsLeft;
  bool get running => _running;
  bool get isFocus => _phase == PomodoroPhase.focus;

  /// Focus blocks finished since the app opened — the "3 of 4" round counter.
  int get completedFocusBlocks => _completedFocusBlocks;

  int get roundInCycle =>
      (_completedFocusBlocks % _roundsBeforeLongBreak) + 1;

  String? get subjectId => _subjectId;

  /// Subjects of the active goal, for the "what are you focusing on?" chip.
  List<Subject> get subjects => _subjects;

  Subject? get selectedSubject =>
      _subjects.where((s) => s.id == _subjectId).firstOrNull;

  /// Blocks logged today, across app runs — the footer tiles.
  int get sessionsToday => _sessionsToday;
  int get minutesToday => _minutesToday;

  /// "1h 15m" / "50m" for the focused-time tile.
  String get minutesTodayLabel {
    final h = _minutesToday ~/ 60;
    final m = _minutesToday % 60;
    return h == 0 ? '${m}m' : (m == 0 ? '${h}h' : '${h}h ${m}m');
  }

  /// "24:05" for the big dial.
  String get display {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 0–1 elapsed fraction, for the ring around the dial.
  double get progress {
    final total = _phaseSeconds(_phase);
    if (total == 0) return 0;
    return (total - _secondsLeft) / total;
  }

  String get phaseLabel => switch (_phase) {
        PomodoroPhase.focus => 'Focus time',
        PomodoroPhase.shortBreak => 'Short break',
        PomodoroPhase.longBreak => 'Long break',
      };

  /// What follows the block in progress, for the caption under the dots.
  String get nextUpLabel {
    if (!isFocus) return 'Focus next';
    final useLong = (_completedFocusBlocks + 1) % _roundsBeforeLongBreak == 0;
    return useLong ? 'Long break next' : 'Short break next';
  }

  /// Today's totals + the subject list. Safe to call on every screen open —
  /// it never touches the running timer.
  Future<void> load() => runLoad(() async {
        final sessions = await _game.getStudySessions();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        var count = 0, minutes = 0;
        for (final s in sessions) {
          final d = s.sessionDate;
          if (DateTime(d.year, d.month, d.day) != today) continue;
          count += s.sessionsCount ?? 1;
          minutes += s.focusedMin ?? s.lengthMin ?? 0;
        }
        _sessionsToday = count;
        _minutesToday = minutes;

        final goal = await _goals.getActiveGoal();
        _subjects =
            goal == null ? const [] : await _goals.getSubjects(goal.id);
      });

  void selectSubject(String? subjectId) {
    _subjectId = subjectId;
    notifyListeners();
  }

  /// Changing a duration while idle resets the dial to the new length; mid-run
  /// it takes effect on the next phase so the current block isn't disrupted.
  void configure({int? focus, int? shortBreak, int? longBreak, int? rounds}) {
    _focusMinutes = focus ?? _focusMinutes;
    _shortBreakMinutes = shortBreak ?? _shortBreakMinutes;
    _longBreakMinutes = longBreak ?? _longBreakMinutes;
    _roundsBeforeLongBreak = rounds ?? _roundsBeforeLongBreak;
    if (!_running) _secondsLeft = _phaseSeconds(_phase);
    notifyListeners();
  }

  void start() {
    if (_running) return;
    _running = true;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!_running) return;
    _running = false;
    _ticker?.cancel();
    notifyListeners();
  }

  void toggle() => _running ? pause() : start();

  /// Abandons the current block without logging it.
  void reset() {
    _ticker?.cancel();
    _running = false;
    _secondsLeft = _phaseSeconds(_phase);
    notifyListeners();
  }

  /// Ends the block early and moves on. A skipped focus block is not logged —
  /// the student didn't finish it.
  void skip() {
    _ticker?.cancel();
    _running = false;
    _advancePhase(logCompletedFocus: false);
  }

  void _tick() {
    if (_secondsLeft > 1) {
      _secondsLeft--;
      notifyListeners();
      return;
    }
    _ticker?.cancel();
    _running = false;
    _advancePhase(logCompletedFocus: true);
  }

  /// Moves to the next phase, persisting the block if a focus block just ran
  /// to completion.
  void _advancePhase({required bool logCompletedFocus}) {
    final finishedFocus = _phase == PomodoroPhase.focus;

    if (finishedFocus) {
      _completedFocusBlocks++;
      final useLong =
          _completedFocusBlocks % _roundsBeforeLongBreak == 0;
      _phase = useLong ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak;
    } else {
      _phase = PomodoroPhase.focus;
    }

    _secondsLeft = _phaseSeconds(_phase);
    notifyListeners();

    if (finishedFocus && logCompletedFocus) {
      // Fire-and-forget: the timer shouldn't stall on a network write.
      unawaited(_logSession(_focusMinutes));
    }
  }

  Future<void> _logSession(int minutes) async {
    await runMutation(() async {
      await _game.recordSession(
        subjectId: _subjectId,
        lengthMin: minutes,
        focusedMin: minutes,
      );
      await _game.logActivity(minutes: minutes, xp: minutes);
    });
  }

  int _phaseSeconds(PomodoroPhase p) => switch (p) {
        PomodoroPhase.focus => _focusMinutes * 60,
        PomodoroPhase.shortBreak => _shortBreakMinutes * 60,
        PomodoroPhase.longBreak => _longBreakMinutes * 60,
      };

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
