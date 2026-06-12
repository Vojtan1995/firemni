import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/design_tokens.dart';
import '../../core/permissions.dart';
import '../../widgets/app_top_actions.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../jobs/resume_work_context_card.dart';

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
          const AppTopActions(),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (auth.isSuperAdmin)
            AppCard(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderColor: AppColors.warning.withValues(alpha: 0.4),
              showChevron: false,
              child: Text(
                'Super Admin — nouzový účet. Běžnou správu provádí role Vedení.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.warning,
                    ),
              ),
            ),
          AppCard(
            leading: AppIconBox(
              icon: Icons.person,
              backgroundColor: AppColors.bgSecondary,
              color: AppColors.textPrimary,
            ),
            title: user['displayName'] as String? ?? '',
            subtitle: AppPermissions.roleLabel(role),
            onTap: () => context.push('/profile'),
          ),
          const SizedBox(height: AppSpacing.sm),
          const ResumeWorkContextCard(),
          _MenuTile(
            icon: Icons.work,
            title: 'Zakázky',
            onTap: () => context.push('/jobs'),
          ),
          if (auth.canAccessReports || auth.canManageWorksheets)
            _MenuTile(
              icon: Icons.description,
              title: auth.isWorker ? 'Moje soupisy' : 'Soupisy práce',
              onTap: () => context.push('/soupisy'),
            ),
          if (auth.canViewStats && !auth.isWorker)
            _MenuTile(
              icon: Icons.analytics_outlined,
              title: auth.isWorker
                  ? 'Moje statistiky'
                  : auth.isUcetni
                      ? 'Statistiky fakturace'
                      : 'Dashboard',
              onTap: () => context.push('/stats'),
            ),
          if (auth.canViewPriceList)
            _MenuTile(
              icon: Icons.price_check,
              title: 'Ceník',
              onTap: () => context.push('/price-list'),
            ),
          if (auth.canManageJobs)
            _MenuTile(
              icon: Icons.admin_panel_settings,
              title: 'Správa staveb',
              onTap: () => context.push('/jobs-admin'),
            ),
          if (auth.canManageUsers)
            _MenuTile(
              icon: Icons.people,
              title: 'Uživatelé',
              onTap: () => context.push('/users-admin'),
            ),
          if (auth.canManageJobs)
            _MenuTile(
              icon: Icons.history,
              title: 'Logy',
              onTap: () => context.push('/logs'),
            ),
          if (auth.canAccessTrash)
            _MenuTile(
              icon: Icons.delete_outline,
              title: 'Koš / Smazané položky',
              onTap: () => context.push('/trash'),
            ),
          _MenuTile(
            icon: Icons.help_outline,
            title: 'Nápověda',
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Ucpávky',
                applicationVersion: '1.0.0',
              );
            },
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
