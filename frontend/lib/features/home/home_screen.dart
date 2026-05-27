import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider)!;
    final auth = ref.read(authServiceProvider);
    final role = user['role'] as String;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hlavní menu'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () async {
            await auth.logout();
            if (context.mounted) context.go('/login');
          }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user['displayName'] as String? ?? ''),
            subtitle: Text(role),
          ),
          const Divider(),
          _MenuTile(icon: Icons.construction, title: 'Stavba', onTap: () => context.push('/job-number')),
          _MenuTile(icon: Icons.sync, title: 'Synchronizace', onTap: () => context.push('/sync')),
          if (auth.isManagement) ...[
            _MenuTile(icon: Icons.admin_panel_settings, title: 'Správa staveb', onTap: () => context.push('/jobs-admin')),
            _MenuTile(icon: Icons.assignment, title: 'Soupis prací / Export', onTap: () => context.push('/reports')),
            _MenuTile(icon: Icons.history, title: 'Logy', onTap: () => context.push('/logs')),
          ],
          _MenuTile(icon: Icons.help_outline, title: 'Nápověda', onTap: () {
            showAboutDialog(context: context, applicationName: 'Ucpávky', applicationVersion: '1.0.0');
          }),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
