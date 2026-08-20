import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'async_store.dart';

/// Backs the Chat screen. The answer comes from the `chat` Edge Function, which
/// writes both turns server-side; this store shows optimistic bubbles and then
/// reloads the thread from the table.
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
      try {
        await _chat.askAi(threadId: thread.id, question: body);
      } on FunctionException catch (e) {
        // Not deployed on this project. Fall back to what this store did before
        // the function existed: keep the question so it isn't lost, and let the
        // screen show a thread with no reply rather than a red screen.
        if (e.status != 404) rethrow;
        await _chat.addMessage(
          threadId: thread.id,
          role: ChatRole.user,
          text: body,
        );
      }
      // Reloading drops the optimistic bubbles and picks up both stored turns
      // along with their citation chips.
      _messages = await _chat.getMessages(thread.id);
    } catch (e) {
      _messages = _messages
          .where((m) => !m.isPending && !m.id.startsWith('_local_'))
          .toList();
      setError(e);
      // The function saves the question before it calls the model, so a failure
      // partway through can leave it stored. Reload so the student sees their own
      // message where they left it rather than watching it disappear.
      try {
        _messages = await _chat.getMessages(thread.id);
      } catch (_) {
        // Offline, most likely — the error already set above is the real one.
      }
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
