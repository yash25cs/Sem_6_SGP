import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Profile and Settings screens: the student's details, their active
/// goal, and class membership.
class ProfileStore extends AsyncStore {
  ProfileStore({ProfileRepository? profiles, GoalRepository? goals})
      : _profiles = profiles ?? const ProfileRepository(),
        _goals = goals ?? const GoalRepository();

  final ProfileRepository _profiles;
  final GoalRepository _goals;

  Profile? _profile;
  Goal? _goal;
  List<Map<String, dynamic>> _classes = const [];

  Profile? get profile => _profile;
  Goal? get activeGoal => _goal;

  /// Classes the student can join, for the settings picker.
  List<Map<String, dynamic>> get classes => _classes;

  Future<void> load() => runLoad(() async {
        final results = await Future.wait([
          _profiles.getMyProfile(),
          _goals.getActiveGoal(),
          // Needed to resolve `class_id` into a name for the Settings row.
          _profiles.getClasses(),
        ]);
        _profile = results[0] as Profile?;
        _goal = results[1] as Goal?;
        _classes = results[2] as List<Map<String, dynamic>>;
      });

  Future<bool> updateProfile({
    String? fullName,
    String? enrollmentId,
    String? branch,
    String? college,
  }) =>
      runMutation(() async {
        _profile = await _profiles.updateProfile(
          fullName: fullName,
          enrollmentId: enrollmentId,
          branch: branch,
          college: college,
        );
      });

  Future<bool> loadClasses() => runMutation(() async {
        _classes = await _profiles.getClasses();
      });

  Future<bool> joinClass(String classId) => runMutation(() async {
        await _profiles.joinClass(classId);
        _profile = await _profiles.getMyProfile();
      });

  Future<bool> leaveClass() => runMutation(() async {
        await _profiles.leaveClass();
        _profile = await _profiles.getMyProfile();
      });

  /// Display name of the class the student belongs to, once [loadClasses] has
  /// run. Null when they haven't joined one or the list isn't loaded yet.
  String? get className {
    final id = _profile?.classId;
    if (id == null) return null;
    final match = _classes.where((c) => c['id'] == id).firstOrNull;
    return match?['name'] as String?;
  }

  Future<bool> updateGoal({String? name, DateTime? examDate, Pace? pace}) =>
      runMutation(() async {
        final goal = _goal;
        if (goal == null) return;
        _goal = await _goals.updateGoal(
          goalId: goal.id,
          name: name,
          examDate: examDate,
          pace: pace,
        );
      });
}
