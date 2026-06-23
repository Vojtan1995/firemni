import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../widgets/widgets.dart';
import '../seals/chip_selector.dart';
import '../seals/multi_chip_selector.dart';
import '../seals/seal_constants.dart';
import 'repair_entry_draft.dart';

/// Formulář opravy — předvyplněný z původní ucpávky. Uložení vytváří nový
/// `SealRepair` záznam, původní ucpávka se nikdy nezapisuje (online-only, v1
/// bez fotek — viz plán modulu Oprava).
class RepairFormScreen extends ConsumerStatefulWidget {
  const RepairFormScreen({super.key, required this.sealId});
  final String sealId;

  @override
  ConsumerState<RepairFormScreen> createState() => _RepairFormScreenState();
}

class _RepairFormScreenState extends ConsumerState<RepairFormScreen> {
  final _noteCtrl = TextEditingController();
  String? _trade;
  String? _system;
  String? _construction;
  String? _location;
  String? _fireRating;
  final _entries = <RepairEntryDraftData>[];
  bool _loading = true;
  bool _saving = false;
  String? _sealNumber;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res =
          await ref.read(dioProvider).get('/api/seals/${widget.sealId}');
      final seal = (res.data as Map).cast<String, dynamic>();
      _trade = seal['trade'] as String?;
      _system = seal['system'] as String?;
      _construction = seal['construction'] as String?;
      _location = seal['location'] as String?;
      _fireRating = seal['fireRating'] as String?;
      _sealNumber = seal['sealNumber'] as String?;
      final entries = (seal['entries'] as List? ?? []);
      _entries
        ..clear()
        ..addAll(entries.map(
          (e) => RepairEntryDraftData.fromMap((e as Map).cast<String, dynamic>()),
        ));
      if (_entries.isEmpty) _entries.add(RepairEntryDraftData());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              apiErrorMessage(e, fallback: 'Ucpávku se nepodařilo načíst'),
            ),
          ),
        );
        context.pop();
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poznámka k opravě je povinná')),
      );
      return;
    }
    if (_trade == null ||
        _system == null ||
        _construction == null ||
        _location == null ||
        _fireRating == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vyplňte povinná pole')),
      );
      return;
    }
    if (_entries.any((e) =>
        e.entryType.isEmpty ||
        e.dimension.trim().isEmpty ||
        e.insulation.isEmpty ||
        e.materials.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doplňte všechna pole u prostupů')),
      );
      return;
    }
    if (_entries.any((e) => e.entryType == 'OCEL' && e.steelInsulated == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('U typu Ocel vyberte Doizolováno (Ano/Ne)')));
      return;
    }
    if (_entries.any(
        (e) => e.entryType == 'EL.V.' && e.electroInstallationType == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'U typu Elektro vyberte typ instalace (Svazek/Husí krk/Žlab/Kabel)')));
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await ref.read(dioProvider).post('/api/repairs', data: {
        'sealId': widget.sealId,
        'note': _noteCtrl.text.trim(),
        'trade': _trade,
        'system': _system,
        'construction': _construction,
        'location': _location,
        'fireRating': _fireRating,
        'entries': _entries.map((e) => e.toPayload()).toList(),
      });
      final repairId = (res.data as Map)['id'] as String;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oprava uložena')),
      );
      context.go('/repairs/$repairId');
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(apiErrorMessage(e, fallback: 'Uložení opravy selhalo')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Oprava ucpávky')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _sealNumber != null
              ? 'Oprava ucpávky #$_sealNumber'
              : 'Oprava ucpávky',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Co bylo opraveno',
              style: SectionHeaderStyle.h3,
            ),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Poznámka k opravě *',
                hintText: 'Popište, co bylo opraveno',
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              title: 'Technické údaje',
              style: SectionHeaderStyle.h3,
            ),
            ChipSelector(
              label: 'Řemeslo *',
              options: sealTrades,
              selected: _trade,
              labelFor: sealTradeLabel,
              onSelected: (v) => setState(() => _trade = v),
            ),
            const SizedBox(height: 12),
            ChipSelector(
              label: 'Systém *',
              options: sealSystems,
              selected: _system,
              onSelected: (v) => setState(() => _system = v),
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              title: 'Prostupy',
              style: SectionHeaderStyle.h3,
            ),
            ..._entries.asMap().entries.map(
                  (i) => _RepairEntryEditor(
                    index: i.key,
                    entry: i.value,
                    system: _system,
                    canRemove: _entries.length > 1,
                    onRemove: () => setState(() => _entries.removeAt(i.key)),
                    onChanged: () => setState(() {}),
                  ),
                ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _entries.add(RepairEntryDraftData())),
              icon: const Icon(Icons.add),
              label: const Text('Přidat prostup'),
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              title: 'Umístění',
              style: SectionHeaderStyle.h3,
            ),
            ChipSelector(
              label: 'Konstrukce *',
              options: constructions,
              selected: _construction,
              onSelected: (v) => setState(() => _construction = v),
            ),
            const SizedBox(height: 12),
            ChipSelector(
              label: 'Umístění *',
              options: locations,
              selected: _location,
              onSelected: (v) => setState(() => _location = v),
            ),
            const SizedBox(height: 12),
            ChipSelector(
              label: 'Požární odolnost *',
              options: fireRatings,
              selected: _fireRating,
              onSelected: (v) => setState(() => _fireRating = v),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Uložit opravu'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepairEntryEditor extends StatefulWidget {
  const _RepairEntryEditor({
    required this.index,
    required this.entry,
    required this.system,
    required this.onChanged,
    this.canRemove = false,
    this.onRemove,
  });

  final int index;
  final RepairEntryDraftData entry;
  final String? system;
  final VoidCallback onChanged;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  State<_RepairEntryEditor> createState() => _RepairEntryEditorState();
}

