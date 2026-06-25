import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

/// Pořadí podkategorií v UI (česky, bez syrových názvů akcí).
const _categoryOrder = [
  'Vytvořené',
  'Stav',
  'Úpravy',
  'Přesuny',
  'Fotky a výkresy',
  'Smazání a obnova',
  'Ceník',
  'Ostatní',
];

/// „Moje aktivita" – posledních pár vlastních akcí uživatele (z /api/logs/my-activity),
/// rozdělených do podkategorií podle druhu úkonu. Záznamy s vlastní ucpávkou jsou
/// prokliknutelné na detail.
class ProfileActivitySection extends ConsumerStatefulWidget {
  const ProfileActivitySection({super.key});

  @override
  ConsumerState<ProfileActivitySection> createState() =>
      _ProfileActivitySectionState();
}

class _ProfileActivitySectionState
    extends ConsumerState<ProfileActivitySection> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get('/api/logs/my-activity');
      if (!mounted) return;
      setState(() => _items =
          (res.data as List).cast<Map<String, dynamic>>().take(50).toList());
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  void _openEntity(Map<String, dynamic>? entity) {
    if (entity == null) return;
    final id = entity['id'] as String?;
    if (id == null || id.isEmpty) return;
    if (entity['type'] == 'seal') context.push('/seal/$id');
  }

  Widget _activityRow(Map<String, dynamic> item) {
    final entity = item['entity'] as Map<String, dynamic>?;
    final ts = item['timestamp'] is String
        ? DateTime.tryParse(item['timestamp'] as String)?.toLocal()
        : null;
    final when = ts != null ? DateFormat('d.M. HH:mm').format(ts) : '';
    final tappable = entity != null && entity['type'] == 'seal';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        title: item['title'] as String? ?? '',
        subtitle: when.isEmpty ? null : when,
        showChevron: tappable,
        onTap: tappable ? () => _openEntity(entity) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final category = item['category'] as String? ?? 'Ostatní';
      byCategory.putIfAbsent(category, () => []).add(item);
    }
    final categories = byCategory.keys.toList()
      ..sort(
        (a, b) =>
            _categoryOrder.indexOf(a).compareTo(_categoryOrder.indexOf(b)),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            title: const Text(
              'Moje aktivita',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${items.length} záznamů'),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            children: [
              for (final category in categories)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '$category (${byCategory[category]!.length})',
                  ),
                  initiallyExpanded: categories.length == 1,
                  children: byCategory[category]!.map(_activityRow).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
