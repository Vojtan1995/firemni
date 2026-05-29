import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../sync/sync_service.dart';
import 'chip_selector.dart';
import 'multi_chip_selector.dart';
import 'seal_constants.dart';

final _sealNumberPattern = RegExp(r'^\d+$');

class SealFormScreen extends ConsumerStatefulWidget {
  const SealFormScreen({super.key, required this.jobId, required this.floorId});
  final String jobId;
  final String floorId;

  @override
  ConsumerState<SealFormScreen> createState() => _SealFormScreenState();
}

class _EntryDraft {
  String entryType = 'EL.V.';
  String dimension = defaultDimensionForEntry('EL.V.', 'žádná');
  int quantity = 1;
  String insulation = 'žádná';
  List<String> materials = [];
}

class _SealFormScreenState extends ConsumerState<SealFormScreen> {
  final _numberCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _system;
  String? _construction;
  String? _location;
  String? _fireRating;
  final _entries = [_EntryDraft()];
  final _photoPaths = <String>[];
  bool _saving = false;
  bool _showPhotoWarning = false;

  Future<void> _addPhotoFromSource(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: source, imageQuality: 85);
      if (img == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fotka nebyla vybrána')),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final out = '${dir.path}/${const Uuid().v4()}.webp';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        img.path,
        out,
        quality: 85,
        format: CompressFormat.webp,
      );
      if (compressed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Komprese fotky se nezdařila')),
          );
        }
        return;
      }
      setState(() {
        _photoPaths.add(compressed.path);
        _showPhotoWarning = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotku se nepodařilo přidat: $e')),
        );
      }
    }
  }

  void _removePhotoAt(int index) {
    setState(() => _photoPaths.removeAt(index));
  }

  Widget _photosSection() {
    final missing = _photoPaths.isEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: missing && _showPhotoWarning
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Fotky *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Minimálně 1 fotka před uložením',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: missing && _showPhotoWarning
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => _addPhotoFromSource(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Vyfotit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => _addPhotoFromSource(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galerie'),
                ),
              ),
            ],
          ),
          if (_photoPaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${_photoPaths.length} fotek'),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photoPaths.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final path = _photoPaths[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(path),
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(4),
                            minimumSize: const Size(28, 28),
                          ),
                          iconSize: 18,
                          onPressed: () => _removePhotoAt(i),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final sealNumber = _numberCtrl.text.trim();
    if (sealNumber.isEmpty ||
        _system == null ||
        _construction == null ||
        _location == null ||
        _fireRating == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vyplňte povinná pole')));
      return;
    }
    if (!_sealNumberPattern.hasMatch(sealNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Číslo ucpávky musí obsahovat jen číslice')),
      );
      return;
    }
    if (_entries.any((e) => e.materials.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Každý prostup potřebuje materiál')));
      return;
    }
    if (_entries.any((e) => e.dimension.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Každý prostup potřebuje rozměr')));
      return;
    }
    if (_photoPaths.isEmpty) {
      setState(() => _showPhotoWarning = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Přidejte alespoň jednu fotku')));
      return;
    }

    setState(() => _saving = true);
    final sealId = const Uuid().v4();
    final payload = {
      'id': sealId,
      'jobId': widget.jobId,
      'floorId': widget.floorId,
      'sealNumber': sealNumber,
      'system': _system,
      'construction': _construction,
      'location': _location,
      'fireRating': _fireRating,
      'note': _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
      'entries': _entries.map((e) => {
        'entryType': e.entryType,
        'dimension': e.dimension,
        'quantity': e.quantity,
        'insulation': e.insulation,
        'materials': e.materials,
      }).toList(),
    };

    try {
      final db = ref.read(databaseProvider);
      await db.into(db.localSeals).insert(LocalSealsCompanion.insert(
        id: sealId,
        jobId: widget.jobId,
        floorId: widget.floorId,
        sealNumber: sealNumber,
        system: _system!,
        construction: _construction!,
        location: _location!,
        fireRating: _fireRating!,
        note: Value(_noteCtrl.text.isEmpty ? null : _noteCtrl.text),
        status: const Value('draft'),
        isSynced: const Value(false),
        jsonPayload: Value(jsonEncode(payload)),
        updatedAt: DateTime.now(),
      ));

      for (final path in _photoPaths) {
        await db.into(db.localPhotos).insert(LocalPhotosCompanion.insert(
          id: const Uuid().v4(),
          sealId: sealId,
          localPath: path,
          createdAt: DateTime.now(),
        ));
      }

      await ref.read(syncServiceProvider).enqueueMutation(
        entityType: 'seal',
        operation: 'create',
        payload: payload,
      );

      try {
        final dio = ref.read(dioProvider);
        final res = await dio.post('/api/seals', data: {
          ...payload,
          'entries': payload['entries'],
        });
        final serverId = (res.data as Map)['id'] as String;
        await (db.update(db.localSeals)..where((s) => s.id.equals(sealId))).write(
          LocalSealsCompanion(id: Value(serverId), isSynced: const Value(true)),
        );
        for (final path in _photoPaths) {
          final formData = FormData.fromMap({
            'photo': await MultipartFile.fromFile(path, filename: 'photo.webp'),
          });
          await dio.post('/api/seals/$serverId/photos', data: formData);
        }
      } catch (_) {
        await ref.read(syncServiceProvider).syncAll();
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Uloženo'),
          content: const Text('Ucpávka byla uložena lokálně.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                context.go('/seal/new?jobId=${widget.jobId}&floorId=${widget.floorId}');
              },
              child: const Text('Přidat další'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                context.pop();
              },
              child: const Text('Zpět na seznam'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _removeEntry(int index) {
    if (_entries.length <= 1) return;
    setState(() => _entries.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nová ucpávka')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _numberCtrl,
              decoration: const InputDecoration(
                labelText: 'Číslo ucpávky *',
                border: OutlineInputBorder(),
                helperText: 'Pouze číslice',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ChipSelector(
              label: 'Systém *',
              options: sealSystems,
              selected: _system,
              onSelected: (v) => setState(() => _system = v),
            ),
            const SizedBox(height: 16),
            ..._entries.asMap().entries.map((i) => _EntryEditor(
              index: i.key,
              entry: i.value,
              system: _system,
              canRemove: _entries.length > 1,
              onRemove: () => _removeEntry(i.key),
              onChanged: () => setState(() {}),
            )),
            TextButton.icon(
              onPressed: () => setState(() => _entries.add(_EntryDraft())),
              icon: const Icon(Icons.add),
              label: const Text('Přidat prostup'),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            _photosSection(),
            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Poznámka', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const CircularProgressIndicator() : const Text('Uložit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({
    required this.index,
    required this.entry,
    required this.system,
    required this.onChanged,
    this.canRemove = false,
    this.onRemove,
  });
  final int index;
  final _EntryDraft entry;
  final String? system;
  final VoidCallback onChanged;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  final _ocelDiameterCtrl = TextEditingController();
  final _vztWidthCtrl = TextEditingController();
  final _vztLengthCtrl = TextEditingController();

  _EntryDraft get entry => widget.entry;

  @override
  void dispose() {
    _ocelDiameterCtrl.dispose();
    _vztWidthCtrl.dispose();
    _vztLengthCtrl.dispose();
    super.dispose();
  }

  void _applyEntryType(String v) {
    entry.entryType = v;
    entry.dimension = defaultDimensionForEntry(v, entry.insulation);
    widget.onChanged();
  }

  void _applyInsulation(String v) {
    entry.insulation = v;
    if (entry.entryType == 'PROSTUP') {
      entry.dimension = defaultDimensionForEntry(entry.entryType, v);
    }
    widget.onChanged();
  }

  void _applyOcelDiameter() {
    final mm = _ocelDiameterCtrl.text.trim();
    if (mm.isEmpty) return;
    entry.dimension = 'Ø$mm';
    widget.onChanged();
  }

  void _applyVztCustomSize() {
    final w = _vztWidthCtrl.text.trim();
    final l = _vztLengthCtrl.text.trim();
    if (w.isEmpty || l.isEmpty) return;
    entry.dimension = '${w}x$l mm';
    widget.onChanged();
  }

  Widget _dimensionSection() {
    if (entry.entryType == 'OCEL') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Průměr trubky (mm)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ocelDiameterCtrl,
                  decoration: const InputDecoration(
                    labelText: 'mm',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _applyOcelDiameter(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _applyOcelDiameter, child: const Text('Použít')),
            ],
          ),
          if (entry.dimension.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Rozměr: ${entry.dimension}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      );
    }

    final presets = dimensionPresetsForEntry(entry.entryType, entry.insulation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChipSelector(
          label: 'Rozměr',
          options: presets,
          selected: entry.dimension.isEmpty ? null : entry.dimension,
          onSelected: (v) {
            entry.dimension = v;
            widget.onChanged();
          },
          allowCustom: true,
        ),
        if (entry.entryType == 'VZT') ...[
          const SizedBox(height: 8),
          const Text('Vlastní rozměr VZT (mm)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vztWidthCtrl,
                  decoration: const InputDecoration(labelText: 'Šířka', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _vztLengthCtrl,
                  decoration: const InputDecoration(labelText: 'Délka', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _applyVztCustomSize, child: const Text('Použít vlastní rozměr')),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Prostup ${widget.index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (widget.canRemove)
                  IconButton(
                    tooltip: 'Odebrat prostup',
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            if (widget.system != null)
              MultiChipSelector(
                label: 'Materiály',
                options: systemMaterials[widget.system] ?? ['Jiný'],
                selected: entry.materials,
                allowCustom: true,
                onChanged: (v) {
                  entry.materials = v;
                  widget.onChanged();
                },
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nejdřív vyberte systém',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            ChipSelector(
              label: 'Typ',
              options: entryTypes,
              selected: entry.entryType,
              onSelected: _applyEntryType,
            ),
            const SizedBox(height: 8),
            _dimensionSection(),
            Row(
              children: [
                const Text('Kusy: '),
                IconButton(
                  onPressed: entry.quantity > 1
                      ? () {
                          entry.quantity--;
                          widget.onChanged();
                        }
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('${entry.quantity}'),
                IconButton(
                  onPressed: () {
                    entry.quantity++;
                    widget.onChanged();
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            ChipSelector(
              label: 'Izolace',
              options: insulations,
              selected: entry.insulation,
              onSelected: _applyInsulation,
            ),
          ],
        ),
      ),
    );
  }
}
