import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/app_top_actions.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).get('/api/notifications');
      if (!mounted) return;
      setState(() {
        _items = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
    }
  }

  void _refreshBadge() {
    ref.invalidate(unreadNotificationsCountProvider);
  }

  Future<void> _markRead(String id) async {
    final index = _items.indexWhere((n) => n['id'] == id);
    if (index < 0) return;
    setState(() {
      _items[index] = {
        ..._items[index],
        'readAt': DateTime.now().toUtc().toIso8601String(),
      };
    });
    try {
      await ref.read(dioProvider).patch('/api/notifications/$id/read');
      _refreshBadge();
    } catch (_) {
      await _load();
    }
  }

  Future<void> _markAllRead() async {
    final now = DateTime.now().toUtc().toIso8601String();
    setState(() {
      _items = _items
          .map((n) => n['readAt'] == null ? {...n, 'readAt': now} : n)
          .toList();
    });
    try {
      await ref.read(dioProvider).patch('/api/notifications/read-all');
      _refreshBadge();
    } catch (_) {
      await _load();
    }
  }

  void _openEntity(Map<String, dynamic> n) {
    final entityType = n['entityType'] as String?;
    final entityId = n['entityId'] as String?;
    if (entityType == 'worksheet' && entityId != null) {
      context.push('/worksheets/$entityId');
    } else if (entityType == 'seal' && entityId != null) {
      context.push('/seal/$entityId');
    }
  }

  bool get _hasUnread => _items.any((n) => n['readAt'] == null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Oznámení'),
        actions: [
          if (_hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Označit vše jako přečtené'),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Žádná oznámení'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final n = _items[i];
                    final unread = n['readAt'] == null;
                    final id = n['id'] as String;
                    return ListTile(
                      leading: Icon(
                        unread
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        color: unread
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                      title: Text(
                        n['title'] as String? ?? '',
                        style: TextStyle(
                          fontWeight:
                              unread ? FontWeight.w600 : FontWeight.normal,
                          color: unread ? null : AppColors.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        n['body'] as String? ?? '',
                        style: TextStyle(
                          color: unread ? null : AppColors.textSecondary,
                        ),
                      ),
                      onTap: () => _openEntity(n),
                      trailing: Tooltip(
                        message: 'Zobrazeno',
                        child: Checkbox(
                          value: !unread,
                          onChanged: unread ? (_) => _markRead(id) : null,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
