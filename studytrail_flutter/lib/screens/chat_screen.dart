import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/data_states.dart';

/// Chat tab — the AI study companion Q&A thread.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Enables/disables the send button without rebuilding the whole tree on
  /// every keystroke — only this flag flips.
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final can = _input.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ChatStore>().load();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final store = context.read<ChatStore>();
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || store.sending) return;

    if (preset == null) _input.clear();
    FocusScope.of(context).unfocus();

    await store.send(text);
    _scrollToBottom();
  }

  /// Jumps to the newest message once the list has laid out the new bubbles.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final store = context.watch<ChatStore>();
    final messages = store.messages;

    return Column(
      children: [
        // header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [p.primary, p.primary2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  boxShadow: p.glow,
                ),
                child: const Icon(Symbols.smart_toy,
                    color: Colors.white, size: 24, fill: 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trail AI',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Row(children: [
                      Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: store.sending ? p.amber : p.green,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(
                          store.sending
                              ? 'Thinking…'
                              : 'Knows your syllabus',
                          style: TextStyle(color: p.ink3, fontSize: 12)),
                    ]),
                  ],
                ),
              ),
              // A fresh thread is the closest thing to "clear chat" while
              // history stays on the server.
              RoundIconButton(Symbols.edit_square,
                  plain: false,
                  onTap: store.busy
                      ? null
                      : () => context.read<ChatStore>().newThread()),
            ],
          ),
        ),
        Divider(color: p.line, height: 1),

        // messages
        Expanded(
          child: store.loading && !store.loaded
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: LoadingBlock(height: 140),
                )
              : store.messages.isEmpty
                  ? _EmptyThread(onAsk: _send)
                  : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      itemCount: messages.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, i) {
                        if (i == 0) return const _DayChip('Conversation');
                        final message = messages[i - 1];
                        if (message.isPending) return _TypingBubble();
                        return _MessageBlock(message: message);
                      },
                    ),
        ),

        if (store.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: ErrorNotice(
              message: store.error!,
              onRetry: () => context.read<ChatStore>().clearError(),
            ),
          ),

        // suggestion chips + composer
        Container(
          decoration: BoxDecoration(
            color: p.card,
            border: Border(top: BorderSide(color: p.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final (label, icon) in const [
                        ('Summarize this unit', Symbols.summarize),
                        ('Make 5 flashcards', Symbols.style),
                        ('Explain simply', Symbols.lightbulb),
                      ]) ...[
                        SoftChip(label,
                            icon: icon,
                            tone: ChipTone.neutral,
                            small: true,
                            onTap: store.sending ? null : () => _send(label)),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: p.card2,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: p.line),
                        ),
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          style: TextStyle(
                              color: p.ink, fontSize: 14, height: 1.4),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                            hintText: 'Ask anything about your syllabus…',
                            hintStyle:
                                TextStyle(color: p.ink3, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _SendButton(
                      enabled: _canSend && !store.sending,
                      sending: store.sending,
                      onTap: _send,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return InkWell(
      onTap: enabled ? onTap : null,
      customBorder: const CircleBorder(),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? p.primary : p.card3,
          boxShadow: enabled ? p.glow : null,
        ),
        child: sending
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: CircularProgressIndicator(
                    color: p.onPrimary, strokeWidth: 2.4),
              )
            : Icon(Symbols.arrow_upward,
                color: enabled ? p.onPrimary : p.ink3,
                size: 24,
                weight: 700),
      ),
    );
  }
}

/// First-run state — a nudge plus starter questions.
class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.onAsk});

  final ValueChanged<String> onAsk;

  static const _starters = [
    'Explain the difference between 2NF and 3NF',
    'What should I revise first this week?',
    'Give me a quick summary of my weakest subject',
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
      children: [
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [p.primary, p.primary2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              boxShadow: p.glow,
            ),
            child: const Icon(Symbols.smart_toy,
                color: Colors.white, size: 34, fill: 1),
          ),
        ),
        const SizedBox(height: 18),
        Text('Ask me about your syllabus',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
            'I answer from the material you uploaded, so the explanations match '
            'what you actually have to study.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink3, fontSize: 13, height: 1.5)),
        const SizedBox(height: 22),
        for (final starter in _starters)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => onAsk(starter),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: p.shadowSm,
                ),
                child: Row(children: [
                  Icon(Symbols.auto_awesome, color: p.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(starter,
                        style: TextStyle(
                            color: p.ink2,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  Icon(Symbols.arrow_forward, color: p.ink3, size: 18),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

/// One message plus, for AI answers, its citation chips.
class _MessageBlock extends StatelessWidget {
  const _MessageBlock({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isUser || message.citations.isEmpty) {
      return _Bubble(text: message.text, me: message.isUser);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Bubble(text: message.text, me: false),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final citation in message.citations)
                SoftChip(citation.label,
                    icon: Symbols.menu_book,
                    tone: ChipTone.primary,
                    small: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: p.card2, borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(
                color: p.ink3, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.me});
  final String text;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: me ? p.primary : p.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(me ? 20 : 6),
          bottomRight: Radius.circular(me ? 6 : 20),
        ),
        boxShadow: me ? null : p.shadowSm,
      ),
      child: SelectableText(text,
          style: TextStyle(
              color: me ? p.onPrimary : p.ink,
              fontSize: 14,
              height: 1.5)),
    );

    if (me) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [p.primary, p.primary2]),
          ),
          child: const Icon(Symbols.smart_toy,
              color: Colors.white, size: 18, fill: 1),
        ),
        const SizedBox(width: 12),
        Flexible(child: bubble),
      ],
    );
  }
}

class _TypingBubble extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [p.primary, p.primary2]),
          ),
          child: const Icon(Symbols.smart_toy,
              color: Colors.white, size: 18, fill: 1),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: p.shadowSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(p.ink3),
              const SizedBox(width: 5),
              _dot(p.ink3.withValues(alpha: 0.6)),
              const SizedBox(width: 5),
              _dot(p.ink3.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dot(Color c) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}
