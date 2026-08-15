import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Chat screen. Until the `chat` Edge Function lands (Phase C) the
/// user's turn is persisted but no answer is generated — the screen shows that
/// state rather than faking a reply.
class ChatStore extends AsyncStore {
  ChatStore({ChatRepository? chat, GoalRepository? goals})
      : _chat = chat ?? const ChatRepository(),
        _goals = goals ?? const GoalRepository();

  final ChatRepository _chat;
  final GoalRepository _goals;

  ChatThread? _thread;
  List<ChatMessage> _messages = const [];
  bool _sending = false;

  ChatThread? get thread => _thread;

  /// Transcript oldest-first, including the optimistic bubbles shown while a
  /// reply is in flight.
  List<ChatMessage> get messages => _messages;

  /// True while waiting on a reply — the composer disables its send button.
  bool get sending => _sending;

  bool get isEmpty => loaded && _messages.isEmpty;

  Future<void> load() => runLoad(() async {
        final goal = await _goals.getActiveGoal();
        final thread = await _chat.getOrCreateThread(goalId: goal?.id);
        _thread = thread;
        _messages = await _chat.getMessages(thread.id);
      });

  /// Sends a question. Shows the user's message and a pending bubble
  /// immediately, then reconciles against what the server stored.
  Future<void> send(String text) async {
    final body = text.trim();
    final thread = _thread;
    if (body.isEmpty || thread == null || _sending) return;

    _sending = true;
    _messages = [
      ..._messages,
      ChatMessage.localUser(body),
      ChatMessage.pending(),
    ];
    notifyListeners();

    try {
      await _chat.addMessage(
        threadId: thread.id,
        role: ChatRole.user,
        text: body,
      );
      // The AI reply is written by the `chat` Edge Function; wired in Phase C.
      // Reloading drops the optimistic bubbles and picks up whatever exists.
      _messages = await _chat.getMessages(thread.id);
    } catch (e) {
      _messages = _messages
          .where((m) => !m.isPending && !m.id.startsWith('_local_'))
          .toList();
      setError(e);
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Starts a fresh conversation.
  Future<bool> newThread() => runMutation(() async {
        final goal = await _goals.getActiveGoal();
        _thread = await _chat.createThread(goalId: goal?.id);
        _messages = const [];
      });
}
