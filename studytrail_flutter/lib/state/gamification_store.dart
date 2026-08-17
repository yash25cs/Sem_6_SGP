import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Achievements screen: streak, week dots, badge grid, and the
/// class leaderboard.
class GamificationStore extends AsyncStore {
  GamificationStore({GamificationRepository? game, ProfileRepository? profiles})
      : _game = game ?? const GamificationRepository(),
        _profiles = profiles ?? const ProfileRepository();

  final GamificationRepository _game;
  final ProfileRepository _profiles;

  Profile? _profile;
  Streak _streak = const Streak();
  List<AchievementBadge> _badges = const [];
  List<LeaderboardEntry> _leaderboard = const [];
  List<ActivityDay> _recent = const [];
  List<String> _newlyUnlocked = const [];

  Profile? get profile => _profile;
  Streak get streak => _streak;
  List<AchievementBadge> get badges => _badges;
  List<AchievementBadge> get unlockedBadges =>
      _badges.where((b) => b.unlocked).toList();
  List<LeaderboardEntry> get leaderboard => _leaderboard;

  /// Badge keys this load unlocked for the first time — empty on every visit
  /// after the one that earned them.
  List<String> get newlyUnlocked => _newlyUnlocked;

  int get unlockedCount => unlockedBadges.length;

  /// True/false per day for the current week, Monday-first — the row of dots
  /// under the streak counter.
  List<bool> get weekDots {
    final today = DateTime.now();
    final monday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));
    final active = {
      for (final d in _recent)
        if (d.isActive) DateTime(d.date.year, d.date.month, d.date.day),
    };
    return List.generate(
      7,
      (i) => active.contains(monday.add(Duration(days: i))),
    );
  }

  /// The caller's own row, if the leaderboard came back.
  LeaderboardEntry? get myRank =>
      _leaderboard.where((e) => e.isMe).firstOrNull;

  Future<void> load() => runLoad(() async {
        // Catch up on badges first, so anything earned since the last visit is
        // already unlocked in the rows read below. The reward RPCs run the same
        // server-side check, so this only picks up the conditions no reward
        // touches — roadmap generated, questions asked, goal finished.
        //
        // Guarded because this is the first await in the load: a project still
        // on 0007 has no `evaluate_badges`, and letting that 404 escape would
        // blank the whole screen — streak, badges, and activity all read fine
        // without it. Catching up is an optimisation, not the data.
        try {
          _newlyUnlocked = await _game.evaluateBadges();
        } catch (_) {
          _newlyUnlocked = const [];
        }

        final results = await Future.wait([
          _profiles.getMyProfile(),
          _game.getStreak(),
          _game.getBadges(),
          _game.getRecentActivity(days: 14),
        ]);
        _profile = results[0] as Profile?;
        _streak = results[1] as Streak;
        _badges = results[2] as List<AchievementBadge>;
        _recent = results[3] as List<ActivityDay>;

        // Leaderboard needs a class; the RPC returns nothing when unset, and a
        // student who hasn't joined a class shouldn't see an error for it.
        try {
          _leaderboard = await _game.getLeaderboard();
        } catch (_) {
          _leaderboard = const [];
        }
      });
}
