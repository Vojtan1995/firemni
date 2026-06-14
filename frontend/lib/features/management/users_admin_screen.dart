import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';

String roleLabel(String role) {
  switch (role) {
    case 'worker':
      return 'Pracovník';
    case 'vedeni':
      return 'Vedení';
    case 'ucetni':
      return 'Administrativa';
    case 'admin':
      return 'Super Admin';
    default:
      return role;
  }
}

class UsersAdminScreen extends ConsumerStatefulWidget {
  const UsersAdminScreen({super.key});

  @override
  ConsumerState<UsersAdminScreen> createState() => _UsersAdminScreenState();
}

class _UsersAdminScreenState extends ConsumerState<UsersAdminScreen> {
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isAdmin => ref.read(authServiceProvider).isAdmin;

  String? get _currentUserId => ref.read(authUserProvider)?['id'] as String?;

  List<String> get _assignableRoles => _isAdmin
      ? ['worker', 'vedeni', 'ucetni', 'admin']
      : ['worker', 'vedeni', 'ucetni'];

  void _showError(Object e) {
    String msg = e.toString();
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        msg = data['error'] as String;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get('/api/users');
      setState(() => _users = (res.data as List).cast<Map<String, dynamic>>());
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _createUser() async {
    final userCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    var role = _assignableRoles.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Nový uživatel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: userCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Přihlašovací jméno'),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Zobrazované jméno'),
                ),
                TextField(
                  controller: pinCtrl,
                  decoration:
                      const InputDecoration(labelText: 'PIN (6–8 znaků)'),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: _assignableRoles
                      .map((r) =>
                          DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialog(() => role = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Zrušit')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Vytvořit')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).post('/api/users', data: {
        'username': userCtrl.text.trim(),
        'displayName': nameCtrl.text.trim(),
        'pin': pinCtrl.text,
        'role': role,
      });
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<bool> _confirmDeactivate(String username) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Deaktivovat účet'),
        content: Text(
            'Opravdu chcete deaktivovat účet „$username“? Uživatel se nebude moci přihlásit.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Zrušit')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Deaktivovat'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    if (!_isAdmin && user['role'] == 'admin') {
      _showError('Vedení nemůže upravovat administrátorské účty');
      return;
    }
    final nameCtrl =
        TextEditingController(text: user['displayName'] as String? ?? '');
    final pinCtrl = TextEditingController();
    var role = user['role'] as String;
    var isActive = user['isActive'] != false;
    final roles = _assignableRoles.contains(role)
        ? _assignableRoles
        : [role, ..._assignableRoles];
    final userId = user['id'] as String;
    final username = user['username'] as String;
    final isSelf = userId == _currentUserId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text('Upravit $username'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Zobrazované jméno'),
                ),
                TextField(
                  controller: pinCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Nový PIN (volitelně)'),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                ),
                DropdownButtonFormField<String>(
                  initialValue: roles.contains(role) ? role : roles.first,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: roles
                      .map((r) =>
                          DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialog(() => role = v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Účet aktivní'),
                  value: isActive,
                  onChanged:
                      isSelf ? null : (v) => setDialog(() => isActive = v),
                ),
                if (isActive && !isSelf) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await _confirmDeactivate(username);
                      if (confirmed) {
                        setDialog(() => isActive = false);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(c).colorScheme.error,
                      side: BorderSide(color: Theme.of(c).colorScheme.error),
                    ),
                    icon: const Icon(Icons.person_off),
                    label: const Text('Deaktivovat účet'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Zrušit')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Uložit')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final data = <String, dynamic>{
      'displayName': nameCtrl.text.trim(),
      'role': role,
      'isActive': isActive,
    };
    if (pinCtrl.text.isNotEmpty) data['pin'] = pinCtrl.text;

    try {
      await ref.read(dioProvider).patch('/api/users/$userId', data: data);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uživatelé')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createUser,
        tooltip: 'Nový uživatel',
        child: const Icon(Icons.person_add),
      ),
      body: _users.isEmpty
          ? const EmptyState(
              message: 'Žádní uživatelé',
              icon: Icons.people_outline,
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                final active = u['isActive'] != false;
                final role = u['role'] as String? ?? '';
                return AppCard(
                  leading: AppIconBox(
                    icon: active ? Icons.person : Icons.person_off,
                    backgroundColor: AppColors.bgSecondary,
                    color: active ? AppColors.textPrimary : AppColors.textMuted,
                  ),
                  title: u['displayName'] as String? ?? '',
                  subtitle: '${u['username']} · ${roleLabel(role)}',
                  trailing: active
                      ? null
                      : const StatusBadge(
                          status: 'inactive',
                          label: 'neaktivní',
                          compact: true,
                        ),
                  onTap: () => _editUser(u),
                );
              },
            ),
    );
  }
}
