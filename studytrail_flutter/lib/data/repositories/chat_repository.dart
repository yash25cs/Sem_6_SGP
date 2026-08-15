import '../../models/models.dart';
import '../supabase_client.dart';

/// Chat threads and messages.
///
/// This repository only reads and writes rows. The actual answer comes from
/// the `chat` Edge Function (Phase C) — it writes both the user message and
/// the AI reply server-side, then this reloads the thread.
class ChatRepository {
  const ChatRepository();

  Future<List<ChatThread>> getThreads({int limit = 20}) async {
    final rows = await db
        .from('chat_threads')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(ChatThread.fromMap).toList();
  }

  /// Most recent thread, or a fresh one — the chat screen opens straight into
  /// a conversation rather than a thread list.
  Future<ChatThread> getOrCreateThread({String? goalId}) async {
    final existing = await db
        .from('chat_threads')
        .select()
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) return ChatThread.fromMap(existing);
    return createThread(goalId: goalId);
  }

  Future<ChatThread> createThread({String? title, String? goalId}) async {
    final row = await db
        .from('chat_threads')
        .insert({
          'user_id': requireUserId,
          'title': ?title,
          'goal_id': ?goalId,
        })
        .select()
        .single();
    return ChatThread.fromMap(row);
  }

  /// Full transcript, oldest first, with citation chips embedded.
  Future<List<ChatMessage>> getMessages(String threadId) async {
    final rows = await db
        .from('chat_messages')
        .select('*, chat_citations(*)')
        .eq('thread_id', threadId)
        .order('created_at');
    return rows.map(ChatMessage.fromMap).toList();
  }

  /// Persists a message. Used for the user's turn when running without the
  /// Edge Function; the AI turn is normally written server-side.
  Future<ChatMessage> addMessage({
    required String threadId,
    required ChatRole role,
    required String text,
  }) async {
    final row = await db
        .from('chat_messages')
        .insert({
          'user_id': requireUserId,
          'thread_id': threadId,
          'role': role.db,
          'text': text,
        })
        .select('*, chat_citations(*)')
        .single();
    return ChatMessage.fromMap(row);
  }

  Future<void> deleteThread(String threadId) =>
      db.from('chat_threads').delete().eq('id', threadId);
}
