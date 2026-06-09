import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

class ManagementHomeScreen extends StatelessWidget {
  const ManagementHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Správa')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _MenuTile(
            icon: Icons.search,
            title: 'Vyhledávání',
            onTap: () => context.push('/search'),
          ),
          _MenuTile(
            icon: Icons.apartment,
            title: 'Stavby a patra',
            onTap: () => context.push('/jobs-admin'),
          ),
          _MenuTile(
            icon: Icons.people,
            title: 'Uživatelé',
            onTap: () => context.push('/users-admin'),
          ),
          _MenuTile(
            icon: Icons.file_download_outlined,
            title: 'Exporty',
            onTap: () => context.push('/reports'),
          ),
          _MenuTile(
            icon: Icons.history,
            title: 'Logy',
            onTap: () => context.push('/logs'),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      leading: AppIconBox(icon: icon),
      title: title,
      onTap: onTap,
    );
  }
}
