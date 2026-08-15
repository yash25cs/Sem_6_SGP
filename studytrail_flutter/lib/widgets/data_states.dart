import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// Placeholder block shown while a screen's first fetch is in flight. Sized
/// like the content it replaces so the layout doesn't jump when data lands.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(color: p.ink3, strokeWidth: 2.4),
        ),
      ),
    );
  }
}

/// "Nothing here yet" state with an optional call to action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      child: Column(
        children: [
          IconTile(icon, bg: p.primarySoft, fg: p.primary, size: 54),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink3, fontSize: 13, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            PillButton(actionLabel!, onTap: onAction),
          ],
        ],
      ),
    );
  }
}

/// Failure state with a retry. Shows the friendly message the repository layer
/// produced, never a raw exception.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: p.errorSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.error.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.error, color: p.error, size: 22, fill: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: p.onError, fontSize: 13, height: 1.45),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text('Retry',
                  style: TextStyle(
                      color: p.error, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}
