import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../database/database_provider.dart';
import '../auth/auth_provider.dart';
import 'sync_conflict.dart';
import 'sync_service.dart';

/// Sleduje přechod offline → online a pokud po opětovném připojení existují
/// nevyřešené konflikty duplicitních čísel ucpávek, upozorní uživatele
/// vyskakovací hláškou s odkazem na záložku Synchronizace.
class SyncConflictWatcher extends ConsumerStatefulWidget {
  const SyncConflictWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncConflictWatcher> createState() =>
      _SyncConflictWatcherState();
}

class _SyncConflictWatcherState extends ConsumerState<SyncConflictWatcher> {
  bool? _wasOnline;
  bool _dialogShown = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      next.whenData((online) {
        final cameBackOnline = _wasOnline == false && online;
        _wasOnline = online;
        if (cameBackOnline) {
          _checkConflictsSoon();
        }
      });
    });
    return widget.child;
  }

  Future<void> _checkConflictsSoon() async {
    // Krátká prodleva, aby doběhl automatický push sync po obnovení připojení.
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted || _dialogShown) return;

    final db = ref.read(databaseProvider);
    final userId = ref.read(currentUserIdProvider);
    final conflicts = await loadActiveSyncConflicts(db, userId: userId);
    if (conflicts.isEmpty || !mounted) return;

    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;

    _dialogShown = true;
    await showDialog<void>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicitní číslo ucpávky'),
        content: Text(
          conflicts.length == 1
              ? 'Jedna ucpávka má při synchronizaci duplicitní číslo. Oprav ji v záložce Synchronizace.'
              : '${conflicts.length} ucpávek má při synchronizaci duplicitní číslo. Oprav je v záložce Synchronizace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Později'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              navContext.push('/sync');
            },
            child: const Text('Přejít na synchronizaci'),
          ),
        ],
      ),
    );
    _dialogShown = false;
  }
}
