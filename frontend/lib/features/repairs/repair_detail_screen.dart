import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../widgets/app_top_actions.dart';
import '../../widgets/widgets.dart';
import '../seals/seal_constants.dart';

const _fieldLabels = <String, String>{
  'trade': 'Řemeslo',
  'system': 'Systém',
  'construction': 'Konstrukce',
  'location': 'Umístění',
  'fireRating': 'Požární odolnost',
  'openingLengthMm': 'Délka otvoru',
  'openingWidthMm': 'Šířka otvoru',
  'entries': 'Prostupy',
};

String _valueOr(dynamic v) {
  if (v == null) return 'Neuvedeno';
  final s = v.toString().trim();
  return s.isEmpty ? 'Neuvedeno' : s;
}

String _formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Detail opravy — formulář opravy, povinná poznámka, odkaz na původní
/// ucpávku a přehled toho, co se oproti snapshotu změnilo.
class RepairDetailScreen extends ConsumerStatefulWidget {
  const RepairDetailScreen({super.key, required this.repairId});
  final String repairId;

  @override
  ConsumerState<RepairDetailScreen> createState() =>
      _RepairDetailScreenState();
}

class _RepairDetailScreenState extends ConsumerState<RepairDetailScreen> {
  Map<String, dynamic>? _repair;
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
      final res = await ref
          .read(dioProvider)
          .get('/api/repairs/${widget.repairId}');
      if (!mounted) return;
      setState(() {
        _repair = (res.data as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e, fallback: 'Opravu se nepodařilo načíst');
        _loading = false;
      });
    }
  }

  Widget _entriesList(List<dynamic> entries) {
    if (entries.isEmpty) return const Text('Neuvedeno');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        final materials = (m['materials'] as List? ?? [])
            .map((x) => x.toString())
            .join(', ');
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${m['entryType']} – ${m['dimension']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('${m['quantity']} ks, ${m['insulation']}'),
                if (materials.isNotEmpty) Text('Materiály: $materials'),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _changesSection(
    Map<String, dynamic> original,
    Map<String, dynamic> repaired,
    List<dynamic> changedFields,
  ) {
    if (changedFields.isEmpty) {
      return const Text('Žádné rozdíly oproti původní ucpávce.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: changedFields.map((f) {
        final field = f.toString();
        final label = _fieldLabels[field] ?? field;
        if (field == 'entries') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('$label: upraveny'),
          );
        }
        final from = field == 'trade'
            ? sealTradeLabel(original[field] as String?)
            : _valueOr(original[field]);
        final to = field == 'trade'
            ? sealTradeLabel(repaired[field] as String?)
            : _valueOr(repaired[field]);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('$label: $from → $to'),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _repair == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail opravy')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Oprava nenalezena', textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                TextButton(onPressed: _load, child: const Text('Zkusit znovu')),
              ],
            ),
          ),
        ),
      );
    }

    final repair = _repair!;
    final job = repair['job'] as Map<String, dynamic>?;
    final floor = repair['floor'] as Map<String, dynamic>?;
    final author = repair['createdBy'] as Map<String, dynamic>?;
    final repaired = (repair['repairData'] as Map).cast<String, dynamic>();
    final original = (repair['originalSnapshot'] as Map).cast<String, dynamic>();
    final changedFields = (repair['changedFields'] as List?) ?? const [];
    final entries = (repaired['entries'] as List?) ?? const [];
    final sealId = repair['sealId'] as String;

    return Scaffold(
      appBar: AppBar(
        title: Text('Oprava ucpávky #${repair['sealNumber']}'),
        actions: const [AppTopActions()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            showChevron: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ucpávka #${repair['sealNumber']}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(_valueOr(job?['name'] ?? job?['projectNumber'])),
                Text(_valueOr(floor?['name'])),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppSecondaryButton(
              label: 'Otevřít původní ucpávku',
              icon: Icons.search,
              onPressed: () => context.push('/seal/$sealId'),
            ),
          ),
          _Section(
            title: 'Poznámka k opravě',
            children: [Text(_valueOr(repair['note']))],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            title: 'Co se změnilo',
            children: [_changesSection(original, repaired, changedFields)],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            title: 'Opravené údaje',
            children: [
              _Kv(label: 'Řemeslo', value: sealTradeLabel(repaired['trade'] as String?)),
              _Kv(label: 'Systém', value: _valueOr(repaired['system'])),
              _Kv(label: 'Konstrukce', value: _valueOr(repaired['construction'])),
              _Kv(label: 'Umístění', value: _valueOr(repaired['location'])),
              _Kv(label: 'Požární odolnost', value: _valueOr(repaired['fireRating'])),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(title: 'Prostupy / materiály', children: [_entriesList(entries)]),
          const SizedBox(height: AppSpacing.md),
          _Section(
            title: 'Evidence',
            children: [
              _Kv(label: 'Opravil', value: _valueOr(author?['displayName'])),
              _Kv(label: 'Datum opravy', value: _formatDate(repair['createdAt'] as String?)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      showChevron: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, style: SectionHeaderStyle.h3),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
