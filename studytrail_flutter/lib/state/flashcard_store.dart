import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Flashcards screen: the deck list and a review session over the
/// cards that are due.
class FlashcardStore extends AsyncStore {
  FlashcardStore({FlashcardRepository? cards, GamificationRepository? game})
      : _cards = cards ?? const FlashcardRepository(),
        _game = game ?? const GamificationRepository();

  final FlashcardRepository _cards;
  final GamificationRepository _game;

  List<FlashcardDeck> _decks = const [];
  List<Flashcard> _queue = const [];
  int _index = 0;
  bool _revealed = false;
  int _reviewedThisSession = 0;

  List<FlashcardDeck> get decks => _decks;

  /// Cards remaining in the current review session.
  List<Flashcard> get queue => _queue;

  Flashcard? get current => _index < _queue.length ? _queue[_index] : null;

  /// True once the student has tapped to see the answer — the grade buttons
  /// only appear after this.
  bool get revealed => _revealed;

  bool get sessionFinished => _queue.isNotEmpty && _index >= _queue.length;
  int get reviewedThisSession => _reviewedThisSession;
  int get remaining => (_queue.length - _index).clamp(0, _queue.length);

  double get sessionProgress =>
      _queue.isEmpty ? 0 : _index / _queue.length;

  Future<void> load() => runLoad(() async {
        _decks = await _cards.getDecks();
      });

  /// Starts a review. Omit [deckId] to review everything that's due.
  Future<bool> startSession({String? deckId}) => runMutation(() async {
        _queue = await _cards.getDueCards(deckId: deckId);
        _index = 0;
        _revealed = false;
        _reviewedThisSession = 0;
      });

  void reveal() {
    if (_revealed) return;
    _revealed = true;
    notifyListeners();
  }

  /// Grades the current card and advances. The new schedule is computed by the
  /// `apply_sr_grade` RPC, so nothing here duplicates the SM-2 math.
  Future<void> grade(SrGrade grade) async {
    final card = current;
    if (card == null) return;

    // Advance immediately — waiting on the network between cards makes review
    // feel sluggish, and a failed grade is recoverable (the card stays due).
    _index++;
    _revealed = false;
    _reviewedThisSession++;
    notifyListeners();

    await runMutation(() async {
      await _cards.gradeCard(card, grade);
      if (sessionFinished) {
        await _game.logActivity(minutes: 0, xp: _reviewedThisSession);
        _decks = await _cards.getDecks();
      }
    });
  }

  Future<bool> createDeck(String name, {String? subjectId}) =>
      runMutation(() async {
        final deck = await _cards.createDeck(name: name, subjectId: subjectId);
        _decks = [deck, ..._decks];
      });

  Future<bool> addCard({
    required String deckId,
    required String front,
    required String back,
  }) =>
      runMutation(() async {
        await _cards.createCard(deckId: deckId, front: front, back: back);
        _decks = await _cards.getDecks();
      });

  Future<bool> deleteDeck(FlashcardDeck deck) => runMutation(() async {
        await _cards.deleteDeck(deck.id);
        _decks = _decks.where((d) => d.id != deck.id).toList();
      });
}
