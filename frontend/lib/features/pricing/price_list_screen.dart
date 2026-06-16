import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';

class _EditablePriceItem {
  _EditablePriceItem({
    this.id,
    required this.category,
    required this.sizeLabel,
    required this.unit,
    required this.priceWithMaterial,
    this.active = true,
    this.sortOrder = 0,
  });

  String? id;
  String category;
  String sizeLabel;
  String unit;
  double priceWithMaterial;
  bool active;
  int sortOrder;

  factory _EditablePriceItem.fromJson(Map<String, dynamic> json) {
    final price = json['priceWithMaterial'];
    final n = price is num
        ? price.toDouble()
        : double.tryParse(price?.toString() ?? '') ?? 0;
    return _EditablePriceItem(
      id: json['id'] as String?,
      category: json['category'] as String? ?? '',
      sizeLabel: json['sizeLabel'] as String? ?? '',
      unit: json['unit'] as String? ?? 'kus',
      priceWithMaterial: n,
      active: json['active'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toPublishJson() => {
        if (id != null) 'id': id,
        'category': category,
        'sizeLabel': sizeLabel,
        'unit': unit,
        'priceWithMaterial': priceWithMaterial,
        'priceWithoutMaterial': priceWithMaterial,
        'active': active,
        'sortOrder': sortOrder,
      };
}

class PriceListScreen extends ConsumerStatefulWidget {
  const PriceListScreen({super.key});

  @override
  ConsumerState<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends ConsumerState<PriceListScreen> {
  Map<String, dynamic>? _priceList;
  List<Map<String, dynamic>> _versions = [];
  List<_EditablePriceItem> _editableItems = [];
  bool _loading = true;
  bool _publishing = false;
  bool _dirty = false;
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
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/api/price-list'),
        dio.get('/api/price-list/versions'),
      ]);
      final list = (results[0].data as Map).cast<String, dynamic>();
      final versions =
          (results[1].data as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _priceList = list;
        _versions = versions;
        _editableItems = (list['items'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(_EditablePriceItem.fromJson)
            .toList();
        _dirty = false;
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

  Future<void> _publish() async {
    final activeItems = _editableItems.where((i) => i.active).toList();
    if (activeItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ceník musí mít alespoň jednu aktivní položku')),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      final res = await ref.read(dioProvider).post(
        '/api/price-list/publish',
        data: {
          'items': _editableItems.map((i) => i.toPublishJson()).toList(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nová verze ceníku ${(res.data as Map)['version']} uložena',
          ),
        ),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage(e, fallback: 'Uložení selhalo'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _showAddItemDialog() async {
    final categoryCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'kus');
    final priceCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nová položka'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(labelText: 'Kategorie'),
              ),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Popis / rozměr'),
              ),
              TextField(
                controller: unitCtrl,
                decoration: const InputDecoration(labelText: 'Jednotka'),
              ),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Cena s materiálem (Kč)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zrušit')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Přidat')),
        ],
      ),
    );

    if (ok != true) return;
    final price = double.tryParse(priceCtrl.text.trim());
    if (categoryCtrl.text.trim().isEmpty ||
        labelCtrl.text.trim().isEmpty ||
        price == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vyplňte kategorii, popis a cenu')),
      );
      return;
    }

    setState(() {
      _editableItems.add(
        _EditablePriceItem(
          category: categoryCtrl.text.trim(),
          sizeLabel: labelCtrl.text.trim(),
          unit: unitCtrl.text.trim().isEmpty ? 'kus' : unitCtrl.text.trim(),
          priceWithMaterial: price,
          sortOrder: _editableItems.length,
        ),
      );
      _dirty = true;
    });
  }

  Future<void> _showVersionDetail(String version) async {
    try {
      final res = await ref.read(dioProvider).get('/api/price-list/versions/$version');
      if (!mounted) return;
      final data = (res.data as Map).cast<String, dynamic>();
      final items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Ceník $version'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: items.map((item) {
                final price = item['priceWithMaterial'];
                return ListTile(
                  dense: true,
                  title: Text('${item['category']} — ${item['sizeLabel']}'),
                  subtitle: item['active'] == false
                      ? const Text('Neaktivní')
                      : null,
                  trailing: Text('$price Kč / ${item['unit']}'),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zavřít')),
          ],
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Načtení verze selhalo'))),
      );
    }
  }

  String _formatPrice(double value) => '${value.toStringAsFixed(0)} Kč';

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(authServiceProvider).canManagePriceList;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ceník'),
        actions: [
          if (canManage && _dirty)
            TextButton(
              onPressed: _publishing ? null : _publish,
              child: _publishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Uložit verzi'),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(message: _error!, icon: Icons.error_outline)
              : _buildContent(canManage),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _showAddItemDialog,
              icon: const Icon(Icons.add),
              label: const Text('Položka'),
            )
          : null,
    );
  }

  Widget _buildContent(bool canManage) {
    final list = _priceList!;
    final version = list['version'] as String? ?? '—';
    final inactiveVersions =
        _versions.where((v) => v['active'] != true).toList();

    final byCategory = <String, List<_EditablePriceItem>>{};
    for (final item in _editableItems.where((i) => i.active || canManage)) {
      if (!item.active && !canManage) continue;
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          showChevron: false,
          leading: const AppIconBox(icon: Icons.price_check),
          title: 'Aktivní ceník',
          subtitle: canManage
              ? '$version — úpravy se uloží jako nová verze'
              : '$version (jen prohlížení)',
        ),
        if (canManage && _dirty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Máte neuložené změny. Stará verze zůstane v historii.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        ...byCategory.entries.map((entry) {
          return AppCard(
            showChevron: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                ...entry.value.map((item) => _buildItemRow(item, canManage)),
              ],
            ),
          );
        }),
        if (inactiveVersions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Historie verzí', style: SectionHeaderStyle.h3),
          ...inactiveVersions.map((v) {
            final ver = v['version'] as String? ?? '';
            final from = v['validFrom'] as String?;
            return AppCard(
              title: ver,
              subtitle: from != null ? 'Platnost od $from' : null,
              trailing: Text('${v['itemCount'] ?? 0} položek'),
              onTap: () => _showVersionDetail(ver),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildItemRow(_EditablePriceItem item, bool canManage) {
    if (!canManage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(child: Text(item.sizeLabel)),
            Text(
              '${_formatPrice(item.priceWithMaterial)} / ${item.unit}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.sizeLabel),
                if (!item.active)
                  Text(
                    'Neaktivní',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 88,
            child: TextFormField(
              initialValue: item.priceWithMaterial.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                suffixText: 'Kč',
                isDense: true,
              ),
              onChanged: (v) {
                final n = double.tryParse(v);
                if (n != null) {
                  item.priceWithMaterial = n;
                  _dirty = true;
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(
              item.active ? Icons.visibility_off_outlined : Icons.undo,
              size: 20,
            ),
            tooltip: item.active ? 'Deaktivovat' : 'Obnovit',
            onPressed: () {
              setState(() {
                item.active = !item.active;
                _dirty = true;
              });
            },
          ),
        ],
      ),
    );
  }
}
