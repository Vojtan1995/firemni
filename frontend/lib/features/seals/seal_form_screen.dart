import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';
import '../../widgets/widgets.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../sync/sync_service.dart';
import 'chip_selector.dart';
import 'multi_chip_selector.dart';
import 'seal_constants.dart';
import 'seal_duplicate_local.dart';
import 'seal_detail_screen.dart';
import 'seal_form_loader.dart';
import 'seal_calculations.dart';
import '../sync/sync_retry.dart';
import 'seal_photo_storage.dart';

final _sealNumberPattern = RegExp(r'^\d+$');

class SealFormScreen extends ConsumerStatefulWidget {
  const SealFormScreen({
    super.key,
    required this.jobId,
    required this.floorId,
    this.sealId,
  });
  final String jobId;
  final String floorId;
  final String? sealId;

  bool get isEdit => sealId != null;

  @override
  ConsumerState<SealFormScreen> createState() => _SealFormScreenState();
}

class _SealFormScreenState extends ConsumerState<SealFormScreen> {
  final _numberCtrl = TextEditingController();
  final _openingLengthCtrl = TextEditingController();
  final _openingWidthCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _internalNoteCtrl = TextEditingController();
  String? _system;
  String? _construction;
  String? _location;
  String? _fireRating;
  final _entries = <SealEntryDraftData>[SealEntryDraftData()];
  final _photoPaths = <String>[];
  bool _saving = false;
  bool _loadingInitial = false;
  bool _showPhotoWarning = false;
  int _baseVersion = 1;
  String? _duplicateNumberError;

  @override
  void initState() {
    super.initState();
    _numberCtrl.addListener(_onSealNumberChanged);
    if (widget.isEdit) {
      _loadingInitial = true;
      _loadForEdit();
    }
  }

