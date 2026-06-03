import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';

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
  final _errors = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
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
        dio.get('/api/logs/errors'),
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
      _errors
        ..clear()
        ..addAll((results[3].data as List).cast<Map<String, dynamic>>());
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
          tabs: const [
            Tab(text: 'Aktivita'),
            Tab(text: 'Změny'),
            Tab(text: 'Přihlášení'),
            Tab(text: 'Chyby'),
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
                _errorsList(),
              ],
            ),
    );
  }

  Widget _activityList() {
    if (_activity.isEmpty) return const Center(child: Text('Žádné záznamy'));
    return ListView.builder(
      itemCount: _activity.length,
      itemBuilder: (_, i) {
        final l = _activity[i];
        final user = l['user'] as Map<String, dynamic>?;
        return ListTile(
          title: Text('${l['action']} – ${l['entityType'] ?? ''}'),
          subtitle:
              Text('${user?['displayName'] ?? ''} | ${l['createdAt']}'),
        );
      },
    );
  }

  Widget _changesList() {
    if (_changes.isEmpty) return const Center(child: Text('Žádné záznamy'));
    return ListView.builder(
      itemCount: _changes.length,
      itemBuilder: (_, i) {
        final l = _changes[i];
        final user = l['user'] as Map<String, dynamic>?;
        return ListTile(
          title: Text('${l['fieldName'] ?? l['entityType']}'),
          subtitle: Text(
            '${user?['displayName'] ?? ''}: ${l['oldValue']} → ${l['newValue']}',
          ),
        );
      },
    );
  }

  Widget _loginList() {
    if (_login.isEmpty) return const Center(child: Text('Žádné záznamy'));
    return ListView.builder(
      itemCount: _login.length,
      itemBuilder: (_, i) {
        final l = _login[i];
        final user = l['user'] as Map<String, dynamic>?;
        return ListTile(
          title: Text(l['success'] == true ? 'Úspěch' : 'Neúspěch'),
          subtitle: Text(
            '${user?['displayName'] ?? l['username'] ?? ''} | ${l['createdAt']}',
          ),
        );
      },
    );
  }

  Widget _errorsList() {
    if (_errors.isEmpty) return const Center(child: Text('Žádné záznamy'));
    return ListView.builder(
      itemCount: _errors.length,
      itemBuilder: (_, i) {
        final l = _errors[i];
        return ListTile(
          title: Text(l['message'] as String? ?? 'Chyba'),
          subtitle: Text('${l['path'] ?? ''} | ${l['createdAt']}'),
        );
      },
    );
  }
}
