import '../../models/models.dart';
import '../supabase_client.dart';

/// Streaks, XP, badges, leaderboard, and study sessions — the gamification
/// layer. Heavy lifting is done by the RPCs in
/// `supabase/migrations/0007_activity.sql`; this repository mostly reads.
class GamificationRepository {
  const GamificationRepository();

  Future<Streak> getStreak() async {
    final row = await db
        .from('streaks')
        .select()
        .eq('user_id', requireUserId)
        .maybeSingle();
    return row == null
        ? const Streak()
        : Streak.fromMap(row);
  }

  /// Grants XP and returns the updated profile. Server-side `award_xp` is
  /// atomic, so concurrent grants never lose each other's increments.
  Future<Profile> awardXp(int amount) async {
    final row = await db.rpc('award_xp', params: {'amount': amount});
    return Profile.fromMap(
      row is List ? row.first as Map<String, dynamic> : row as Map<String, dynamic>,
    );
  }

  /// Records minutes/tasks/XP for today and rolls the streak forward.
  Future<void> logActivity({
    int minutes = 0,
    int tasks = 0,
    int xp = 0,
  }) async {
    await db.rpc('log_activity', params: {
      'minutes': minutes,
      'tasks': tasks,
      'xp': xp,
    });
  }

  /// Last 60 days of activity for the heatmap and weekly bars.
  Future<List<ActivityDay>> getRecentActivity({int days = 60}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await db
        .from('activity_log')
        .select()
        .gte('activity_date', _dateOnly(cutoff))
        .order('activity_date');
    return rows.map(ActivityDay.fromMap).toList();
  }

  /// The badge catalog, each with whether the caller has it. For "my badges",
  /// filter [unlocked] client-side.
  ///
  /// `!left` keeps locked badges in the result — a plain embed would inner-join
  /// and drop every badge the user hasn't earned yet. RLS on `user_badges`
  /// already restricts the embedded rows to the caller, so no filter is needed.
  Future<List<AchievementBadge>> getBadges({bool onlyUnlocked = false}) async {
    final rows = await db
        .from('badges')
        .select('*, user_badges!left(*)')
        .order('key');
    final all = rows.map(AchievementBadge.fromMap).toList();
    return onlyUnlocked ? all.where((b) => b.unlocked).toList() : all;
  }

  /// Idempotent unlock; true only the first time — the cue for the toast.
  Future<bool> unlockBadge(String badgeKey) async {
    final row = await db.rpc('unlock_badge', params: {'badge_key': badgeKey});
    return row == true;
  }

  /// Classmates ordered by XP. `is_me` comes from the RPC; rank is assigned
  /// client-side from the returned order.
  Future<List<LeaderboardEntry>> getLeaderboard({int limit = 20}) async {
    final result =
        await db.rpc('get_class_leaderboard', params: {'limit_count': limit});
    final rows = (result as List).cast<Map<String, dynamic>>();
    return rows.indexed
        .map((e) => LeaderboardEntry.fromMap(e.$2, rank: e.$1 + 1))
        .toList();
  }

  /// Completed Pomodoro sessions, newest first.
  Future<List<StudySession>> getStudySessions({int limit = 50}) async {
    final rows = await db
        .from('study_sessions')
        .select('*, subjects(name)')
        .eq('user_id', requireUserId)
        .order('started_at', ascending: false)
        .limit(limit);
    return rows.map(StudySession.fromMap).toList();
  }

  /// Persists one finished Pomodoro block and grants its XP in one shot.
  Future<StudySession> recordSession({
    String? subjectId,
    int? lengthMin,
    int sessionsCount = 1,
    int? focusedMin,
  }) async {
    final row = await db
        .from('study_sessions')
        .insert({
          'user_id': requireUserId,
          'subject_id': ?subjectId,
          'length_min': ?lengthMin,
          'sessions_count': sessionsCount,
          'focused_min': ?focusedMin,
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('*, subjects(name)')
        .single();
    return StudySession.fromMap(row);
  }

  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;
}
