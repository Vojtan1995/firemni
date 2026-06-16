import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

/// „Moje aktivita" – posledních pár vlastních akcí uživatele (z /api/logs/my-activity).
/// Záznamy s vlastní ucpávkou jsou prokliknutelné na detail.
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
          (res.data as List).cast<Map<String, dynamic>>().take(10).toList());
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

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Moje aktivita', style: SectionHeaderStyle.h3),
        ...items.map((item) {
          final entity = item['entity'] as Map<String, dynamic>?;
          final ts = item['timestamp'] is String
              ? DateTime.tryParse(item['timestamp'] as String)?.toLocal()
              : null;
          final when = ts != null ? DateFormat('d.M. HH:mm').format(ts) : '';
          final tappable = entity != null && entity['type'] == 'seal';
          return AppCard(
            title: item['title'] as String? ?? '',
            subtitle: when.isEmpty ? null : when,
            showChevron: tappable,
            onTap: tappable ? () => _openEntity(entity) : null,
          );
        }),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
