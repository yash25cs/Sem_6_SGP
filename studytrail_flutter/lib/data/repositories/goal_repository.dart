import '../../models/models.dart';
import '../supabase_client.dart';

/// Reads and writes `goals` + `subjects`. RLS scopes every query to the
/// signed-in user, so no `user_id` filter is needed on selects.
class GoalRepository {
  const GoalRepository();

  /// The goal the app is currently working against — newest active one.
  Future<Goal?> getActiveGoal() async {
    final rows = await db
        .from('goals')
        .select()
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Goal.fromMap(rows.first);
  }

  /// Cheap existence check for the onboarding gate.
  Future<bool> hasAnyGoal() async {
    final rows = await db.from('goals').select('id').limit(1);
    return rows.isNotEmpty;
  }

  Future<List<Goal>> getGoals() async {
    final rows =
        await db.from('goals').select().order('created_at', ascending: false);
    return rows.map(Goal.fromMap).toList();
  }

  /// Makes [goalId] the goal the app works against.
  ///
  /// Two statements rather than one: PostgREST can't express
  /// `is_active = (id = $1)` in a single update, and adding an RPC for it would
  /// block this on applying another migration. The retire-others call goes
  /// first, so the worst outcome of a drop between them is *no* active goal —
  /// which the UI shows as "no goal" and the student can fix with another tap —
  /// rather than two, which would silently pick whichever is newer.
  Future<void> setActiveGoal(String goalId) async {
    await db
        .from('goals')
        .update({'is_active': false})
        .eq('is_active', true)
        .neq('id', goalId);
    await db.from('goals').update({'is_active': true}).eq('id', goalId);
  }

  /// Creates a goal and its subjects, and retires the previously active one.
  ///
  /// All three writes happen inside the `create_goal` RPC, so they succeed or
  /// fail together. Doing them here as three calls left a real failure mode: a
  /// drop after the first one deactivated the old goal but never created the
  /// new one, and the student was left with no active goal and no way to notice
  /// (REVIEW.md P1). `user_id` comes from the JWT inside the function, so it
  /// isn't sent.
  Future<Goal> createGoal({
    required String name,
    DateTime? examDate,
    Pace pace = Pace.steady,
    List<String> subjectNames = const [],
  }) async {
    final row = await db.rpc('create_goal', params: {
      'p_name': name,
      // date column → date-only, not a full timestamp.
      'p_exam_date': examDate?.toIso8601String().split('T').first,
      'p_pace': pace.db,
      'p_subjects': [
        for (final n in subjectNames)
          if (n.trim().isNotEmpty) n.trim(),
      ],
    });
    return Goal.fromMap(
      row is List ? row.first as Map<String, dynamic> : row as Map<String, dynamic>,
    );
  }

  /// Updates the fields that were passed and returns the saved row, so callers
  /// don't have to re-read to refresh their view.
  Future<Goal> updateGoal({
    required String goalId,
    String? name,
    DateTime? examDate,
    Pace? pace,
  }) async {
    final examDay = examDate?.toIso8601String().split('T').first;
    final row = await db
        .from('goals')
        .update({
          'name': ?name,
          'exam_date': ?examDay,
          'pace': ?pace?.db,
        })
        .eq('id', goalId)
        .select()
        .single();
    return Goal.fromMap(row);
  }

  Future<void> deleteGoal(String goalId) =>
      db.from('goals').delete().eq('id', goalId);

  Future<List<Subject>> getSubjects(String goalId) async {
    final rows =
        await db.from('subjects').select().eq('goal_id', goalId).order('name');
    return rows.map(Subject.fromMap).toList();
  }

  Future<void> toggleSubjectFocus(String subjectId, bool isFocus) =>
      db.from('subjects').update({'is_focus': isFocus}).eq('id', subjectId);
}
