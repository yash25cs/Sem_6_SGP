import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';

/// Study Buddy Room — a shared focus session with peers and a group timer.
class BuddyRoomScreen extends StatelessWidget {
  const BuddyRoomScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const StatusStrip(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back, onTap: onBack),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DBMS War Room',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                    Row(children: [
                      Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: p.green, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text('4 studying now',
                          style: TextStyle(color: p.ink3, fontSize: 12)),
                    ]),
                  ],
                ),
                const Spacer(),
                RoundIconButton(Symbols.logout, plain: false, color: p.error),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                // shared timer
                AppCard(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [p.primary, p.primary2]),
                  child: Column(
                    children: [
                      Text('GROUP FOCUS',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('23:14',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      const SizedBox(height: 6),
                      Text('Everyone’s heads down · silent mode',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                CardHeader('In the room'),
                Row(
                  children: [
                    _Peer('Yash', 'You', p.primary, true),
                    _Peer('Aarav', 'DBMS', p.coral, true),
                    _Peer('Isha', 'OS', p.green, true),
                    _Peer('Rehan', 'Break', p.amber, false),
                  ],
                ),
                const SizedBox(height: 22),

                CardHeader('Room chat'),
                _ChatLine('Aarav', 'anyone done with unit 3?', p.coral),
                _ChatLine('Isha', 'almost! locking protocols left', p.green),
                _ChatLine('You', 'same, let’s quiz after this session', p.primary,
                    me: true),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: p.line),
                        ),
                        child: Text('Message the room…',
                            style: TextStyle(color: p.ink3, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.primary,
                        boxShadow: p.glow,
                      ),
                      child: Icon(Symbols.send,
                          color: p.onPrimary, size: 22, fill: 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Peer extends StatelessWidget {
  const _Peer(this.name, this.status, this.color, this.active);
  final String name, status;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Expanded(
      child: Column(
        children: [
          Stack(
            children: [
              Opacity(
                opacity: active ? 1 : 0.45,
                child: GradAvatar(name[0],
                    size: 56,
                    colors: [color.withValues(alpha: 0.85), color]),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? p.green : p.amber,
                    border: Border.all(color: p.bg, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(name,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800)),
          Text(status, style: TextStyle(color: p.ink3, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine(this.name, this.text, this.color, {this.me = false});
  final String name, text;
  final Color color;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradAvatar(name[0],
              size: 32, colors: [color.withValues(alpha: 0.85), color]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        color: p.ink2,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: me ? p.primarySoft : p.card,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: me ? null : p.shadowSm,
                  ),
                  child: Text(text,
                      style: TextStyle(
                          color: me ? p.onPrimarySoft : p.ink,
                          fontSize: 13.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
