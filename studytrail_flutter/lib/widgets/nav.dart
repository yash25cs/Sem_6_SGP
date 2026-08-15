import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';

/// The five-item bottom navigation bar from the reference. Rounded top, active
/// item is a filled indigo pill.
class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.current, this.onTap});

  /// Index of the active destination (0=Home … 4=Profile).
  final int current;
  final ValueChanged<int>? onTap;

  static const _items = [
    (Symbols.home, 'Home'),
    (Symbols.calendar_month, 'Roadmap'),
    (Symbols.smart_toy, 'Chat'),
    (Symbols.style, 'Cards'),
    (Symbols.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < _items.length; i++)
              _NavItem(
                icon: _items[i].$1,
                label: _items[i].$2,
                active: i == current,
                onTap: () => onTap?.call(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.icon, required this.label, required this.active, this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final fg = active ? p.onPrimary : p.ink3;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? p.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: fg, fill: active ? 1 : 0, weight: active ? 600 : 500),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// The iOS-style status bar strip drawn at the top of each phone mock.
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.p.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('9:41',
              style: TextStyle(
                  color: c,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          Row(children: [
            Icon(Symbols.signal_cellular_alt, size: 15, color: c),
            const SizedBox(width: 5),
            Icon(Symbols.wifi, size: 15, color: c),
            const SizedBox(width: 5),
            Icon(Symbols.battery_full, size: 15, color: c),
          ]),
        ],
      ),
    );
  }
}
