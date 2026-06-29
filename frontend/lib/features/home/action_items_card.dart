import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../core/parse_utils.dart';
import '../../widgets/widgets.dart';
import '../worksheets/worksheet_navigation.dart';

String actionSearchRoute(String filter) => '/search?filters=$filter';
String get jobsWithoutActivityRoute => '/jobs-admin?filter=without_activity';

/// Karta „Vyžaduje akci" na domovské obrazovce. Načte `/api/stats/overview` a podle
/// role zobrazí jen ty položky, které mají nenulový počet a vedou na konkrétní akci.
/// Když není co řešit (nebo nastane chyba), nezobrazí se nic.
class ActionItemsCard extends ConsumerStatefulWidget {
  const ActionItemsCard({super.key, required this.role});

  final String role;

  @override
  ConsumerState<ActionItemsCard> createState() => _ActionItemsCardState();
}

class _ActionItem {
  const _ActionItem({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _ActionItemsCardState extends ConsumerState<ActionItemsCard> {
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get('/api/stats/overview');
      if (!mounted) return;
      setState(() => _stats = Map<String, dynamic>.from(res.data as Map));
    } catch (_) {
      // Tichý fallback – karta se prostě nezobrazí.
    }
  }

  int _n(String key) => parseNum(_stats?[key]).toInt();

  List<_ActionItem> _itemsForRole() {
    final s = _stats;
    if (s == null) return const [];
    final role = widget.role;

    if (role == 'worker') {
      return [
        _ActionItem(
          label: 'Bez fotky',
          count: _n('missingPhotos'),
          icon: Icons.photo_camera_outlined,
          color: AppColors.warning,
          onTap: () => context.push(actionSearchRoute('no_photo')),
        ),
      ].where((i) => i.count > 0).toList();
    }

    // vedeni / admin
    final jobsWithoutActivity = s['jobsWithoutActivity'];
    final jobsWithoutActivityCount =
        jobsWithoutActivity is List ? jobsWithoutActivity.length : 0;
    return [
      _ActionItem(
        label: 'Nezkontrolované ucpávky',
        count: _n('uncheckedSeals'),
        icon: Icons.fact_check_outlined,
        color: AppColors.warning,
        onTap: () => context.push(actionSearchRoute('status_draft')),
      ),
      _ActionItem(
        label: 'Připraveno k fakturaci',
        count: _n('readyForInvoice'),
        icon: Icons.request_quote_outlined,
        color: AppColors.accent,
        onTap: () => goToSoupisy(context, status: 'ready_for_invoice'),
      ),
      _ActionItem(
        label: 'Zakázky bez aktivity',
        count: jobsWithoutActivityCount,
        icon: Icons.warning_amber_outlined,
        color: AppColors.warning,
        onTap: () => context.push(jobsWithoutActivityRoute),
      ),
    ].where((i) => i.count > 0).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsForRole();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
            title: 'Vyžaduje akci', style: SectionHeaderStyle.h3),
        ...items.map(
          (item) => AppCard(
            leading: AppIconBox(
              icon: item.icon,
              backgroundColor: item.color.withValues(alpha: 0.12),
              color: item.color,
            ),
            title: item.label,
            onTap: item.onTap,
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.15),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                '${item.count}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: item.color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
