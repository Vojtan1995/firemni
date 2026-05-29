import 'dart:convert';
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

class SealFormScreen extends ConsumerStatefulWidget {
  const SealFormScreen({super.key, required this.jobId, required this.floorId});
  final String jobId;
  final String floorId;

  @override
  ConsumerState<SealFormScreen> createState() => _SealFormScreenState();
}

class _EntryDraft {
  String entryType = 'EL.V.';
  String dimension = 'Ø50';
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

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (img == null) return;
    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/${const Uuid().v4()}.webp';
    final compressed = await FlutterImageCompress.compressAndGetFile(
      img.path,
      out,
      quality: 85,
      format: CompressFormat.webp,
    );
    if (compressed != null) setState(() => _photoPaths.add(compressed.path));
  }

  Future<void> _save() async {
    if (_numberCtrl.text.isEmpty || _system == null || _construction == null || _location == null || _fireRating == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vyplňte povinná pole')));
      return;
    }
    if (_entries.any((e) => e.materials.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Každý prostup potřebuje materiál')));
      return;
    }
    if (_photoPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Přidejte alespoň jednu fotku')));
      return;
    }

    setState(() => _saving = true);
    final sealId = const Uuid().v4();
    final payload = {
      'id': sealId,
      'jobId': widget.jobId,
      'floorId': widget.floorId,
      'sealNumber': _numberCtrl.text,
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
        sealNumber: _numberCtrl.text,
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
              decoration: const InputDecoration(labelText: 'Číslo ucpávky *', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ChipSelector(label: 'Systém *', options: sealSystems, selected: _system, onSelected: (v) => setState(() => _system = v)),
            const SizedBox(height: 12),
            ChipSelector(label: 'Konstrukce *', options: constructions, selected: _construction, onSelected: (v) => setState(() => _construction = v)),
            const SizedBox(height: 12),
            ChipSelector(label: 'Umístění *', options: locations, selected: _location, onSelected: (v) => setState(() => _location = v)),
            const SizedBox(height: 12),
            ChipSelector(label: 'Požární odolnost *', options: fireRatings, selected: _fireRating, onSelected: (v) => setState(() => _fireRating = v)),
            const SizedBox(height: 16),
            ..._entries.asMap().entries.map((i) => _EntryEditor(
              index: i.key,
              entry: i.value,
              system: _system,
              onChanged: () => setState(() {}),
            )),
            TextButton.icon(
              onPressed: () => setState(() => _entries.add(_EntryDraft())),
              icon: const Icon(Icons.add),
              label: const Text('Přidat prostup'),
            ),
            TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: 'Poznámka', border: OutlineInputBorder()), maxLines: 2),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.camera_alt), label: const Text('Fotka')),
                const SizedBox(width: 12),
                Text('${_photoPaths.length} fotek'),
              ],
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

class _EntryEditor extends StatelessWidget {
  const _EntryEditor({required this.index, required this.entry, required this.system, required this.onChanged});
  final int index;
  final _EntryDraft entry;
  final String? system;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prostup ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ChipSelector(label: 'Typ', options: entryTypes, selected: entry.entryType, onSelected: (v) { entry.entryType = v; onChanged(); }),
            ChipSelector(label: 'Rozměr', options: dimensions, selected: entry.dimension, onSelected: (v) { entry.dimension = v; onChanged(); }, allowCustom: true),
            ChipSelector(label: 'Izolace', options: insulations, selected: entry.insulation, onSelected: (v) { entry.insulation = v; onChanged(); }),
            Row(
              children: [
                const Text('Kusy: '),
                IconButton(onPressed: entry.quantity > 1 ? () { entry.quantity--; onChanged(); } : null, icon: const Icon(Icons.remove)),
                Text('${entry.quantity}'),
                IconButton(onPressed: () { entry.quantity++; onChanged(); }, icon: const Icon(Icons.add)),
              ],
            ),
            if (system != null)
              MultiChipSelector(
                label: 'Materiály',
                options: systemMaterials[system] ?? ['Jiný'],
                selected: entry.materials,
                allowCustom: true,
                onChanged: (v) {
                  entry.materials = v;
                  onChanged();
                },
              ),
          ],
        ),
      ),
    );
  }
}
