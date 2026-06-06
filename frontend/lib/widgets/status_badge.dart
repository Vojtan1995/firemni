import 'package:flutter/material.dart';
import '../core/design_tokens.dart';
import '../core/theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.conflict = false,
    this.label,
    this.compact = false,
  });

  final String status;
  final bool conflict;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status, conflict: conflict);
    final text = label ?? AppTheme.statusLabel(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
