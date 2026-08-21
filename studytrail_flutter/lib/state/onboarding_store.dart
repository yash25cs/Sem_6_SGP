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

  /// How many materials one student may keep.
  ///
  /// Chosen for the free tier's actual costs, not as a round number: every file
  /// is re-read by Gemini on upload and its chunks are searched on every single
  /// question. The `chat` function returns the 6 best chunks regardless of how
  /// many exist, so past a point more files stop improving answers and only
  /// dilute retrieval — a stray page from a half-related PDF starts outranking
  /// the right unit. 20 covers a full semester's subjects with room to spare.
  static const maxMaterials = 20;

  List<StudyMaterial> _uploaded = const [];
  Goal? _goal;

  /// Files added during this session, newest first.
  List<StudyMaterial> get uploaded => _uploaded;
  Goal? get createdGoal => _goal;
  bool get hasMaterial => _uploaded.isNotEmpty;

  /// Whether another file may be added. Drives the disabled state on both the
  /// onboarding drop zone and the chat sheet's add button.
  bool get atLimit => _uploaded.length >= maxMaterials;

  /// Slots left before [maxMaterials] is reached.
  int get remainingSlots =>
      (maxMaterials - _uploaded.length).clamp(0, maxMaterials);

  Future<void> load() => runLoad(() async {
        _uploaded = await _materials.getMaterials();
      });

  /// Opens the system picker, uploads whatever was chosen, then asks the
  /// `embed-material` function to read each file. Returns how many files
  /// actually landed.
  ///
  /// 0 with no [error] means the user backed out, which isn't a failure and
  /// shouldn't produce a message. 0 with an error means the first file failed;
  /// a non-zero count with an error means the batch stopped partway, and those
  /// files really are stored — reporting 0 there would have told the student
  /// nothing happened while [uploaded] showed otherwise.
  Future<int> pickAndUpload(MaterialType sourceType) async {
    if (atLimit) {
      setError(
        'You already have $maxMaterials files. Remove one to add another.',
      );
      return 0;
    }

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: sourceType == MaterialType.syllabusPdf
          ? FileType.custom
          : FileType.any,
      // Only these three can be read: PDFs go through Gemini's document vision,
      // .txt/.md are split locally. A .docx or .pptx would upload fine and then
      // fail ingestion, so it isn't offered.
      allowedExtensions: sourceType == MaterialType.syllabusPdf
          ? const ['pdf', 'txt', 'md']
          : null,
    );
    if (result == null || result.files.isEmpty) return 0;

    // Paths are null on web; this app ships to Android, so a null path means
    // the platform couldn't materialise the file and it has to be skipped.
    final picked = result.files.where((f) => f.path != null).toList();
    if (picked.isEmpty) return 0;

    // Selecting 30 files at the picker is the easy way past the cap, so the
    // batch is trimmed here rather than refused — the first few land, and the
    // student is told the rest didn't.
    final skipped = picked.length - remainingSlots;
    final batch = skipped > 0 ? picked.take(remainingSlots).toList() : picked;

    var stored = 0;
    final fresh = <StudyMaterial>[];
    await runMutation(() async {
      for (final file in batch) {
        final saved = await _materials.uploadFile(
          file: File(file.path!),
          fileName: file.name,
          sourceType: sourceType,
        );
        _uploaded = [saved, ..._uploaded];
        fresh.add(saved);
        stored++;
      }
    });

    // Ingestion is a second pass, outside the mutation: a PDF the AI can't read
    // shouldn't make a successful upload look like it never happened. The file
    // is stored either way — the row's status is what says whether it's
    // searchable yet.
    await _ingestAll(fresh);

    // Set last so a real ingest failure keeps the more useful message.
    if (skipped > 0 && error == null) {
      setError(
        skipped == 1
            ? 'One file was skipped — that would pass the $maxMaterials-file '
                'limit.'
            : '$skipped files were skipped — those would pass the '
                '$maxMaterials-file limit.',
      );
    }
    return stored;
  }

  /// Retry for a row that ended up `failed` — reset it, ask again, then show
  /// whatever it became.
  Future<bool> reingest(StudyMaterial material) async {
    _patchStatus(material.id, IngestStatus.processing);
    final ok = await runMutation(() async {
      await _materials.reingest(material.id);
    });
    await _refresh(material.id);
    return ok;
  }

  /// Asks for ingestion one file at a time, then reads back the final status.
  Future<void> _ingestAll(List<StudyMaterial> materials) async {
    Object? firstFailure;
    for (final material in materials) {
      // A link has nothing to download; the function refuses it anyway.
      if (material.sourceType == MaterialType.videoLink) continue;

      _patchStatus(material.id, IngestStatus.processing);
      try {
        await _materials.requestIngest(material.id);
      } catch (e) {
        // Per file: one unreadable PDF shouldn't abandon the rest of the batch.
        // The first reason is the one shown — a list of them helps nobody.
        firstFailure ??= e;
      }
      await _refresh(material.id);
    }
    if (firstFailure != null) setError(firstFailure);
  }

  /// Shows a status locally while the function works, so the chip doesn't sit on
  /// "Uploaded" for the several seconds a PDF takes.
  void _patchStatus(String id, IngestStatus status) {
    _uploaded = [
      for (final m in _uploaded) m.id == id ? m.withStatus(status) : m,
    ];
    notifyListeners();
  }

  /// Replaces one row with the server's copy — the authoritative status.
  Future<void> _refresh(String id) async {
    try {
      final latest = await _materials.getMaterial(id);
      if (latest == null) return;
      _uploaded = [for (final m in _uploaded) m.id == id ? latest : m];
      notifyListeners();
    } catch (_) {
      // A stale status chip is a cosmetic loss next to the error already set.
    }
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
