import '../../models/models.dart';
import '../supabase_client.dart';

/// Reads and writes `profiles`. The row itself is created server-side by the
/// `handle_new_user` trigger, so this never inserts.
///
/// `level`, `xp`, and `xp_to_next` are deliberately absent: 0008_rewards.sql
/// revokes the client's UPDATE privilege on those columns, and XP is granted
/// only by the reward RPCs.
class ProfileRepository {
  const ProfileRepository();

  Future<Profile?> getMyProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final row =
        await db.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<Profile> updateProfile({
    String? fullName,
    String? enrollmentId,
    String? branch,
    String? college,
  }) async {
    final uid = requireUserId;
    final row = await db
        .from('profiles')
        .update({
          'full_name': ?fullName,
          'enrollment_id': ?enrollmentId,
          'branch': ?branch,
          'college': ?college,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', uid)
        .select()
        .single();
    return Profile.fromMap(row);
  }

  Future<List<Map<String, dynamic>>> getClasses() async {
    final rows = await db.from('classes').select().order('name');
    return rows;
  }

  Future<void> joinClass(String classId) async {
    await db
        .from('profiles')
        .update({'class_id': classId}).eq('id', requireUserId);
  }

  /// Clears `class_id` so the student leaves the leaderboard pool. Their
  /// history and badges stay.
  Future<void> leaveClass() async {
    await db.from('profiles').update({'class_id': null}).eq('id', requireUserId);
  }
}
