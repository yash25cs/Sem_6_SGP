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

  /// Creates a goal and its subjects. `user_id` comes from the session, never
  /// from the caller. Marks any previous goal inactive so there's one focus.
  Future<Goal> createGoal({
    required String name,
    DateTime? examDate,
    Pace pace = Pace.steady,
    List<String> subjectNames = const [],
  }) async {
    final uid = requireUserId;

    await db.from('goals').update({'is_active': false}).eq('is_active', true);

    final draft = Goal(id: '', name: name, examDate: examDate, pace: pace);
    final row = await db
        .from('goals')
        .insert({...draft.toInsertMap(), 'user_id': uid})
        .select()
        .single();
    final goal = Goal.fromMap(row);

    if (subjectNames.isNotEmpty) {
      final rows = [
        for (final n in subjectNames)
          if (n.trim().isNotEmpty)
            {'user_id': uid, 'goal_id': goal.id, 'name': n.trim()},
      ];
      if (rows.isNotEmpty) await db.from('subjects').insert(rows);
    }
    return goal;
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
