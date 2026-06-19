import 'dart:convert';
import 'dart:async';
import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../widgets/widgets.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../sync/sync_service.dart';
import 'chip_selector.dart';
import 'multi_chip_selector.dart';
import 'seal_constants.dart';
import 'seal_duplicate_local.dart';
import 'suggest_next_seal_number.dart';
import 'seal_detail_screen.dart';
import 'seal_form_loader.dart';
import 'seal_calculations.dart';
import '../sync/sync_retry.dart';
import 'seal_photo_storage.dart';
import 'seal_note_helpers.dart';
import '../auth/auth_provider.dart';
import '../../core/unsaved_changes.dart';
import '../jobs/floor_plan/floor_drawing_availability.dart';
import '../jobs/floor_plan/floor_drawing_download_service.dart';
import '../jobs/floor_plan/floor_drawing_status.dart';
import '../jobs/floor_plan_screen.dart';

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
  final _noteCtrl = TextEditingController();
  final _internalNoteCtrl = TextEditingController();
  String? _trade;
  String? _system;
  String? _construction;
  String? _location;
  String? _fireRating;
  final _entries = <SealEntryDraftData>[SealEntryDraftData()];
  final _photoPaths = <String>[];
  bool _saving = false;
  bool _loadingInitial = false;
  bool _trackDirty = false;
  bool _isDirty = false;
  bool _showPhotoWarning = false;
  int _baseVersion = 1;
  String? _duplicateNumberError;
  String? _floorName;
  FloorDrawingState? _drawingState;
  double? _draftMarkerX;
  double? _draftMarkerY;
  bool _markerPlacementConfirmed = false;

  @override
  void initState() {
    super.initState();
    _numberCtrl.addListener(_onSealNumberChanged);
    _numberCtrl.addListener(_markDirty);
    _noteCtrl.addListener(_markDirty);
    _internalNoteCtrl.addListener(_markDirty);
    if (widget.isEdit) {
      _loadingInitial = true;
      _loadForEdit();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final db = ref.read(databaseProvider);
        await _loadFloorContext(db);
        await _applyNewSealDefaults(db);
        var next = await suggestNextSealNumber(db, floorId: widget.floorId);
        try {
          final res = await ref.read(dioProvider).get(
            '/api/jobs/${widget.jobId}/floors/${widget.floorId}/next-seal-number',
          );
          next = (res.data as Map)['nextSealNumber'] as String? ?? next;
        } catch (_) {}
        if (!mounted) return;
        if (_numberCtrl.text.trim().isEmpty) {
          _numberCtrl.text = next;
        }
        setState(() => _trackDirty = true);
      });
    }
  }

  void _markDirty() {
    if (!_trackDirty || _isDirty) return;
    setState(() => _isDirty = true);
  }

  void _enableDirtyTracking() {
    if (!mounted) return;
    setState(() {
      _trackDirty = true;
      _isDirty = false;
    });
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
      if (row != null) {
        final photos = await (db.select(db.localPhotos)
              ..where((p) => p.sealId.equals(widget.sealId!)))
            .get();
        seal = sealDetailFromLocal(row, photos);
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
    _trade = seal['trade'] as String?;
    _system = seal['system'] as String?;
    _construction = seal['construction'] as String?;
    _location = seal['location'] as String?;
    _fireRating = seal['fireRating'] as String?;
    _noteCtrl.text = seal['note'] as String? ?? '';
    _internalNoteCtrl.text = seal['internalNote'] as String? ?? '';
    _baseVersion = seal['version'] as int? ?? 1;
    _entries
      ..clear()
      ..addAll(entryDraftsFromSealMap(seal));

    await _loadFloorContext(db);
    final marker = await (db.select(db.localSealMarkers)
          ..where((m) => m.sealId.equals(widget.sealId!)))
        .getSingleOrNull();
    if (marker != null) _markerPlacementConfirmed = true;

    setState(() => _loadingInitial = false);
    _enableDirtyTracking();
  }

  Future<void> _loadFloorContext(AppDatabase db) async {
    final floor = await (db.select(db.localFloors)
          ..where((f) => f.id.equals(widget.floorId)))
        .getSingleOrNull();
    var drawing = await resolveFloorDrawingState(db, floorId: widget.floorId);

    if (!drawing.hasDrawingOnFloor) {
      try {
        final res = await ref.read(dioProvider).get(
              '/api/jobs/${widget.jobId}/floors/${widget.floorId}/drawing',
            );
        final drawingMeta =
            (res.data as Map)['drawing'] as Map<String, dynamic>?;
        if (drawingMeta != null) {
          await upsertFloorDrawingMetadata(
            db,
            floorId: widget.floorId,
            jobId: widget.jobId,
            meta: drawingMeta,
          );
          drawing = await resolveFloorDrawingState(
            db,
            floorId: widget.floorId,
          );
          final dio = ref.read(dioProvider);
          unawaited(
            downloadFloorDrawingFile(
              dio: dio,
              db: db,
              jobId: widget.jobId,
              floorId: widget.floorId,
              meta: drawingMeta,
            ).then((_) async {
              if (!mounted) return;
              final updated = await resolveFloorDrawingState(
                db,
                floorId: widget.floorId,
              );
              if (mounted) setState(() => _drawingState = updated);
            }),
          );
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _floorName = floor?.name;
      _drawingState = drawing;
    });
  }

  /// Předvyplní bezpečné výchozí hodnoty pro NOVOU ucpávku (nikdy pro editaci).
  /// Preferuje poslední použité hodnoty pracovníka na této zakázce (z poslední
  /// lokální ucpávky), jinak bezpečný default požární odolnosti. Materiály ani
  /// konkrétní produkty se nepředvybírají, aby nevznikla chybná evidence.
  Future<void> _applyNewSealDefaults(AppDatabase db) async {
    final lastSeal = await (db.select(db.localSeals)
          ..where((s) => s.jobId.equals(widget.jobId))
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (lastSeal != null) {
      _trade ??= lastSeal.trade;
      _system ??= lastSeal.system;
      _construction ??= lastSeal.construction;
      _location ??= lastSeal.location;
      _fireRating ??= lastSeal.fireRating;
    }
    // Bezpečný default odolnosti, pokud není co převzít (90 min je nejběžnější).
    _fireRating ??= '90 min';
    if (mounted) setState(() {});
  }

  Future<void> _openDraftPlacement() async {
    final sealNumber = _numberCtrl.text.trim();
    if (sealNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nejdřív zadejte číslo ucpávky')),
      );
      return;
    }
    final result = await context.push<SealPlacementResult>(
      '/floor-plan/${widget.floorId}?jobId=${widget.jobId}&draftPlacement=1&sealNumber=$sealNumber',
    );
    if (result != null && mounted) {
      setState(() {
        _draftMarkerX = result.x;
        _draftMarkerY = result.y;
        _markerPlacementConfirmed = true;
        _isDirty = true;
      });
    }
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
      _markDirty();
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
    _markDirty();
  }

  Widget _drawingSection() {
    final drawing = _drawingState;
    if (drawing == null) {
      return const Text('Načítání stavu výkresu…');
    }
    if (!drawing.hasDrawingOnFloor) {
      return const Text('Patro nemá výkres — značka není potřeba.');
    }
    final statusText = drawing.status.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Značka na výkresu je volitelná — doplníte ji teď nebo později ve výkresu patra.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text('Stav výkresu: $statusText'),
        if (_markerPlacementConfirmed)
          const Text('Značka potvrzena')
        else if (!drawing.isInteractive)
          Text(
            'Po uložení: čeká na zakreslení (výkres zatím není stažen).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        if (drawing.isInteractive)
          FilledButton.icon(
            onPressed: _openDraftPlacement,
            icon: const Icon(Icons.place),
            label: Text(
              _markerPlacementConfirmed ? 'Změnit umístění' : 'Umístit na výkres',
            ),
          ),
      ],
    );
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
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _addPhotoFromSource(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Vyfotit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
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
        _trade == null ||
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
    if (_entries.asMap().entries.any((i) {
      final e = i.value;
      if (e.dimension.trim().isNotEmpty) return false;
      final calc = computeSealEntryPreview(
        entryType: e.entryType,
        quantityKus: e.quantity,
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
    if (_entries.any((e) => e.entryType == 'OCEL' && e.steelInsulated == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('U typu Ocel vyberte Doizolováno (Ano/Ne)')));
      return;
    }
    if (_entries.any(
        (e) => e.entryType == 'EL.V.' && e.electroInstallationType == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('U typu Elektro vyberte typ instalace (Svazek/Husí krk/Žlab)')));
      return;
    }
    final overDeducted = _entries.asMap().entries.any((i) {
      final e = i.value;
      if (e.entryType != 'PROSTUP') return false;
      return computeSealEntryPreview(
        entryType: e.entryType,
        quantityKus: e.quantity,
        itemLengthMm: parseMmText(e.itemLengthMmText),
        itemWidthMm: parseMmText(e.itemWidthMmText),
        allEntries: _entries,
        entryIndex: i.key,
      ).netAreaWasNegative;
    });
    if (overDeducted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Odečtená plocha je větší než celková plocha prostupu.')));
      return;
    }
    if (!widget.isEdit && _photoPaths.isEmpty) {
      setState(() => _showPhotoWarning = true);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Přidejte alespoň jednu fotku')));
      return;
    }

    final db = ref.read(databaseProvider);
    final drawing =
        _drawingState ?? await resolveFloorDrawingState(db, floorId: widget.floorId);

    final placementPending = computeMarkerPlacementPending(
      isEdit: widget.isEdit,
      drawing: drawing,
      markerPlacementConfirmed: _markerPlacementConfirmed,
    );

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
          if (e.entryType == 'OCEL') 'steelInsulated': e.steelInsulated,
          if (e.entryType == 'EL.V.')
            'electroInstallationType': e.electroInstallationType,
        };
      }).toList(),
    );

    try {
      if (widget.isEdit) {
        await _saveEdit(db, sealNumber, entriesPayload);
      } else {
        await _saveCreate(
          db,
          sealNumber,
          entriesPayload,
          markerPlacementPending: placementPending,
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = apiErrorMessage(e, fallback: 'Chyba: $e');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCreate(
    AppDatabase db,
    String sealNumber,
    List<Map<String, dynamic>> entriesPayload, {
    bool markerPlacementPending = false,
  }) async {
    final sealId = const Uuid().v4();
    final role = ref.read(authServiceProvider).role;
    final payload = {
      'id': sealId,
      'jobId': widget.jobId,
      'floorId': widget.floorId,
      'sealNumber': sealNumber,
      'trade': _trade,
      'system': _system,
      'construction': _construction,
      'location': _location,
      'fireRating': _fireRating,
      'markerPlacementPending': markerPlacementPending,
      'entries': entriesPayload,
    };
    SealNoteHelpers.applyNotesToPayload(
      payload,
      role: role,
      noteText: _noteCtrl.text,
      internalNoteText: _internalNoteCtrl.text,
    );
    final cols = SealNoteHelpers.localColumnsForRole(
      role: role,
      noteText: _noteCtrl.text,
      internalNoteText: _internalNoteCtrl.text,
    );

    await db.transaction(() async {
      await db.into(db.localSeals).insert(LocalSealsCompanion.insert(
            id: sealId,
            jobId: widget.jobId,
            floorId: widget.floorId,
            sealNumber: sealNumber,
            trade: Value(_trade!),
            system: _system!,
            construction: _construction!,
            location: _location!,
            fireRating: _fireRating!,
            note: Value(cols.note),
            internalNote: Value(cols.internalNote),
            status: const Value('draft'),
            markerPlacementPending: Value(markerPlacementPending),
            isSynced: const Value(false),
            jsonPayload: Value(jsonEncode(payload)),
            updatedAt: DateTime.now(),
          ));

      if (_markerPlacementConfirmed &&
          _draftMarkerX != null &&
          _draftMarkerY != null) {
        await db.into(db.localSealMarkers).insertOnConflictUpdate(
              LocalSealMarkersCompanion.insert(
                sealId: sealId,
                floorId: widget.floorId,
                sealNumber: sealNumber,
                x: _draftMarkerX!,
                y: _draftMarkerY!,
                updatedAt: DateTime.now(),
              ),
            );
        await ref.read(syncServiceProvider).enqueueMutation(
              db: db,
              entityType: 'seal_marker',
              operation: 'update',
              payload: {
                'sealId': sealId,
                'floorId': widget.floorId,
                'x': _draftMarkerX,
                'y': _draftMarkerY,
              },
            );
      }

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
    if (markerPlacementPending) {
      final addAnother = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Uloženo'),
          content: const Text(
            'Ucpávka uložena jako čeká na zakreslení. '
            'Značku doplníte ve výkresu patra po stažení výkresu nebo na signálu.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Hotovo'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Další ucpávka'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (addAnother == true) {
        context.go('/seal/new?jobId=${widget.jobId}&floorId=${widget.floorId}');
      } else {
        context.go('/seals/${widget.floorId}?jobId=${widget.jobId}');
      }
      return;
    }

    final addAnother = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Uloženo'),
        content: const Text('Chcete zadat další ucpávku?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Ne'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Ano'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (addAnother == true) {
      context.go('/seal/new?jobId=${widget.jobId}&floorId=${widget.floorId}');
    } else {
      context.go('/seals/${widget.floorId}?jobId=${widget.jobId}');
    }
  }

  Future<void> _saveEdit(
    AppDatabase db,
    String sealNumber,
    List<Map<String, dynamic>> entriesPayload,
  ) async {
    final sealId = widget.sealId!;
    final role = ref.read(authServiceProvider).role;
    final existing = await (db.select(db.localSeals)
          ..where((s) => s.id.equals(sealId)))
        .getSingleOrNull();
    final payload = {
      'id': sealId,
      'jobId': widget.jobId,
      'floorId': widget.floorId,
      'sealNumber': sealNumber,
      'trade': _trade,
      'system': _system,
      'construction': _construction,
      'location': _location,
      'fireRating': _fireRating,
      'entries': entriesPayload,
    };
    SealNoteHelpers.applyNotesToPayload(
      payload,
      role: role,
      noteText: _noteCtrl.text,
      internalNoteText: _internalNoteCtrl.text,
      isUpdate: true,
    );
    final cols = SealNoteHelpers.localColumnsForRole(
      role: role,
      noteText: _noteCtrl.text,
      internalNoteText: _internalNoteCtrl.text,
      existingNote: existing?.note,
      existingInternalNote: existing?.internalNote,
    );

    await db.transaction(() async {
      await (db.update(db.localSeals)..where((s) => s.id.equals(sealId))).write(
        LocalSealsCompanion(
          sealNumber: Value(sealNumber),
          trade: Value(_trade!),
          system: Value(_system!),
          construction: Value(_construction!),
          location: Value(_location!),
          fireRating: Value(_fireRating!),
          note: Value(cols.note),
          internalNote: Value(cols.internalNote),
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
    _markDirty();
  }

  @override
  void dispose() {
    _numberCtrl.removeListener(_onSealNumberChanged);
    _numberCtrl.dispose();
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

    return UnsavedChangesPopScope(
      isDirty: _isDirty,
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Upravit ucpávku' : 'Nová ucpávka'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Základ',
              style: SectionHeaderStyle.h3,
            ),
            if (_floorName != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Patro'),
                subtitle: Text(_floorName!),
              ),
              const SizedBox(height: 8),
            ],
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
            const SizedBox(height: 8),
            ChipSelector(
              label: 'Řemeslo *',
              options: sealTrades,
              selected: _trade,
              labelFor: sealTradeLabel,
              onSelected: (v) {
                setState(() => _trade = v);
                _markDirty();
              },
            ),
            const SizedBox(height: 8),
            ChipSelector(
              label: 'Systém *',
              options: sealSystems,
              selected: _system,
              onSelected: (v) {
                setState(() => _system = v);
                _markDirty();
              },
            ),
            const SizedBox(height: 14),
            const SectionHeader(
              title: 'Hlavní prostup',
              subtitle: 'Technické údaje',
              style: SectionHeaderStyle.h3,
            ),
            if (_entries.isNotEmpty)
              _EntryEditor(
                index: 0,
                entry: _entries.first,
                system: _system,
                allEntries: _entries,
                canRemove: false,
                onChanged: () {
                  setState(() {});
                  _markDirty();
                },
              ),
            if (_entries.length > 1) ...[
              const SizedBox(height: 8),
              const SectionHeader(
                title: 'Další prostupy',
                style: SectionHeaderStyle.h3,
              ),
              ..._entries.asMap().entries.where((i) => i.key > 0).map(
                    (i) => _EntryEditor(
                      index: i.key,
                      entry: i.value,
                      system: _system,
                      allEntries: _entries,
                      canRemove: true,
                      onRemove: () => _removeEntry(i.key),
                      onChanged: () {
                        setState(() {});
                        _markDirty();
                      },
                    ),
                  ),
            ],
            TextButton.icon(
              onPressed: () {
                setState(() => _entries.add(SealEntryDraftData()));
                _markDirty();
              },
              icon: const Icon(Icons.add),
              label: const Text('Přidat prostup'),
            ),
            const SizedBox(height: 14),
            const SectionHeader(
              title: 'Umístění',
              style: SectionHeaderStyle.h3,
            ),
            ChipSelector(
              label: 'Konstrukce *',
              options: constructions,
              selected: _construction,
              onSelected: (v) {
                setState(() => _construction = v);
                _markDirty();
              },
            ),
            const SizedBox(height: 8),
            ChipSelector(
              label: 'Umístění *',
              options: locations,
              selected: _location,
              onSelected: (v) {
                setState(() => _location = v);
                _markDirty();
              },
            ),
            const SizedBox(height: 8),
            ChipSelector(
              label: 'Požární odolnost *',
              options: fireRatings,
              selected: _fireRating,
              onSelected: (v) {
                setState(() => _fireRating = v);
                _markDirty();
              },
            ),
            const SizedBox(height: 14),
            const SectionHeader(
                title: 'Značka ve výkresu', style: SectionHeaderStyle.h3),
            _drawingSection(),
            const SizedBox(height: 14),
            const SectionHeader(
                title: 'Foto a poznámka', style: SectionHeaderStyle.h3),
            if (!widget.isEdit) ...[
              _photosSection(),
              const SizedBox(height: 12),
            ],
            ..._noteFields(ref.read(authServiceProvider).role),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Uložit'),
            ),
          ],
        ),
      ),
    ),
    );
  }

  List<Widget> _noteFields(String? role) {
    final fields = <Widget>[];
    if (SealNoteHelpers.canEditPublicNote(role)) {
      fields.addAll([
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Poznámka pro zákazníka',
            hintText: 'Volitelné — může jít do exportu',
            border: OutlineInputBorder(),
          ),
          minLines: 3,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
        ),
        const SizedBox(height: 12),
      ]);
    }
    if (SealNoteHelpers.canEditInternalNote(role)) {
      fields.add(
        TextField(
          key: const Key('seal_internal_note'),
          controller: _internalNoteCtrl,
          decoration: InputDecoration(
            labelText: 'Interní poznámka z terénu',
            hintText: role == 'worker'
                ? 'Volitelné — viditelné pro vedení'
                : 'Volitelné — interní pro vedení',
            border: const OutlineInputBorder(),
          ),
          minLines: 3,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
        ),
      );
    }
    return fields;
  }
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({
    required this.index,
    required this.entry,
    required this.system,
    required this.allEntries,
    required this.onChanged,
    this.canRemove = false,
    this.onRemove,
  });
  final int index;
  final SealEntryDraftData entry;
  final String? system;
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
          'Odečtená plocha instalací: ${formatArea(calc.deductionAreaM2!)} m²');
    }
    if (calc.netAreaM2 != null) {
      lines.add('Čistá účtovaná plocha: ${formatArea(calc.netAreaM2!)} m²');
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
              'Odečtená plocha je větší než celková plocha prostupu.',
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
    if (v != 'OCEL') entry.steelInsulated = null;
    if (v != 'EL.V.') entry.electroInstallationType = null;
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
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
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
            _subLabel('Typ / instalace'),
            ChipSelector(
              label: 'Typ',
              options: entryTypes,
              selected: entry.entryType,
              onSelected: _applyEntryType,
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
                  entry.steelInsulated = v == 'Ano';
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
                  entry.electroInstallationType = v;
                  widget.onChanged();
                },
              ),
            ],
            const SizedBox(height: 8),
            ChipSelector(
              label: 'Izolace',
              options: insulations,
              selected: entry.insulation,
              onSelected: _applyInsulation,
            ),
            const SizedBox(height: 8),
            _subLabel('Rozměry'),
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
          ],
        ),
      ),
    );
  }

  Widget _subLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
