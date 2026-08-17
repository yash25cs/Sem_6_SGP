import '../../models/models.dart';
import '../supabase_client.dart';

/// Reads and writes `daily_tasks` — the Home screen checklist.
class TaskRepository {
  const TaskRepository();

  /// Tasks for a given day, newest-first within the day. Embeds the subject
  /// name so the list can show it without a second round-trip.
  Future<List<DailyTask>> getTasksForDate(DateTime date) async {
    final day = _dateOnly(date);
    final rows = await db
        .from('daily_tasks')
        .select('*, subjects(name)')
        .eq('scheduled_date', day)
        .order('done')
        .order('tag');
    return rows.map(DailyTask.fromMap).toList();
  }

  Future<List<DailyTask>> getTodayTasks() => getTasksForDate(DateTime.now());

  Future<DailyTask> createTask({
    required String title,
    String? goalId,
    String? subjectId,
    String? milestoneTaskId,
    int? durationMin,
    TaskTag tag = TaskTag.now,
    DateTime? scheduledDate,
  }) async {
    final draft = DailyTask(
      id: '',
      title: title,
      subjectId: subjectId,
      milestoneTaskId: milestoneTaskId,
      durationMin: durationMin,
      tag: tag,
      scheduledDate: scheduledDate ?? DateTime.now(),
    );
    final row = await db
        .from('daily_tasks')
        .insert({
          ...draft.toInsertMap(),
          'user_id': requireUserId,
          'goal_id': ?goalId,
        })
        .select('*, subjects(name)')
        .single();
    return DailyTask.fromMap(row);
  }

  /// Flips a task's done state through the `complete_task` RPC.
  ///
  /// The RPC also mirrors the linked roadmap checkbox and pays out XP — in one
  /// transaction, and only for a task's *first* completion, so re-ticking is
  /// worth nothing. Doing the mirror here as a second call could leave the two
  /// screens disagreeing if it failed.
  Future<DailyTask> setDone(DailyTask task, bool done) async {
    final row = await db.rpc('complete_task', params: {
      'p_task': task.id,
      'p_done': done,
    });
    final saved = DailyTask.fromMap(
      row is List
          ? row.first as Map<String, dynamic>
          : row as Map<String, dynamic>,
    );
    // The RPC returns a bare row, so keep the subject name the list is already
    // showing — a done-toggle can't have changed it.
    return task.copyWith(done: saved.done, tag: saved.tag);
  }

  Future<void> deleteTask(String taskId) =>
      db.from('daily_tasks').delete().eq('id', taskId);

  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;
}