  Future<void> _loadForEdit() async {
    final db = ref.read(databaseProvider);
    Map<String, dynamic>? seal;
    try {
      final res =
          await ref.read(dioProvider).get('/api/seals/${widget.sealId}');
      seal = (res.data as Map).cast<String, dynamic>();
      await cacheSealDetailFromApi(db, seal);
    } catch (_) {
      final row = await (db.select(db.localSeals)
            ..where((s) => s.id.equals(widget.sealId!)))
          .getSingleOrNull();
      if (row?.jsonPayload != null && row!.jsonPayload!.isNotEmpty) {
        seal = Map<String, dynamic>.from(
            jsonDecode(row.jsonPayload!) as Map<dynamic, dynamic>);
      }
    }

    if (!mounted) return;
    if (seal == null) {
      setState(() => _loadingInitial = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ucpávku se nepodařilo načíst')),
      );
      context.pop();
      return;
    }

    if (seal['status'] != 'draft' && seal['status'] != 'checked') {
      setState(() => _loadingInitial = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Fakturované ucpávky nelze upravovat')),
      );
      context.pop();
      return;
    }

    _numberCtrl.text = seal['sealNumber'] as String? ?? '';
    _system = seal['system'] as String?;
    _construction = seal['construction'] as String?;
    _location = seal['location'] as String?;
    _fireRating = seal['fireRating'] as String?;
    _openingLengthCtrl.text = seal['openingLengthMm']?.toString() ?? '';
    _openingWidthCtrl.text = seal['openingWidthMm']?.toString() ?? '';
    _noteCtrl.text = seal['note'] as String? ?? '';
    _internalNoteCtrl.text = seal['internalNote'] as String? ?? '';
    _baseVersion = seal['version'] as int? ?? 1;
    _entries
      ..clear()
      ..addAll(entryDraftsFromSealMap(seal));

    setState(() => _loadingInitial = false);
  }

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
      final persistedPath = await compressAndPersistSealPhoto(img.path);
      if (persistedPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Komprese fotky se nezdařila')),
          );
        }
        return;
      }
      setState(() {
        _photoPaths.add(persistedPath);
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
          const Text('Fotky *',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => _addPhotoFromSource(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Vyfotit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
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
                  return PhotoThumbnailFile(
                    path: path,
                    size: 96,
                    onDelete: () => _removePhotoAt(i),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Vyplňte povinná pole')));
      return;
    }
    if (!_sealNumberPattern.hasMatch(sealNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Číslo ucpávky musí obsahovat jen číslice')),
      );
      return;
    }
    if (_entries.first.materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hlavní prostup potřebuje alespoň jeden materiál')));
      return;
    }
    final openingL = parseMmText(_openingLengthCtrl.text);
    final openingW = parseMmText(_openingWidthCtrl.text);
    if (_entries.asMap().entries.any((i) {
      final e = i.value;
      if (e.dimension.trim().isNotEmpty) return false;
      final calc = computeSealEntryPreview(
        entryType: e.entryType,
        quantityKus: e.quantity,
        openingLengthMm: openingL,
        openingWidthMm: openingW,
        itemLengthMm: parseMmText(e.itemLengthMmText),
        itemWidthMm: parseMmText(e.itemWidthMmText),
        allEntries: _entries,
        entryIndex: i.key,
      );
      return calc.unit == 'kus';
    })) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Každý prostup potřebuje rozměr')));
      return;
    }
    if (!widget.isEdit && _photoPaths.isEmpty) {
      setState(() => _showPhotoWarning = true);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Přidejte alespoň jednu fotku')));
      return;
    }

    final db = ref.read(databaseProvider);
    final duplicate = await findLocalDuplicateSeal(
      db,
      jobId: widget.jobId,
      floorId: widget.floorId,
      sealNumber: sealNumber,
      excludeSealId: widget.sealId,
    );
    if (duplicate != null) {
      if (!mounted) return;
      setState(() => _duplicateNumberError = duplicateSealNumberMessage);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(duplicateSealNumberMessage)),
      );
      return;
    }

    setState(() => _saving = true);
    final entriesPayload = sealEntriesWithSharedMaterials(
      _entries.asMap().entries.map((i) {
        final e = i.value;
        final calc = computeSealEntryPreview(
          entryType: e.entryType,
          quantityKus: e.quantity,
          openingLengthMm: openingL,
          openingWidthMm: openingW,
          itemLengthMm: parseMmText(e.itemLengthMmText),
          itemWidthMm: parseMmText(e.itemWidthMmText),
          allEntries: _entries,
          entryIndex: i.key,
        );
        final itemL = parseMmText(e.itemLengthMmText);
        final itemW = parseMmText(e.itemWidthMmText);
        return {
          'entryType': e.entryType,
          'dimension': e.dimension,
          'quantity': calc.unit == 'kus' ? e.quantity : calc.billableQuantity,
          'insulation': e.insulation,
          'materials': e.materials,
          if (itemL != null) 'itemLengthMm': itemL,
          if (itemW != null) 'itemWidthMm': itemW,
        };
      }).toList(),
    );

    try {
      if (widget.isEdit) {
        await _saveEdit(db, sealNumber, entriesPayload);
      } else {
        await _saveCreate(db, sealNumber, entriesPayload);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Chyba: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _openingPayloadFields() {
    final openingL = parseMmText(_openingLengthCtrl.text);
    final openingW = parseMmText(_openingWidthCtrl.text);
    return {
      if (openingL != null) 'openingLengthMm': openingL,
      if (openingW != null) 'openingWidthMm': openingW,
    };
  }

  Future<void> _saveCreate(
    AppDatabase db,
    String sealNumber,
    List<Map<String, dynamic>> entriesPayload,
  ) async {
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
      'internalNote':
          _internalNoteCtrl.text.isEmpty ? null : _internalNoteCtrl.text,
      ..._openingPayloadFields(),
      'entries': entriesPayload,
    };

    await db.transaction(() async {
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
            internalNote: Value(
                _internalNoteCtrl.text.isEmpty ? null : _internalNoteCtrl.text),
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
            db: db,
            entityType: 'seal',
            operation: 'create',
            payload: payload,
          );
    });

    await ref.read(syncServiceProvider).syncAll();

    if (!mounted) return;
    final message = await _buildSaveDialogMessage(db);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Uloženo'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              context.go(
                  '/seal/new?jobId=${widget.jobId}&floorId=${widget.floorId}');
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
  }

  Future<String> _buildSaveDialogMessage(AppDatabase db) async {
    final unsent = await countUnsentPhotos(db);
    if (unsent == 0) {
      return 'Ucpávka byla uložena, fotky nahrány na server.';
    }
    final word = unsent == 1
        ? 'fotka'
        : unsent < 5
            ? 'fotky'
            : 'fotek';
    return 'Ucpávka byla uložena, ale $unsent $word se nepodařilo nahrát. '
        'Otevřete Synchronizaci a zkuste znovu.';
  }

  Future<void> _saveEdit(
    AppDatabase db,
    String sealNumber,
    List<Map<String, dynamic>> entriesPayload,
  ) async {
    final sealId = widget.sealId!;
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
      'internalNote':
          _internalNoteCtrl.text.isEmpty ? null : _internalNoteCtrl.text,
      ..._openingPayloadFields(),
      'entries': entriesPayload,
    };

    await db.transaction(() async {
      await (db.update(db.localSeals)..where((s) => s.id.equals(sealId))).write(
        LocalSealsCompanion(
          sealNumber: Value(sealNumber),
          system: Value(_system!),
          construction: Value(_construction!),
          location: Value(_location!),
          fireRating: Value(_fireRating!),
          note: Value(_noteCtrl.text.isEmpty ? null : _noteCtrl.text),
          internalNote: Value(
              _internalNoteCtrl.text.isEmpty ? null : _internalNoteCtrl.text),
          isSynced: const Value(false),
          syncConflict: const Value(false),
          jsonPayload: Value(jsonEncode(payload)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await ref.read(syncServiceProvider).enqueueMutation(
            db: db,
            entityType: 'seal',
            operation: 'update',
            payload: payload,
            baseVersion: _baseVersion,
          );
    });

    await ref.read(syncServiceProvider).syncAll();

    if (!mounted) return;
    final unsent = await countUnsentPhotos(db);
    final message = unsent == 0
        ? 'Ucpávka uložena, fotky nahrány na server.'
        : 'Ucpávka uložena, ale $unsent fotek se nepodařilo nahrát. Synchronizujte znovu.';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    context.go('/seal/$sealId');
  }

  void _removeEntry(int index) {
    if (_entries.length <= 1) return;
    setState(() => _entries.removeAt(index));
  }

  @override
  void dispose() {
    _numberCtrl.removeListener(_onSealNumberChanged);
    _numberCtrl.dispose();
    _openingLengthCtrl.dispose();
    _openingWidthCtrl.dispose();
    _noteCtrl.dispose();
    _internalNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSealNumberChanged() async {
    final sealNumber = _numberCtrl.text.trim();
    if (sealNumber.isEmpty || !_sealNumberPattern.hasMatch(sealNumber)) {
      if (_duplicateNumberError != null) {
        setState(() => _duplicateNumberError = null);
      }
      return;
    }
    final db = ref.read(databaseProvider);
    final duplicate = await findLocalDuplicateSeal(
      db,
      jobId: widget.jobId,
      floorId: widget.floorId,
      sealNumber: sealNumber,
      excludeSealId: widget.sealId,
    );
    final nextError = duplicate != null ? duplicateSealNumberMessage : null;
    if (mounted && _duplicateNumberError != nextError) {
      setState(() => _duplicateNumberError = nextError);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInitial) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.isEdit ? 'Upravit ucpávku' : 'Nová ucpávka'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Upravit ucpávku' : 'Nová ucpávka'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _numberCtrl,
              decoration: InputDecoration(
                labelText: 'Číslo ucpávky *',
                border: const OutlineInputBorder(),
                helperText: _duplicateNumberError == null
                    ? 'Pouze číslice — číslo musí odpovídat štítku v terénu'
                    : null,
                errorText: _duplicateNumberError,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            const Text('Rozměr prostupu (volitelné)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _openingLengthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Délka prostupu (mm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _openingWidthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Šířka prostupu (mm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
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
                  openingLengthText: _openingLengthCtrl.text,
                  openingWidthText: _openingWidthCtrl.text,
                  allEntries: _entries,
                  canRemove: _entries.length > 1,
                  onRemove: () => _removeEntry(i.key),
                  onChanged: () => setState(() {}),
                )),
            TextButton.icon(
              onPressed: () => setState(() => _entries.add(SealEntryDraftData())),
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
            if (!widget.isEdit) ...[
              const SizedBox(height: 16),
              _photosSection(),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                  labelText: 'Poznámka', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('seal_internal_note'),
              controller: _internalNoteCtrl,
              decoration: const InputDecoration(
                labelText: 'Interní poznámka z terénu',
                hintText: 'Volitelné — viditelné pro vedení a export',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Uložit'),
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
    required this.openingLengthText,
    required this.openingWidthText,
    required this.allEntries,
    required this.onChanged,
    this.canRemove = false,
    this.onRemove,
  });
  final int index;
  final SealEntryDraftData entry;
  final String? system;
  final String openingLengthText;
  final String openingWidthText;
  final List<SealEntryDraftData> allEntries;
  final VoidCallback onChanged;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  final _ocelDiameterCtrl = TextEditingController();
  final _itemLengthCtrl = TextEditingController();
  final _itemWidthCtrl = TextEditingController();

  SealEntryDraftData get entry => widget.entry;

  @override
  void initState() {
    super.initState();
    _itemLengthCtrl.text = entry.itemLengthMmText;
    _itemWidthCtrl.text = entry.itemWidthMmText;
  }

  @override
  void dispose() {
    _ocelDiameterCtrl.dispose();
    _itemLengthCtrl.dispose();
    _itemWidthCtrl.dispose();
    super.dispose();
  }

  void _syncItemDims() {
    entry.itemLengthMmText = _itemLengthCtrl.text;
    entry.itemWidthMmText = _itemWidthCtrl.text;
    final l = parseMmText(entry.itemLengthMmText);
    final w = parseMmText(entry.itemWidthMmText);
    if (entry.entryType == 'VZT' && l != null && w != null) {
      entry.dimension = '${l}x$w mm';
    } else if (entry.entryType == 'PROSTUP' && l != null && w != null) {
      entry.dimension = '${l}x$w mm';
    }
    widget.onChanged();
  }

  SealCalculationResult get _calc => computeSealEntryPreview(
        entryType: entry.entryType,
        quantityKus: entry.quantity,
        openingLengthMm: parseMmText(widget.openingLengthText),
        openingWidthMm: parseMmText(widget.openingWidthText),
        itemLengthMm: parseMmText(entry.itemLengthMmText),
        itemWidthMm: parseMmText(entry.itemWidthMmText),
        allEntries: widget.allEntries,
        entryIndex: widget.index,
      );

  Widget _calculationPanel() {
    final calc = _calc;
    if (calc.unit == 'kus' &&
        calc.openingAreaM2 == null &&
        calc.linearMeters == null) {
      return const SizedBox.shrink();
    }

    final lines = <String>[];
    final oL = parseMmText(widget.openingLengthText);
    final oW = parseMmText(widget.openingWidthText);
    if (oL != null && oW != null) {
      lines.add('Rozměr prostupu: $oL × $oW mm');
    }
    final iL = parseMmText(entry.itemLengthMmText);
    final iW = parseMmText(entry.itemWidthMmText);
    if (iL != null && iW != null && entry.entryType != 'PROSTUP') {
      lines.add('${entry.entryType}: $iL × $iW mm');
    }
    lines.add('Výpočet:');
    if (calc.openingAreaM2 != null) {
      lines.add('Plocha prostupu: ${formatArea(calc.openingAreaM2!)} m²');
    }
    if (calc.deductionAreaM2 != null && calc.deductionAreaM2! > 0) {
      lines.add(
          'Odečet prvku + 50 mm: ${formatArea(calc.deductionAreaM2!)} m²');
    }
    if (calc.netAreaM2 != null) {
      lines.add('Čistá plocha: ${formatArea(calc.netAreaM2!)} m²');
    }
    if (calc.linearMeters != null) {
      lines.add('Běžné metry: ${formatMb(calc.linearMeters!)} mb');
    }
    lines.add(
        'Množství: ${calc.unit == 'm2' ? formatArea(calc.billableQuantity) : formatMb(calc.billableQuantity)} ${unitLabel(calc.unit)}');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...lines.map((l) => Text(l, style: Theme.of(context).textTheme.bodySmall)),
          if (calc.netAreaWasNegative)
            Text(
              'Upozornění: čistá plocha by byla záporná — použito 0',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemDimensionFields(String lengthLabel, String widthLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(lengthLabel,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _itemLengthCtrl,
                decoration: InputDecoration(
                  labelText: lengthLabel,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => _syncItemDims(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _itemWidthCtrl,
                decoration: InputDecoration(
                  labelText: widthLabel,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => _syncItemDims(),
              ),
            ),
          ],
        ),
      ],
    );
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

  Widget _dimensionSection() {
    if (entry.entryType == 'PROSTUP') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _itemDimensionFields('Délka (mm)', 'Šířka (mm)'),
          _calculationPanel(),
        ],
      );
    }

    if (entry.entryType == 'VZT') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChipSelector(
            label: 'Rozměr (průměr)',
            options: dimensionPresetsForEntry(entry.entryType, entry.insulation),
            selected: entry.dimension.isEmpty ? null : entry.dimension,
            onSelected: (v) {
              entry.dimension = v;
              widget.onChanged();
            },
            allowCustom: true,
          ),
          _itemDimensionFields('Délka D (mm)', 'Šířka Š (mm)'),
          _calculationPanel(),
        ],
      );
    }

    if (entry.entryType == 'OCEL') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Průměr trubky (mm)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
              FilledButton(
                  onPressed: _applyOcelDiameter, child: const Text('Použít')),
            ],
          ),
          if (entry.dimension.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Rozměr: ${entry.dimension}',
                style: Theme.of(context).textTheme.bodySmall),
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
                  child: Text(
                    widget.index == 0
                        ? 'Hlavní prostup'
                        : 'Prostup ${widget.index + 1}',
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
            if (widget.index == 0) ...[
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
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Materiály z hlavního prostupu (systém ucpávky)',
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
            if (_calc.unit == 'kus')
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
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Množství: ${_calc.unit == 'm2' ? formatArea(_calc.billableQuantity) : formatMb(_calc.billableQuantity)} ${unitLabel(_calc.unit)}',
                ),
                subtitle: const Text('Vypočteno automaticky z rozměrů'),
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
