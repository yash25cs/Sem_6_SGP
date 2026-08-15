import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Quiz screen: one question at a time, immediate feedback, and a
/// server-scored result at the end.
class QuizStore extends AsyncStore {
  QuizStore({QuizRepository? quizzes})
      : _quizzes = quizzes ?? const QuizRepository();

  final QuizRepository _quizzes;

  List<Quiz> _available = const [];
  Quiz? _quiz;
  QuizAttempt? _attempt;
  int _index = 0;
  int? _picked;
  final Map<String, int> _picks = {};

  List<Quiz> get available => _available;
  Quiz? get quiz => _quiz;
  QuizAttempt? get attempt => _attempt;

  List<QuizQuestion> get questions => _quiz?.questions ?? const [];
  QuizQuestion? get current =>
      _index < questions.length ? questions[_index] : null;

  /// The option the student tapped for the current question, or null.
  int? get picked => _picked;

  /// True once an option is tapped — the correct answer is revealed and the
  /// options lock until "Next".
  bool get answered => _picked != null;

  int get questionNumber => _index + 1;
  int get questionCount => questions.length;
  bool get isLastQuestion => _index >= questions.length - 1;

  /// Correct answers so far, for the running score chip.
  int get runningScore => _picks.entries
      .where((e) => questions
          .any((q) => q.id == e.key && q.correctIndex == e.value))
      .length;

  double get progress =>
      questions.isEmpty ? 0 : (_index + (answered ? 1 : 0)) / questions.length;

  Future<void> load({String? subjectId}) => runLoad(() async {
        _available = await _quizzes.getQuizzes(subjectId: subjectId);
      });

  /// Loads a quiz and opens an attempt row.
  Future<bool> start(String quizId) => runMutation(() async {
        _quiz = await _quizzes.getQuiz(quizId);
        _attempt = await _quizzes.startAttempt(quizId);
        _index = 0;
        _picked = null;
        _picks.clear();
      });

  void pick(int optionIndex) {
    if (_picked != null) return; // locked once answered
    final q = current;
    if (q == null) return;
    _picked = optionIndex;
    _picks[q.id] = optionIndex;
    notifyListeners();
  }

  /// Advances. Returns true when that was the last question, so the screen
  /// knows to call [finish] and show results.
  bool next() {
    if (_picked == null) return false;
    if (isLastQuestion) return true;
    _index++;
    _picked = null;
    notifyListeners();
    return false;
  }

  /// Scores the attempt server-side and stores the result.
  Future<bool> finish() => runMutation(() async {
        final attempt = _attempt;
        if (attempt == null) return;
        _attempt = await _quizzes.submit(
          attemptId: attempt.id,
          picks: Map.of(_picks),
        );
      });

  void reset() {
    _quiz = null;
    _attempt = null;
    _index = 0;
    _picked = null;
    _picks.clear();
    notifyListeners();
  }
}
