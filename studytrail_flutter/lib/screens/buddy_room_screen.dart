import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';
import '../widgets/nav.dart';

/// Study buddies — the student's class and the classmates actually in it.
///
/// Everything here comes from `profiles.class_id` and the `get_class_leaderboard`
/// RPC. Live presence ("studying now"), a shared group timer and room chat need
/// realtime channels that don't exist yet, so the screen says so rather than
/// showing peers who aren't there.
class BuddyRoomScreen extends StatefulWidget {
  const BuddyRoomScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<BuddyRoomScreen> createState() => _BuddyRoomScreenState();
}

class _BuddyRoomScreenState extends State<BuddyRoomScreen> {
  @override
  void initState() {
    super.initState();
    // Both stores live in `_SignedInScope` and are shared with Settings and
    // Achievements — only load what hasn't been loaded already.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profiles = context.read<ProfileStore>();
      if (!profiles.loaded) profiles.load();
      final game = context.read<GamificationStore>();
      if (!game.loaded) game.load();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    await context.read<ProfileStore>().load();
    if (mounted) await context.read<GamificationStore>().load();
  }

  /// Joining a class is what fills this screen — and the leaderboard.
  Future<void> _joinClass() async {
    final store = context.read<ProfileStore>();
    if (store.classes.isEmpty) await store.loadClasses();
    if (!mounted) return;

    if (store.classes.isEmpty) {
      _toast('No classes are set up yet.');
      return;
    }

    final p = context.p;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('Pick your class',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              for (final c in store.classes)
                ListTile(
                  leading: Icon(Symbols.groups, color: p.primary),
                  title: Text((c['name'] as String?) ?? 'Class',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.of(sheetContext).pop(c['id'] as String),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final ok = await store.joinClass(picked);
    if (!mounted) return;
    if (!ok) {
      _toast(store.error ?? 'Could not join that class');
      return;
    }
    // The leaderboard is class-scoped, so it only has rows once we're in one.
    await context.read<GamificationStore>().load();
  }

  Future<void> _leaveClass() async {
    final p = context.p;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Leave this class?',
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        content: Text(
            'You’ll drop off the class leaderboard. Your streak, XP and badges '
            'stay with you.',
            style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: p.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Leave',
                style: TextStyle(color: p.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final store = context.read<ProfileStore>();
    final ok = await store.leaveClass();
    if (!mounted) return;
    if (!ok) {
      _toast(store.error ?? 'Could not leave the class');
      return;
    }
    await context.read<GamificationStore>().load();
  }

  /// 1240 → "1,240".
  String _thousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final profiles = context.watch<ProfileStore>();
    final game = context.watch<GamificationStore>();

    final joined = profiles.profile?.classId != null;
    final members = game.leaderboard;
    final firstLoad = profiles.loading && !profiles.loaded;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: widget.onBack),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          joined
                              ? (profiles.className ?? 'Your class')
                              : 'Study buddies',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      Text(
                          !joined
                              ? 'Not in a group yet'
                              : members.isEmpty
                                  ? 'Just you so far'
                                  : '${members.length} '
                                      'classmate${members.length == 1 ? '' : 's'}',
                          style: TextStyle(color: p.ink3, fontSize: 12)),
                    ],
                  ),
                ),
                if (joined)
                  RoundIconButton(Symbols.logout,
                      plain: false,
                      color: p.error,
                      onTap: profiles.busy ? null : _leaveClass),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: p.primary,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (profiles.error != null)
                    ErrorNotice(
                      message: profiles.error!,
                      onRetry: () => context.read<ProfileStore>().load(),
                    ),

                  if (firstLoad)
                    const LoadingBlock(height: 180)
                  else if (!joined)
                    EmptyState(
                      icon: Symbols.groups,
                      title: 'You haven’t joined a group yet',
                      message:
                          'Join your class to see who else is preparing for the '
                          'same exams and how you rank against them.',
                      actionLabel: 'Join a class',
                      onAction: profiles.busy ? null : _joinClass,
                    )
                  else ...[
                    _ClassCard(
                      name: profiles.className ?? 'Your class',
                      memberCount: members.length,
                      myRank: game.myRank,
                    ),
                    const SizedBox(height: 20),
                    CardHeader('Classmates',
                        action: game.loading && !game.loaded
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: p.ink3, strokeWidth: 2),
                              )
                            : null),
                    if (game.loading && !game.loaded)
                      const LoadingBlock(height: 120)
                    else if (members.isEmpty)
                      EmptyState(
                        icon: Symbols.person_add,
                        title: 'Nobody else here yet',
                        message:
                            'You’re the first from this class on StudyTrail. '
                            'Classmates show up as soon as they join.',
                      )
                    else
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            for (final entry in members)
                              _MemberRow(
                                entry: entry,
                                xpLabel: '${_thousands(entry.xp)} XP',
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    AppCard(
                      color: p.card2,
                      shadow: false,
                      child: Row(
                        children: [
                          IconTile(Symbols.upcoming,
                              bg: p.primarySoft, fg: p.primary, size: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Live rooms are coming',
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text(
                                    'Shared focus timers and room chat land in a '
                                    'later update. For now you can see who’s in '
                                    'your class and where you stand.',
                                    style: TextStyle(
                                        color: p.ink3,
                                        fontSize: 12.5,
                                        height: 1.45)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient header card: which class, how many are on StudyTrail, and where the
/// student sits in it.
class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.name,
    required this.memberCount,
    required this.myRank,
  });

  final String name;
  final int memberCount;
  final LeaderboardEntry? myRank;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final rank = myRank;

    return AppCard(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.primary, p.primary2]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.groups,
                  color: Colors.white.withValues(alpha: 0.9), size: 20),
              const SizedBox(width: 8),
              Text('YOUR CLASS',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat('$memberCount', 'On StudyTrail'),
              _Stat(rank == null ? '—' : '#${rank.rank}', 'Your rank'),
              _Stat(rank == null ? '—' : 'Lv ${rank.level}', 'Your level'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// One classmate, ordered by XP — same shape the Achievements leaderboard uses.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.entry, required this.xpLabel});

  final LeaderboardEntry entry;
  final String xpLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final me = entry.isMe;

    final trophyColor = switch (entry.rank) {
      1 => p.amber,
      2 => p.ink3,
      3 => p.coral,
      _ => null,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: me ? p.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: trophyColor != null
                ? Icon(Symbols.trophy, color: trophyColor, size: 24, fill: 1)
                : Text('${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          GradAvatar(entry.initial, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me ? '${entry.fullName} (You)' : entry.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: me ? FontWeight.w800 : FontWeight.w700)),
                Text('Level ${entry.level}',
                    style: TextStyle(color: p.ink3, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(xpLabel,
              style: TextStyle(
                  color: me ? p.primary : p.ink2,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
