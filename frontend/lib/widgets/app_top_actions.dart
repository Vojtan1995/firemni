import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api/api_client.dart';
import '../core/design_tokens.dart';
import '../database/database_provider.dart';
import '../features/auth/auth_provider.dart';
import '../features/sync/sync_retry.dart';

final unreadNotificationsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final res = await ref.read(dioProvider).get('/api/notifications/unread-count');
    return (res.data as Map)['count'] as int? ?? 0;
  } catch (_) {
    return 0;
  }
});

final appBarSyncPendingProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = ref.read(databaseProvider);
  final userId = ref.read(currentUserIdProvider);
  return countDueSyncItems(db, DateTime.now(), userId: userId);
});

final unreadMessagesCountProvider = FutureProvider<int>((ref) async {
  try {
    final res = await ref.read(dioProvider).get('/api/messages/unread-count');
    return (res.data as Map)['count'] as int? ?? 0;
  } catch (_) {
    return 0;
  }
});

class AppTopActions extends ConsumerWidget {
  const AppTopActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(appBarSyncPendingProvider).valueOrNull ?? 0;
    final notifications = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    final messages = ref.watch(unreadMessagesCountProvider).valueOrNull ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BadgeIcon(
          icon: Icons.sync,
          count: pending,
          tooltip: pending > 0 ? 'Čeká na sync ($pending)' : 'Synchronizace',
          color: pending > 0 ? AppColors.warning : null,
          onPressed: () => context.push('/sync'),
        ),
        _BadgeIcon(
          icon: Icons.notifications_outlined,
          count: notifications,
          tooltip: 'Oznámení',
          onPressed: () => context.push('/notifications'),
        ),
        _BadgeIcon(
          icon: Icons.mail_outline,
          count: messages,
          tooltip: 'Zprávy',
          onPressed: () => context.push('/messages'),
        ),
      ],
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.icon,
    required this.count,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final int count;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(icon, color: color),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(color: Colors.white, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
