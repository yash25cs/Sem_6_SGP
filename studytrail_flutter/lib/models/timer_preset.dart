/// A named set of Pomodoro durations, optionally with a note from the student.
///
/// Unlike every other model here this one never goes to Postgres — presets are
/// a preference about how *this* student likes to work on *this* phone, so they
/// live in `shared_preferences` via `LocalPrefs`. That's why there is a
/// [toJson]/[fromJson] pair and no `fromMap`/`toInsertMap`.
class TimerPreset {
  const TimerPreset({
    required this.id,
    required this.label,
    required this.focusMinutes,
    required this.shortBreakMinutes,
    required this.longBreakMinutes,
    required this.rounds,
    this.description,
    this.isBuiltIn = false,
  });

  /// Stable key. Built-ins use a readable slug so a saved choice still resolves
  /// after an app update; custom presets get a timestamp-based id at creation.
  final String id;
  final String label;

  /// The student's own note — "revision only", "no phone" — shown under the
  /// dial. Optional by design: the timer is useful without it.
  final String? description;

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  /// Focus blocks before the long break replaces the short one.
  final int rounds;

  /// Shipped with the app, so it can't be deleted.
  final bool isBuiltIn;

  /// Shortest sensible block is a minute — anything less makes the dial and the
  /// logged session meaningless. The ceilings keep a typo from producing a
  /// timer that never ends.
  static const int minMinutes = 1;
  static const int maxMinutes = 180;
  static const int minRounds = 1;
  static const int maxRounds = 12;

  static const List<TimerPreset> builtIns = [
    TimerPreset(
      id: 'classic',
      label: 'Classic',
      description: 'The original Pomodoro rhythm.',
      focusMinutes: 25,
      shortBreakMinutes: 5,
      longBreakMinutes: 15,
      rounds: 4,
      isBuiltIn: true,
    ),
    TimerPreset(
      id: 'deep-work',
      label: 'Deep work',
      description: 'Long stretches for problem sets and past papers.',
      focusMinutes: 50,
      shortBreakMinutes: 10,
      longBreakMinutes: 20,
      rounds: 3,
      isBuiltIn: true,
    ),
    TimerPreset(
      id: 'short-burst',
      label: 'Short burst',
      description: 'For days when starting is the hard part.',
      focusMinutes: 15,
      shortBreakMinutes: 3,
      longBreakMinutes: 12,
      rounds: 4,
      isBuiltIn: true,
    ),
  ];

  static TimerPreset get fallback => builtIns.first;

  /// "25 / 5 · 4 rounds" — the subtitle in the preset list.
  String get summary =>
      '$focusMinutes / $shortBreakMinutes · $rounds round'
      '${rounds == 1 ? '' : 's'}';

  /// Clamps every field into range and drops a blank description, so neither a
  /// bad form entry nor a hand-edited preferences file can produce a preset the
  /// timer can't run.
  TimerPreset sanitized() {
    final note = description?.trim();
    return TimerPreset(
      id: id,
      label: label.trim().isEmpty ? 'Custom' : label.trim(),
      description: (note == null || note.isEmpty) ? null : note,
      focusMinutes: focusMinutes.clamp(minMinutes, maxMinutes),
      shortBreakMinutes: shortBreakMinutes.clamp(minMinutes, maxMinutes),
      longBreakMinutes: longBreakMinutes.clamp(minMinutes, maxMinutes),
      rounds: rounds.clamp(minRounds, maxRounds),
      isBuiltIn: isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (description != null) 'description': description,
        'focus': focusMinutes,
        'short': shortBreakMinutes,
        'long': longBreakMinutes,
        'rounds': rounds,
      };

  /// Returns null when the entry can't be read — a preferences file written by
  /// an older build, or one that's been tampered with. Callers skip nulls rather
  /// than losing the whole list to one bad row.
  static TimerPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    if (id is! String || id.isEmpty || label is! String) return null;
    final note = raw['description'];
    return TimerPreset(
      id: id,
      label: label,
      description: note is String ? note : null,
      focusMinutes: (raw['focus'] as num?)?.toInt() ?? 25,
      shortBreakMinutes: (raw['short'] as num?)?.toInt() ?? 5,
      longBreakMinutes: (raw['long'] as num?)?.toInt() ?? 15,
      rounds: (raw['rounds'] as num?)?.toInt() ?? 4,
    ).sanitized();
  }
}
