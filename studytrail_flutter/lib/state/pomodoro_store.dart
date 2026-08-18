import 'dart:async';

import '../data/local_prefs.dart';
import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Which half of the Pomodoro cycle is running.
enum PomodoroPhase { focus, shortBreak, longBreak }

/// Backs the Pomodoro screen and the global focus bar. The timer is local (a
/// 1-second `Timer.periodic`); only completed focus blocks are persisted, so a
/// paused or abandoned session never inflates the study log.
///
/// The countdown deliberately lives here rather than in the screen, so leaving
/// the screen doesn't cancel the block — which is what lets `PomodoroOverlay`
/// keep showing it from anywhere in the app.
class PomodoroStore extends AsyncStore {
  PomodoroStore({GamificationRepository? game, GoalRepository? goals})
      : _game = game ?? const GamificationRepository(),
        _goals = goals ?? const GoalRepository();

  final GamificationRepository _game;
  final GoalRepository _goals;

  Timer? _ticker;

  TimerPreset _preset = TimerPreset.fallback;
  List<TimerPreset> _customPresets = const [];
  bool _presetsLoaded = false;

  PomodoroPhase _phase = PomodoroPhase.focus;
  int _secondsLeft = TimerPreset.fallback.focusMinutes * 60;

  /// Length the *current* phase started with.
  ///
  /// [progress] divides by this rather than by the live preset, so switching
  /// preset mid-block can't make the ring jump — it used to compare the old
  /// seconds-left against the new duration.
  int _phaseTotalSeconds = TimerPreset.fallback.focusMinutes * 60;

  bool _running = false;
  int _completedFocusBlocks = 0;
  String? _subjectId;
  bool _onTimerScreen = false;

  int _completionTick = 0;
  PomodoroPhase? _lastCompletedPhase;
  int? _lastCompletedMinutes;
  PomodoroPhase? _startedPhase;

  List<Subject> _subjects = const [];
  int _sessionsToday = 0;
  int _minutesToday = 0;

  TimerPreset get preset => _preset;

  /// Built-ins first, then whatever the student saved.
  List<TimerPreset> get savedPresets =>
      [...TimerPreset.builtIns, ..._customPresets];

  int get focusMinutes => _preset.focusMinutes;
  int get shortBreakMinutes => _preset.shortBreakMinutes;
  int get longBreakMinutes => _preset.longBreakMinutes;
  int get roundsBeforeLongBreak => _preset.rounds;

  PomodoroPhase get phase => _phase;
  int get secondsLeft => _secondsLeft;
  int get phaseTotalSeconds => _phaseTotalSeconds;
  bool get running => _running;
  bool get isFocus => _phase == PomodoroPhase.focus;

  /// Changing durations is only allowed between blocks. Doing it mid-run was the
  /// reported bug: the dial and the round counter no longer described the block
  /// actually being timed.
  bool get canConfigure => !_running;

  /// True once a block has been started and not yet finished or reset — what the
  /// global bar keys off. A freshly loaded dial that nobody touched isn't
  /// "in progress" and shouldn't follow the student around the app.
  bool get inProgress => _running || _secondsLeft < _phaseTotalSeconds;

  /// Focus blocks finished since the app opened.
  int get completedFocusBlocks => _completedFocusBlocks;

  /// 1-based number of the focus block the current phase belongs to.
  ///
  /// A break belongs to the focus block that just ended, not the one coming up —
  /// otherwise the long break after block 4 reported "Session 1 of 4".
  int get roundInCycle {
    final index = isFocus ? _completedFocusBlocks : _completedFocusBlocks - 1;
    return (index % _preset.rounds) + 1;
  }

  /// Focus blocks finished within the cycle currently on screen, for the dots.
  ///
  /// The modulo alone reads 0 during the long break, when the cycle it closes is
  /// in fact complete — so that case reports a full row instead.
  int get completedInCycle {
    final done = _completedFocusBlocks % _preset.rounds;
    if (done == 0 && _completedFocusBlocks > 0 && !isFocus) {
      return _preset.rounds;
    }
    return done;
  }

