import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';

enum _SealStatusMenuAction { checked, invoiced, revertToDraft }

/// Jedno tlačítko se stavovou nabídkou akcí pro detail ucpávky (vedení / admin).
class SealStatusActions extends StatelessWidget {
  const SealStatusActions({
    super.key,
    required this.auth,
    required this.status,
    required this.offline,
    required this.onApprove,
    required this.onInvoice,
    required this.onRevertToDraft,
  });

  final AuthService auth;
  final String status;
  final bool offline;
  final VoidCallback onApprove;
  final VoidCallback onInvoice;
  final VoidCallback onRevertToDraft;

  @override
  Widget build(BuildContext context) {
    if (offline) return const SizedBox.shrink();
    if (status == 'invoiced') return const SizedBox.shrink();

    final items = <PopupMenuEntry<_SealStatusMenuAction>>[];

    if (status == 'draft' && auth.canReviewSeal) {
      items.add(
        const PopupMenuItem(
          value: _SealStatusMenuAction.checked,
          child: Text('Zkontrolováno'),
        ),
      );
    }

    if (status == 'checked') {
      if (auth.canInvoiceSeal) {
        items.add(
          const PopupMenuItem(
            value: _SealStatusMenuAction.invoiced,
            child: Text('Fakturováno'),
          ),
        );
      }
      if (auth.canReviewSeal) {
        items.add(
          const PopupMenuItem(
            value: _SealStatusMenuAction.revertToDraft,
            child: Text('Vrátit na rozpracováno'),
          ),
        );
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: PopupMenuButton<_SealStatusMenuAction>(
        itemBuilder: (context) => items,
        onSelected: (action) {
          switch (action) {
            case _SealStatusMenuAction.checked:
              onApprove();
              break;
            case _SealStatusMenuAction.invoiced:
              onInvoice();
              break;
            case _SealStatusMenuAction.revertToDraft:
              onRevertToDraft();
              break;
          }
        },
        child: AbsorbPointer(
          child: AppPrimaryButton(
            label: 'Změnit stav',
            icon: Icons.expand_more,
            fullWidth: false,
            onPressed: () {},
          ),
        ),
      ),
    );
  }
}
