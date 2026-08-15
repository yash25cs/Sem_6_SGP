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

  /// Flips a task's done state. Also mirrors it onto the linked roadmap task
  /// so the two screens agree.
  Future<DailyTask> setDone(DailyTask task, bool done) async {
    final row = await db
        .from('daily_tasks')
        .update({'done': done, 'tag': done ? TaskTag.done.db : TaskTag.now.db})
        .eq('id', task.id)
        .select('*, subjects(name)')
        .single();

    if (task.milestoneTaskId != null) {
      await db
          .from('milestone_tasks')
          .update({'done': done}).eq('id', task.milestoneTaskId!);
    }
    return DailyTask.fromMap(row);
  }

  Future<void> deleteTask(String taskId) =>
      db.from('daily_tasks').delete().eq('id', taskId);

  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;
}
