import 'package:flutter/material.dart';
import '../core/design_tokens.dart';

class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({
    super.key,
    this.label = 'Offline',
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off,
            size: compact ? 14 : 16,
            color: AppColors.warning,
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.warning,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OnlineIndicator extends StatelessWidget {
  const OnlineIndicator({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 8 : 10,
      height: compact ? 8 : 10,
      decoration: const BoxDecoration(
        color: AppColors.success,
        shape: BoxShape.circle,
      ),
    );
  }
}
