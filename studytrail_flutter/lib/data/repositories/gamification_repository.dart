import '../../models/models.dart';
import '../supabase_client.dart';

/// Streaks, XP, badges, leaderboard, and study sessions — the gamification
/// layer.
///
/// Reads only, plus two RPCs. Nothing here writes XP, activity, or a badge
/// directly: `0008_rewards.sql` revokes the client's INSERT/UPDATE on
/// `activity_log`, `streaks`, `user_badges`, and `study_sessions`, so the
/// reward RPCs are the only path in.
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

  /// Last 60 days of activity for the heatmap and weekly bars.
  Future<List<ActivityDay>> getRecentActivity({int days = 60}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await db
        .from('activity_log')
        .select()
        .gte('activity_date', _dateOnly(cutoff))
        .order('activity_date', ascending: true);
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
        .order('key', ascending: true);
    final all = rows.map(AchievementBadge.fromMap).toList();
    return onlyUnlocked ? all.where((b) => b.unlocked).toList() : all;
  }

  /// Re-checks every badge condition against the database and unlocks whatever
  /// is genuinely earned, returning the keys unlocked *by this call* — the cue
  /// for an "unlocked!" toast.
  ///
  /// Replaces the old `unlock_badge(key)` RPC, which took the client's word for
  /// which badge to grant. The reward RPCs run the same check server-side, so
  /// this is only needed for conditions no reward touches (roadmap generated,
  /// questions asked, goal finished).
  Future<List<String>> evaluateBadges() async {
    final result = await db.rpc('evaluate_badges');
    return (result as List?)?.cast<String>() ?? const [];
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

  /// Persists one finished Pomodoro block.
  ///
  /// `record_focus_session` validates the length, rejects a subject that isn't
  /// the caller's, caps the day's logged focus, then derives the XP from the
  /// minutes — so the client reports what it did, not what it earned. The
  /// returned row has no embedded subject name; re-read the list if you need it.
  Future<StudySession> recordSession({
    String? subjectId,
    int? lengthMin,
    int? focusedMin,
  }) async {
    final row = await db.rpc('record_focus_session', params: {
      'p_subject': subjectId,
      'p_length_min': lengthMin ?? 25,
      'p_focused_min': focusedMin,
    });
    return StudySession.fromMap(
      row is List
          ? row.first as Map<String, dynamic>
          : row as Map<String, dynamic>,
    );
  }

  static String _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;
}
