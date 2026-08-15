import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the two onboarding steps that write data: material upload and goal
/// creation. Kept separate from [ProfileStore] because it only lives for the
/// duration of onboarding — once the goal exists the app reads through the
/// per-tab stores instead.
class OnboardingStore extends AsyncStore {
  OnboardingStore({MaterialRepository? materials, GoalRepository? goals})
      : _materials = materials ?? const MaterialRepository(),
        _goals = goals ?? const GoalRepository();

  final MaterialRepository _materials;
  final GoalRepository _goals;

  List<StudyMaterial> _uploaded = const [];
  Goal? _goal;

  /// Files added during this session, newest first.
  List<StudyMaterial> get uploaded => _uploaded;
  Goal? get createdGoal => _goal;
  bool get hasMaterial => _uploaded.isNotEmpty;

  Future<void> load() => runLoad(() async {
        _uploaded = await _materials.getMaterials();
      });

  /// Opens the system picker and uploads whatever was chosen. Returns the
  /// number of files stored — 0 means the user backed out, which is not an
  /// error, so the caller shouldn't show a failure message for it.
  Future<int> pickAndUpload(MaterialType sourceType) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: sourceType == MaterialType.syllabusPdf
          ? FileType.custom
          : FileType.any,
      allowedExtensions: sourceType == MaterialType.syllabusPdf
          ? const ['pdf', 'docx', 'pptx']
          : null,
    );
    if (result == null || result.files.isEmpty) return 0;

    // Paths are null on web; this app ships to Android, so a null path means
    // the platform couldn't materialise the file and it has to be skipped.
    final picked = result.files.where((f) => f.path != null).toList();
    if (picked.isEmpty) return 0;

    var stored = 0;
    final ok = await runMutation(() async {
      for (final file in picked) {
        final saved = await _materials.uploadFile(
          file: File(file.path!),
          fileName: file.name,
          sourceType: sourceType,
        );
        _uploaded = [saved, ..._uploaded];
        stored++;
      }
    });
    return ok ? stored : 0;
  }

  Future<bool> addLink(String url, {String? title}) => runMutation(() async {
        final saved = await _materials.addLink(url: url, title: title);
        _uploaded = [saved, ..._uploaded];
      });

  Future<bool> removeMaterial(StudyMaterial material) => runMutation(() async {
        await _materials.deleteMaterial(material);
        _uploaded = _uploaded.where((m) => m.id != material.id).toList();
      });

  /// Creates the goal (and its subjects) that the rest of the app hangs off.
  /// The AI roadmap generation that follows lands in Phase C.
  Future<bool> createGoal({
    required String name,
    DateTime? examDate,
    Pace pace = Pace.steady,
    List<String> subjects = const [],
  }) =>
      runMutation(() async {
        _goal = await _goals.createGoal(
          name: name,
          examDate: examDate,
          pace: pace,
          subjectNames: subjects,
        );
      });
}
