import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design_tokens.dart';
import '../../database/database_provider.dart';
import '../../widgets/widgets.dart';
import '../seals/seal_duplicate_local.dart';
import 'sync_conflict.dart';
import 'sync_service.dart';

final _sealNumberPattern = RegExp(r'^\d+$');

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _syncing = false;
  String? _message;

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _message = null;
    });
    final result = await ref.read(syncServiceProvider).syncAll();
    setState(() {
      _syncing = false;
      _message = result.offline ? 'Offline – data zůstávají lokálně' : 'Synchronizace dokončena';
    });
  }

  Future<void> _fixDuplicateNumber(SyncConflictView conflict) async {
    final controller = TextEditingController(text: conflict.sealNumber ?? '');
    final newNumber = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Opravit číslo ucpávky'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (conflict.jobLabel != null)
              Text('Stavba: ${conflict.jobLabel}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            if (conflict.floorName != null)
              Text('Patro: ${conflict.floorName}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Nové číslo ucpávky'),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: AppRadius.smAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.camera_alt_outlined,
                      size: 18, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Na štítku je staré číslo — doporučujeme pořídit '
                      'novou fotografii ucpávky se správným číslem.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Zrušit'),
          ),
          if (conflict.sealId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/seal/${conflict.sealId}');
              },
              child: const Text('Vyfotit znovu'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Uložit a synchronizovat'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newNumber == null || newNumber.isEmpty) return;
    if (!_sealNumberPattern.hasMatch(newNumber)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Číslo ucpávky musí obsahovat jen číslice')),
      );
      return;
    }

    final db = ref.read(databaseProvider);
    final error = await fixDuplicateSealNumberAndRequeue(
      db,
      outboxId: conflict.outboxId,
      newSealNumber: newNumber,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final result = await ref.read(syncServiceProvider).syncAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Číslo upraveno, synchronizace dokončena'
              : (result.offline
                  ? 'Číslo upraveno – synchronizace proběhne po připojení'
                  : 'Číslo upraveno – synchronizace selhala'),
        ),
      ),
    );
  }

  Future<void> _dismissConflict(String outboxId) async {
    final db = ref.read(databaseProvider);
    await dismissSyncConflict(db, outboxId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upozornění skryto – lokální data zůstávají zachována')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(connectivityProvider);
    final pending = ref.watch(syncPendingCountProvider);
    final queuedOutbox = ref.watch(syncQueuedOutboxCountProvider);
    final unsentPhotos = ref.watch(unsentPhotosCountProvider);
    final unsentPhotoList = ref.watch(unsentPhotosProvider);
    final conflicts = ref.watch(syncConflictsProvider);
    final dateFormat = DateFormat('d.M.y HH:mm');
    final isOnline = online.valueOrNull == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronizace')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            showChevron: false,
            leading: AppIconBox(
              icon: isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: isOnline ? AppColors.success : AppColors.warning,
              backgroundColor: (isOnline ? AppColors.success : AppColors.warning)
                  .withValues(alpha: 0.12),
            ),
            title: isOnline ? 'Online' : 'Offline',
            subtitle:
                'Připraveno k sync: ${pending.valueOrNull ?? 0}\n'
                'Outbox ve frontě: ${queuedOutbox.valueOrNull ?? 0}\n'
                'Neodeslané fotky: ${unsentPhotos.valueOrNull ?? 0}',
          ),
          unsentPhotoList.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: 'Neodeslané fotky', style: SectionHeaderStyle.h3),
                  ...items.take(5).map((item) {
                    final p = item.photo;
                    final label = item.sealNumber != null
                        ? 'Ucpávka č. ${item.sealNumber}'
                        : 'Ucpávka ${p.sealId.substring(0, 8)}…';
                    final statusLabel =
                        p.status == 'failed' ? 'Selhala' : 'Čeká na upload';
                    return AppCard(
                      showChevron: false,
                      leading: Icon(
                        p.status == 'failed'
                            ? Icons.error_outline
                            : Icons.photo_camera,
                        color: p.status == 'failed'
                            ? AppColors.error
                            : AppColors.warning,
                      ),
                      title: label,
                      subtitle: p.lastError != null && p.lastError!.isNotEmpty
                          ? '$statusLabel\n${p.lastError}'
                          : statusLabel,
                    );
                  }),
                  if (items.length > 5)
                    Text(
                      '… a dalších ${items.length - 5} fotek',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: 'Synchronizovat',
            icon: Icons.sync,
            loading: _syncing,
            onPressed: _sync,
          ),
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_message!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Konflikty synchronizace', style: SectionHeaderStyle.h3),
          conflicts.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('Chyba načtení konfliktů: $e'),
            data: (items) {
              if (items.isEmpty) {
                return AppCard(
                  showChevron: false,
                  leading: const Icon(Icons.check_circle_outline, color: AppColors.success),
                  title: 'Žádné aktivní konflikty',
                  subtitle: 'Lokální změny nejsou v konfliktu se serverem.',
                );
              }
              return Column(
                children: items.map((c) {
                  return AppCard(
                    showChevron: false,
                    borderColor: AppColors.warning.withValues(alpha: 0.4),
                    color: AppColors.warning.withValues(alpha: 0.08),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber, color: AppColors.warning),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '${c.entityType} · ${c.operationLabel}',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        if (c.sealNumber != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text('Ucpávka č. ${c.sealNumber}'),
                        ],
                        if (isDuplicateConflictMessage(c.conflictMessage)) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            duplicateConflictSummary(
                              attemptedNumber: c.sealNumber,
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (c.jobLabel != null) Text('Stavba: ${c.jobLabel}'),
                        if (c.floorName != null) Text('Patro: ${c.floorName}'),
                        const SizedBox(height: AppSpacing.sm),
                        Text('Důvod: ${c.conflictMessage}'),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Čas: ${dateFormat.format(c.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (c.entityType == 'seal' &&
                                isDuplicateConflictMessage(c.conflictMessage))
                              TextButton.icon(
                                onPressed: () => _fixDuplicateNumber(c),
                                icon: const Icon(Icons.edit),
                                label: const Text('Opravit číslo'),
                              ),
                            TextButton.icon(
                              onPressed: () => _dismissConflict(c.outboxId),
                              icon: const Icon(Icons.visibility_off),
                              label: const Text('Skrýt'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
