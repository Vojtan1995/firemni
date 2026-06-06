import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _activity = <Map<String, dynamic>>[];
  final _changes = <Map<String, dynamic>>[];
  final _login = <Map<String, dynamic>>[];
  final _sync = <Map<String, dynamic>>[];
  final _errors = <Map<String, dynamic>>[];
  final _photos = <Map<String, dynamic>>[];
  final _admin = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    try {
      final results = await Future.wait([
        dio.get('/api/logs/activity'),
        dio.get('/api/logs/changes'),
        dio.get('/api/logs/login'),
        dio.get('/api/logs/sync'),
        dio.get('/api/logs/errors'),
        dio.get('/api/logs/photos'),
        dio.get('/api/logs/admin'),
      ]);
      _activity
        ..clear()
        ..addAll((results[0].data as List).cast<Map<String, dynamic>>());
      _changes
        ..clear()
        ..addAll((results[1].data as List).cast<Map<String, dynamic>>());
      _login
        ..clear()
        ..addAll((results[2].data as List).cast<Map<String, dynamic>>());
      _sync
        ..clear()
        ..addAll((results[3].data as List).cast<Map<String, dynamic>>());
      _errors
        ..clear()
        ..addAll((results[4].data as List).cast<Map<String, dynamic>>());
      _photos
        ..clear()
        ..addAll((results[5].data as List).cast<Map<String, dynamic>>());
      _admin
        ..clear()
        ..addAll((results[6].data as List).cast<Map<String, dynamic>>());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logy'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: AppColors.border,
          labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          unselectedLabelStyle: Theme.of(context).textTheme.bodyMedium,
          tabs: const [
            Tab(text: 'Aktivita'),
            Tab(text: 'Změny'),
            Tab(text: 'Přihlášení'),
            Tab(text: 'Synchronizace'),
            Tab(text: 'Chyby'),
            Tab(text: 'Fotky'),
            Tab(text: 'Admin'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _activityList(),
                _changesList(),
                _loginList(),
                _syncList(),
                _errorsList(),
                _photosList(),
                _adminList(),
              ],
            ),
    );
  }

  Widget _logList({
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) titleFor,
    required String Function(Map<String, dynamic>) subtitleFor,
    IconData emptyIcon = Icons.inbox_outlined,
  }) {
    if (items.isEmpty) {
      return EmptyState(message: 'Žádné záznamy', icon: emptyIcon);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return AppCard(
          showChevron: false,
          title: titleFor(item),
          subtitle: subtitleFor(item),
        );
      },
    );
  }

  Widget _activityList() {
    return _logList(
      items: _activity,
      titleFor: (l) => '${l['action']} – ${l['entityType'] ?? ''}',
      subtitleFor: (l) {
        final user = l['user'] as Map<String, dynamic>?;
        return '${user?['displayName'] ?? ''} | ${l['createdAt']}';
      },
      emptyIcon: Icons.history,
    );
  }

  Widget _changesList() {
    return _logList(
      items: _changes,
      titleFor: (l) => '${l['fieldName'] ?? l['entityType']}',
      subtitleFor: (l) {
        final user = l['user'] as Map<String, dynamic>?;
        return '${user?['displayName'] ?? ''}: ${l['oldValue']} → ${l['newValue']}';
      },
      emptyIcon: Icons.edit_note,
    );
  }

  Widget _loginList() {
    return _logList(
      items: _login,
      titleFor: (l) => l['success'] == true ? 'Úspěch' : 'Neúspěch',
      subtitleFor: (l) {
        final user = l['user'] as Map<String, dynamic>?;
        return '${user?['displayName'] ?? l['username'] ?? ''} | ${l['createdAt']}';
      },
      emptyIcon: Icons.login,
    );
  }

  Widget _syncList() {
    return _logList(
      items: _sync,
      titleFor: (l) => '${l['operation']} – ${l['entityType']}',
      subtitleFor: (l) => 'device ${l['deviceId'] ?? ''} | ${l['createdAt']}',
      emptyIcon: Icons.sync,
    );
  }

  Widget _errorsList() {
    return _logList(
      items: _errors,
      titleFor: (l) => l['message'] as String? ?? 'Chyba',
      subtitleFor: (l) => '${l['path'] ?? ''} | ${l['createdAt']}',
      emptyIcon: Icons.error_outline,
    );
  }

  Widget _photosList() {
    return _logList(
      items: _photos,
      titleFor: (l) => l['action'] as String? ?? 'foto',
      subtitleFor: (l) {
        final user = l['user'] as Map<String, dynamic>?;
        return '${user?['displayName'] ?? ''} | seal ${l['entityId'] ?? ''} | ${l['createdAt']}';
      },
      emptyIcon: Icons.photo_camera_outlined,
    );
  }

  Widget _adminList() {
    return _logList(
      items: _admin,
      titleFor: (l) => l['action'] as String? ?? 'admin',
      subtitleFor: (l) {
        final user = l['user'] as Map<String, dynamic>?;
        return '${user?['displayName'] ?? ''} (${user?['role'] ?? ''}) | ${l['createdAt']}';
      },
      emptyIcon: Icons.admin_panel_settings_outlined,
    );
  }
}