  String? get subjectId => _subjectId;

  /// Subjects of the active goal, for the "what are you focusing on?" chip.
  List<Subject> get subjects => _subjects;

  Subject? get selectedSubject =>
      _subjects.where((s) => s.id == _subjectId).firstOrNull;

  /// Set by the Pomodoro screen while it's on top, so the global bar doesn't
  /// duplicate the dial the student is already looking at.
  bool get onTimerScreen => _onTimerScreen;

  /// Bumped once per phase that runs to completion.
  ///
  /// A counter rather than a stream or a callback: `ChangeNotifier` has no
  /// one-shot channel, and a listener that rebuilds late still sees the new
  /// value, so the completion popup can't be missed just because the overlay
  /// happened to be busy.
  int get completionTick => _completionTick;
  PomodoroPhase? get lastCompletedPhase => _lastCompletedPhase;

  /// Minutes logged by the phase that just completed — null for breaks, which
  /// aren't logged.
  int? get lastCompletedMinutes => _lastCompletedMinutes;

  /// The phase that started as a result, for the "…and X has begun" line.
  PomodoroPhase? get startedPhase => _startedPhase;

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
    if (_phaseTotalSeconds == 0) return 0;
    return (_phaseTotalSeconds - _secondsLeft) / _phaseTotalSeconds;
  }

  String get phaseLabel => labelFor(_phase);

  static String labelFor(PomodoroPhase phase) => switch (phase) {
        PomodoroPhase.focus => 'Focus time',
        PomodoroPhase.shortBreak => 'Short break',
        PomodoroPhase.longBreak => 'Long break',
      };

  /// What follows the block in progress, for the caption under the dots.
  String get nextUpLabel {
    if (!isFocus) return 'Focus next';
    final useLong = (_completedFocusBlocks + 1) % _preset.rounds == 0;
    return useLong ? 'Long break next' : 'Short break next';
  }

  /// Today's totals, the subject list, and the saved presets. Safe to call on
  /// every screen open — it never touches a running timer.
  Future<void> load() => runLoad(() async {
        // Presets are device-local, so they load even when the network is down.
        // Done before the awaits below for that reason.
        await _loadPresets();

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

  /// Restores the saved presets and the last-used choice. Only applies that
  /// choice to an untouched, idle dial, so reopening the screen mid-block can't
  /// reset the block being timed.
  Future<void> _loadPresets() async {
    if (_presetsLoaded) return;
    _presetsLoaded = true;

    _customPresets = await LocalPrefs.getTimerPresets();
    final activeId = await LocalPrefs.getActiveTimerId();
    if (activeId == null || _running || inProgress) return;

    final match = savedPresets.where((p) => p.id == activeId).firstOrNull;
    if (match != null) _adoptPreset(match);
  }

  void selectSubject(String? subjectId) {
    _subjectId = subjectId;
    notifyListeners();
  }

  void setOnTimerScreen(bool value) {
    if (_onTimerScreen == value) return;
    _onTimerScreen = value;
    notifyListeners();
  }

  /// Switches the timer to [preset] and remembers the choice.
  ///
  /// Rejected while the timer runs — see [canConfigure]. The dial resets to the
  /// new focus length, which is the point: the student is choosing how the next
  /// block should look.
  Future<bool> applyPreset(TimerPreset preset) async {
    if (!canConfigure) return false;
    _adoptPreset(preset.sanitized());
    notifyListeners();
    await LocalPrefs.setActiveTimerId(_preset.id);
    return true;
  }

  /// Saves a preset of the student's own and switches to it.
  ///
  /// Editing an existing custom preset means passing its id back; anything else
  /// is appended.
  Future<bool> saveCustomPreset(TimerPreset preset) async {
    final clean = preset.sanitized();
    final index = _customPresets.indexWhere((p) => p.id == clean.id);
    _customPresets = [
      if (index < 0) ...[..._customPresets, clean],
      if (index >= 0)
        for (final p in _customPresets) p.id == clean.id ? clean : p,
    ];
    await LocalPrefs.setTimerPresets(_customPresets);
    // Saving while a block runs keeps the preset but leaves the block alone.
    if (!canConfigure) {
      notifyListeners();
      return false;
    }
    return applyPreset(clean);
  }

  Future<void> deleteCustomPreset(String id) async {
    _customPresets = _customPresets.where((p) => p.id != id).toList();
    await LocalPrefs.setTimerPresets(_customPresets);
    // Deleting the preset in use falls back to the default rather than leaving
    // the dial describing something that no longer exists.
    if (_preset.id == id && canConfigure) {
      _adoptPreset(TimerPreset.fallback);
      await LocalPrefs.setActiveTimerId(_preset.id);
    }
    notifyListeners();
  }

  /// Adopts [preset] and rebuilds the dial from it. Callers notify.
  void _adoptPreset(TimerPreset preset) {
    _preset = preset;
    _phase = PomodoroPhase.focus;
    _completedFocusBlocks = 0;
    _setPhaseDuration();
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
    _setPhaseDuration();
    notifyListeners();
  }

  /// Ends the block early and moves on. A skipped focus block is not logged —
  /// the student didn't finish it — and the next block waits for a tap, since
  /// ending one by hand shouldn't silently start another.
  void skip() {
    _ticker?.cancel();
    _running = false;
    _advancePhase(logCompletedFocus: false, autoStart: false);
  }

  void _tick() {
    if (_secondsLeft > 0) _secondsLeft--;
    if (_secondsLeft > 0) {
      notifyListeners();
      return;
    }
    // Hit zero. Record what just finished for the completion popup, then chain
    // straight into the next block — leaving it paused was the reported
    // "changing to next session timer is not working" bug.
    _lastCompletedPhase = _phase;
    _lastCompletedMinutes = isFocus ? _preset.focusMinutes : null;
    _advancePhase(logCompletedFocus: true, autoStart: true);
    _startedPhase = _phase;
    _completionTick++;
    notifyListeners();
  }

  /// Moves to the next phase, persisting the block if a focus block just ran to
  /// completion.
  void _advancePhase({
    required bool logCompletedFocus,
    required bool autoStart,
  }) {
    final finishedFocus = _phase == PomodoroPhase.focus;

    if (finishedFocus) {
      _completedFocusBlocks++;
      final useLong = _completedFocusBlocks % _preset.rounds == 0;
      _phase = useLong ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak;
    } else {
      _phase = PomodoroPhase.focus;
    }

    _setPhaseDuration();

    if (autoStart) {
      _running = true;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _running = false;
    }
    notifyListeners();

    if (finishedFocus && logCompletedFocus) {
      // Fire-and-forget: the timer shouldn't stall on a network write.
      unawaited(_logSession(_preset.focusMinutes));
    }
  }

  /// Loads the current phase's length and freezes it as the denominator for
  /// [progress].
  void _setPhaseDuration() {
    _phaseTotalSeconds = switch (_phase) {
      PomodoroPhase.focus => _preset.focusMinutes * 60,
      PomodoroPhase.shortBreak => _preset.shortBreakMinutes * 60,
      PomodoroPhase.longBreak => _preset.longBreakMinutes * 60,
    };
    _secondsLeft = _phaseTotalSeconds;
  }

  /// One completed focus block. `recordSession` derives the XP from the minutes
  /// server-side, so the store never names an amount.
  Future<void> _logSession(int minutes) async {
    await runMutation(() async {
      await _game.recordSession(
        subjectId: _subjectId,
        lengthMin: minutes,
        focusedMin: minutes,
      );
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
