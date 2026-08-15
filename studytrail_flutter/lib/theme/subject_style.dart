import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';

/// Resolves a subject to an icon + accent colour.
///
/// The DB carries optional `icon_key` / `color_key` strings (set by the AI when
/// it generates subjects). When they're absent — a hand-typed subject — the
/// name is matched against common CS papers, and anything unrecognised falls
/// back to a stable hash so the same subject always gets the same colour
/// instead of flickering between rebuilds.
class SubjectStyle {
  const SubjectStyle(this.icon, this.color);

  final IconData icon;
  final Color color;

  static const _icons = <String, IconData>{
    'database': Symbols.database,
    'memory': Symbols.memory,
    'lan': Symbols.lan,
    'code': Symbols.code,
    'functions': Symbols.functions,
    'hub': Symbols.hub,
    'account_tree': Symbols.account_tree,
    'science': Symbols.science,
    'calculate': Symbols.calculate,
    'book': Symbols.menu_book,
  };

  /// Keyword → icon, matched against the subject name in order.
  static const _keywords = <String, IconData>{
    'dbms': Symbols.database,
    'database': Symbols.database,
    'sql': Symbols.database,
    'operating': Symbols.memory,
    'os': Symbols.memory,
    'network': Symbols.lan,
    'algorithm': Symbols.account_tree,
    'data structure': Symbols.account_tree,
    'math': Symbols.functions,
    'discrete': Symbols.functions,
    'statistic': Symbols.calculate,
    'physics': Symbols.science,
    'chemistry': Symbols.science,
    'software': Symbols.code,
    'programming': Symbols.code,
    'java': Symbols.code,
    'python': Symbols.code,
    'web': Symbols.hub,
    'cloud': Symbols.hub,
  };

  static SubjectStyle of(
    BuildContext context, {
    required String name,
    String? iconKey,
    String? colorKey,
  }) {
    final p = context.p;
    final accents = <String, Color>{
      'primary': p.primary,
      'coral': p.coral,
      'green': p.green,
      'amber': p.amber,
      'violet': p.primary2,
    };
    final palette = [p.primary, p.coral, p.green, p.amber, p.primary2];

    final icon = _icons[iconKey] ?? _iconForName(name);
    final color = accents[colorKey] ?? palette[_stableIndex(name, palette.length)];
    return SubjectStyle(icon, color);
  }

  static IconData _iconForName(String name) {
    final lower = name.toLowerCase();
    for (final entry in _keywords.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return Symbols.menu_book;
  }

  /// Deterministic bucket from the name — same subject, same colour, always.
  static int _stableIndex(String name, int buckets) {
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % buckets;
  }
}
