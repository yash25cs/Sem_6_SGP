import '../../models/models.dart';
import '../supabase_client.dart';

/// Reads and writes `milestones` + `milestone_tasks` — the Roadmap screen.
class RoadmapRepository {
  const RoadmapRepository();

  /// Milestones for a goal with their tasks nested, in display order.
  Future<List<Milestone>> getMilestones(String goalId) async {
    final rows = await db
        .from('milestones')
        .select('*, milestone_tasks(*)')
        .eq('goal_id', goalId)
        .order('order_index');
    return rows.map(Milestone.fromMap).toList();
  }

  /// Flips a roadmap checkbox and re-derives the parent milestone's state:
  /// all done → done, some done → active, none → upcoming.
  Future<MilestoneState> toggleTask(
    String milestoneId,
    String taskId,
    bool done,
  ) async {
    await db.from('milestone_tasks').update({'done': done}).eq('id', taskId);

    final siblings = await db
        .from('milestone_tasks')
        .select('done')
        .eq('milestone_id', milestoneId);

    final total = siblings.length;
    final doneCount =
        siblings.where((r) => (r['done'] as bool?) ?? false).length;

    final state = switch (doneCount) {
      0 => MilestoneState.upcoming,
      _ when doneCount == total => MilestoneState.done,
      _ => MilestoneState.active,
    };

    await db
        .from('milestones')
        .update({'state': state.db}).eq('id', milestoneId);
    return state;
  }

  /// Overall completion across a goal's roadmap tasks, counted and persisted by
  /// the `recompute_goal_progress` RPC.
  ///
  /// Deliberately not computed here: `goals.overall_percent` is the input to the
  /// goal_crusher badge, so it isn't the client's to assert. 0008_rewards.sql
  /// revokes UPDATE on that column.
  Future<double> recomputeGoalProgress(String goalId) async {
    final result = await db.rpc(
      'recompute_goal_progress',
      params: {'p_goal': goalId},
    );
    return (result as num?)?.toDouble() ?? 0;
  }

  Future<void> deleteMilestones(String goalId) =>
      db.from('milestones').delete().eq('goal_id', goalId);
}