class _RepairEntryEditorState extends State<_RepairEntryEditor> {
  late final TextEditingController _lengthCtrl;
  late final TextEditingController _widthCtrl;

  RepairEntryDraftData get entry => widget.entry;

  @override
  void initState() {
    super.initState();
    _lengthCtrl = TextEditingController(text: entry.itemLengthMmText);
    _widthCtrl = TextEditingController(text: entry.itemWidthMmText);
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    super.dispose();
  }

  void _syncDims() {
    entry.itemLengthMmText = _lengthCtrl.text;
    entry.itemWidthMmText = _widthCtrl.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final materialOptions = widget.system != null
        ? (systemMaterials[widget.system] ?? ['Jiný'])
        : const ['Jiný'];
    final presets = entry.entryType.isEmpty
        ? const <String>[]
        : dimensionPresetsForEntry(entry.entryType, entry.insulation);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Prostup ${widget.index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    tooltip: 'Odebrat prostup',
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            ChipSelector(
              label: 'Typ *',
              options: entryTypes,
              selected: entry.entryType.isEmpty ? null : entry.entryType,
              onSelected: (v) {
                setState(() {
                  entry.entryType = v;
                  if (v != 'OCEL') entry.steelInsulated = null;
                  if (v != 'EL.V.') entry.electroInstallationType = null;
                });
                widget.onChanged();
              },
            ),
            if (entry.entryType == 'OCEL') ...[
              const SizedBox(height: 8),
              ChipSelector(
                label: 'Doizolováno *',
                options: const ['Ano', 'Ne'],
                selected: entry.steelInsulated == null
                    ? null
                    : (entry.steelInsulated! ? 'Ano' : 'Ne'),
                onSelected: (v) {
                  setState(() => entry.steelInsulated = v == 'Ano');
                  widget.onChanged();
                },
              ),
            ],
            if (entry.entryType == 'EL.V.') ...[
              const SizedBox(height: 8),
              ChipSelector(
                label: 'Typ elektro instalace *',
                options: electroInstallationTypes,
                selected: entry.electroInstallationType,
                onSelected: (v) {
                  setState(() => entry.electroInstallationType = v);
                  widget.onChanged();
                },
              ),
            ],
            const SizedBox(height: 8),
            ChipSelector(
              label: 'Izolace *',
              options: insulations,
              selected: entry.insulation.isEmpty ? null : entry.insulation,
              onSelected: (v) {
                setState(() => entry.insulation = v);
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
            ChipSelector(
              label: 'Rozměr *',
              options: presets,
              selected: entry.dimension.isEmpty ? null : entry.dimension,
              onSelected: (v) {
                setState(() => entry.dimension = v);
                widget.onChanged();
              },
              allowCustom: true,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lengthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Délka (mm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _syncDims(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _widthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Šířka (mm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _syncDims(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MultiChipSelector(
              label: 'Materiály *',
              options: materialOptions,
              selected: entry.materials,
              allowCustom: true,
              onChanged: (v) {
                setState(() => entry.materials = v);
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Kusy: '),
                IconButton(
                  onPressed: entry.quantity > 1
                      ? () {
                          setState(() => entry.quantity--);
                          widget.onChanged();
                        }
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('${entry.quantity}'),
                IconButton(
                  onPressed: () {
                    setState(() => entry.quantity++);
                    widget.onChanged();
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
