import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../widgets/widgets.dart';
import 'seal_list_helpers.dart';

/// Kompaktní řádek seznamu ucpávek (Task 3.1).
class SealListRow extends StatelessWidget {
  const SealListRow({
    super.key,
    required this.seal,
    required this.isWorker,
    required this.hasConflict,
    required this.selected,
    required this.showCheckbox,
    required this.onTap,
    this.onSelectChanged,
  });

  final Map<String, dynamic> seal;
  final bool isWorker;
  final bool hasConflict;
  final bool selected;
  final bool showCheckbox;
  final VoidCallback onTap;
  final ValueChanged<bool?>? onSelectChanged;

  @override
  Widget build(BuildContext context) {
    final status = seal['status'] as String? ?? 'draft';
    final photoCount = seal['photoCount'] as int? ?? 0;
    final hasNote = sealHasNoteForList(seal, isWorker: isWorker);
    final reviewStatus = seal['reviewStatus'] as String?;
    final isReturned = reviewStatus == 'returned';
    final pendingSync = seal['isSynced'] == false;
    final placementPending = seal['markerPlacementPending'] == true;
    final unplaced = !placementPending && seal['hasMarker'] == false;
    final number = seal['sealNumber'] as String? ?? '?';

    return AppCard(
      borderColor: selected
          ? AppColors.accent.withValues(alpha: 0.5)
          : hasConflict || isReturned
              ? AppColors.error.withValues(alpha: 0.4)
              : null,
      showChevron: false,
      onTap: onTap,
      child: Row(
        children: [
          if (showCheckbox)
            Checkbox(value: selected, onChanged: onSelectChanged)
          else
            Icon(
              hasConflict ? Icons.warning_amber : Icons.circle,
              size: 10,
              color: hasConflict
                  ? AppColors.error
                  : AppTheme.statusColor(status),
            ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '#$number',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (photoCount > 0)
            _iconBadge(Icons.photo_camera_outlined, AppColors.textMuted),
          if (hasNote) _iconBadge(Icons.sticky_note_2_outlined, AppColors.textMuted),
          if (isReturned)
            _iconBadge(Icons.replay, AppColors.error),
          if (pendingSync)
            _iconBadge(Icons.cloud_upload_outlined, AppColors.warning),
          if (placementPending)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Tooltip(
                message: 'Čeká na zakreslení',
                child: Icon(Icons.pending_outlined,
                    size: 16, color: AppColors.warning),
              ),
            ),
          if (unplaced)
            _iconBadge(Icons.place_outlined, AppColors.warning),
          StatusBadge(
            status: status,
            conflict: hasConflict,
            compact: true,
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
        ],
      ),
    );
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Icon(icon, size: 16, color: color),
    );
  }
}
