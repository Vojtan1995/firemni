import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';

/// Stavově podmíněné akce pro detail ucpávky (vedení / účetní / admin).
class SealStatusActions extends StatelessWidget {
  const SealStatusActions({
    super.key,
    required this.auth,
    required this.status,
    required this.reviewStatus,
    required this.offline,
    required this.onApprove,
    required this.onReturnForRepair,
    required this.onInvoice,
    required this.onRevertToDraft,
  });

  final AuthService auth;
  final String status;
  final String? reviewStatus;
  final bool offline;
  final VoidCallback onApprove;
  final VoidCallback onReturnForRepair;
  final VoidCallback onInvoice;
  final VoidCallback onRevertToDraft;

  @override
  Widget build(BuildContext context) {
    if (offline) return const SizedBox.shrink();
    if (status == 'invoiced') return const SizedBox.shrink();

    final children = <Widget>[];

    if (auth.canReviewSeal && (status == 'draft' || reviewStatus == 'returned')) {
      children.add(
        AppPrimaryButton(
          label: 'Schválit',
          fullWidth: false,
          onPressed: onApprove,
        ),
      );
      children.add(
        AppSecondaryButton(
          label: 'Vrátit k opravě',
          fullWidth: false,
          onPressed: onReturnForRepair,
        ),
      );
    }

    if (status == 'checked') {
      if (auth.canInvoiceSeal) {
        children.add(
          AppPrimaryButton(
            label: 'Fakturovat',
            fullWidth: false,
            onPressed: onInvoice,
          ),
        );
      }
      if (auth.canReviewSeal) {
        children.add(
          AppSecondaryButton(
            label: 'Vrátit na rozpracováno',
            fullWidth: false,
            onPressed: onRevertToDraft,
          ),
        );
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: children,
      ),
    );
  }
}
