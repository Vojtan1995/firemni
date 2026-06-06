import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

class PriceListScreen extends ConsumerStatefulWidget {
  const PriceListScreen({super.key});

  @override
  ConsumerState<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends ConsumerState<PriceListScreen> {
  Map<String, dynamic>? _priceList;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(dioProvider).get('/api/price-list');
      setState(() {
        _priceList = (res.data as Map).cast<String, dynamic>();
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data is Map
            ? (e.response!.data as Map)['message']?.toString()
            : 'Nepodařilo se načíst ceník';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatPrice(dynamic value) {
    if (value == null) return '—';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString());
    if (n == null) return '—';
    return '${n.toStringAsFixed(0)} Kč';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ceník'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(message: _error!, icon: Icons.error_outline)
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final list = _priceList!;
    final version = list['version'] as String? ?? '—';
    final items = (list['items'] as List? ?? []).cast<Map<String, dynamic>>();

    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final cat = item['category'] as String? ?? 'Ostatní';
      byCategory.putIfAbsent(cat, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          showChevron: false,
          leading: const AppIconBox(icon: Icons.price_check),
          title: 'Aktivní ceník',
          subtitle: '$version (jen prohlížení)',
        ),
        const SizedBox(height: AppSpacing.sm),
        ...byCategory.entries.map((entry) {
          return AppCard(
            showChevron: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                ...entry.value.map((item) {
                  final unit = item['unit'] as String? ?? 'kus';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['sizeLabel'] as String? ?? '',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        Text(
                          '${_formatPrice(item['priceWithMaterial'])} / $unit',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ],
    );
  }
}
