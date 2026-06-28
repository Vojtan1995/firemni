import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../widgets/widgets.dart';
import 'seal_constants.dart';
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
    final pendingSync = seal['isSynced'] == false;
    final placementPending = seal['markerPlacementPending'] == true;
    final unplaced = !placementPending && seal['hasMarker'] == false;
    final number = seal['sealNumber'] as String? ?? '?';
    final trade = sealTradeLabel(seal['trade'] as String?);
    final photoPending = seal['photoPending'] as int? ?? 0;
    final photoFailed = seal['photoFailed'] as int? ?? 0;

    return AppCard(
      borderColor: selected
          ? AppColors.accent.withValues(alpha: 0.5)
          : hasConflict
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '#$number',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  trade,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                ),
              ],
            ),
          ),
          if (photoCount > 0)
            _iconBadge(Icons.photo_camera_outlined, AppColors.textMuted),
          if (photoFailed > 0)
            _photoStateBadge(Icons.broken_image_outlined, AppColors.error,
                photoFailed, 'Fotky se nepodařilo nahrát'),
          if (photoPending > 0)
            _photoStateBadge(Icons.cloud_upload_outlined, AppColors.warning,
                photoPending, 'Fotky čekají na nahrání'),
          if (hasNote) _iconBadge(Icons.sticky_note_2_outlined, AppColors.textMuted),
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

  Widget _photoStateBadge(
      IconData icon, Color color, int count, String tooltip) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Tooltip(
        message: tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 2),
            Text(
              '$count',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
