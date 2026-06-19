import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../auth/auth_provider.dart';
import '../jobs/floor_plan/floor_drawing_download_service.dart';
import '../seals/seal_detail_screen.dart';
import '../seals/seal_note_helpers.dart';
import '../seals/seal_photo_upload.dart';
import 'sync_conflict.dart';
import 'sync_outbox_user.dart';
import 'sync_retry.dart';

final syncServiceProvider = Provider((ref) => SyncService(ref));

final syncPendingCountProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(databaseProvider);
  final userId = ref.watch(currentUserIdProvider);
  while (true) {
    yield await countDueSyncItems(db, DateTime.now(), userId: userId);
    await Future.delayed(const Duration(seconds: 5));
  }
});

final syncQueuedOutboxCountProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(databaseProvider);
  final userId = ref.watch(currentUserIdProvider);
  while (true) {
    yield await countQueuedOutboxItems(db, userId: userId);
    await Future.delayed(const Duration(seconds: 5));
  }
});

final unsentPhotosCountProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(databaseProvider);
  while (true) {
    yield await countUnsentPhotos(db);
    await Future.delayed(const Duration(seconds: 5));
  }
});

final unsentPhotosProvider = StreamProvider<List<({LocalPhoto photo, String? sealNumber})>>((ref) async* {
  final db = ref.watch(databaseProvider);
  while (true) {
    yield await loadUnsentPhotosWithSeal(db);
    await Future.delayed(const Duration(seconds: 5));
  }
});

final connectivityProvider = StreamProvider<bool>((ref) async* {
  await for (final r in Connectivity().onConnectivityChanged) {
    yield r.any((e) => e != ConnectivityResult.none);
  }
});

class SyncService {
  SyncService(this._ref);
  final Ref _ref;
  final _uuid = const Uuid();
  static const deviceIdKey = 'device_id';

  AppDatabase get _db => _ref.read(databaseProvider);
  Dio get _dio => _ref.read(dioProvider);

  Future<String> _deviceId() async {
    const storage = FlutterSecureStorage();
    var id = await storage.read(key: deviceIdKey);
    if (id == null) {
      id = _uuid.v4();
      await storage.write(key: deviceIdKey, value: id);
    }
    return id;
  }

  Future<void> enqueueMutation({
    required String entityType,
    required String operation,
    required Map<String, dynamic> payload,
    int? baseVersion,
    AppDatabase? db,
  }) async {
    final database = db ?? _db;
    final deviceId = await _deviceId();
    final userId = _ref.read(currentUserIdProvider);
    await database.into(database.localOutbox).insert(LocalOutboxCompanion.insert(
          id: _uuid.v4(),
          mutationId: _uuid.v4(),
          userId: Value(userId),
          deviceId: deviceId,
          entityType: entityType,
          operation: operation,
          payload: jsonEncode(payload),
          baseVersion: Value(baseVersion),
          status: const Value('pending'),
          retryCount: const Value(0),
          createdAt: DateTime.now(),
        ));
  }

  /// [force] true = ruční sync (ignoruje nextRetryAt); false = automatický retry timer.
  Future<SyncResult> syncAll({bool force = true}) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      return SyncResult(offline: true);
    }

    final now = DateTime.now();
    final userId = _ref.read(currentUserIdProvider);
    if (!force && !await hasDueSyncWork(_db, now, userId: userId)) {
      return SyncResult(success: true, skipped: true);
    }

    try {
      await _pushOutbox(force: force, now: now);
      await _uploadPendingPhotos(force: force, now: now);
      await _pullChanges();
      await processPendingDrawingDownloads(dio: _dio, db: _db, now: now);
      return SyncResult(success: true);
    } on DioException catch (e) {
      return SyncResult(success: false, error: e.message);
    }
  }

  Future<List<LocalOutboxData>> _dueOutboxRows(
      {required bool force, required DateTime now}) async {
    final userId = _ref.read(currentUserIdProvider);
    final rows = filterOutboxForUser(
      await (_db.select(_db.localOutbox)
            ..where((o) => o.status.isIn(['pending', 'failed'])))
          .get(),
      userId,
    );
    if (force) return rows;
    return rows.where((o) => outboxIsDueForRetry(o, now)).toList();
  }

  Future<void> _pushOutbox({required bool force, required DateTime now}) async {
    final pending = await _dueOutboxRows(force: force, now: now);
    if (pending.isEmpty) return;

    final deviceId = await _deviceId();
    final mutations = pending
        .map((o) => {
              'mutationId': o.mutationId,
              'deviceId': deviceId,
              'entityType': o.entityType,
              'operation': o.operation,
              'payload': jsonDecode(o.payload) as Map<String, dynamic>,
              if (o.baseVersion != null) 'baseVersion': o.baseVersion,
            })
        .toList();

    List<Map<String, dynamic>> results;
    try {
      final res =
          await _dio.post('/api/sync/push', data: {'mutations': mutations});
      results = (res.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      for (final row in pending) {
        await markOutboxSyncFailure(
          _db,
          row.id,
          currentRetryCount: row.retryCount,
          error: e.toString(),
          now: now,
        );
      }
      rethrow;
    }

    for (var i = 0; i < pending.length; i++) {
      if (i >= results.length) {
        await markOutboxSyncFailure(
          _db,
          pending[i].id,
          currentRetryCount: pending[i].retryCount,
          error: 'Neúplná odpověď serveru při synchronizaci',
          now: now,
        );
        continue;
      }
      final r = results[i];
      final status = r['status'] as String;
      if (status == 'ok' || status == 'already_processed') {
        await markOutboxSyncSuccess(_db, pending[i].id);
        final localSealId = await resolveSealIdForOutbox(_db, pending[i]);
        final serverId = r['entityId'] as String?;
        if (localSealId != null && serverId != null) {
          if (localSealId != serverId) {
            await remapLocalSealIdAfterPush(_db, localSealId, serverId);
          } else {
            await (_db.update(_db.localSeals)
                  ..where((s) => s.id.equals(localSealId)))
                .write(
              const LocalSealsCompanion(
                isSynced: Value(true),
                syncConflict: Value(false),
              ),
            );
          }
        }
      } else if (status == 'conflict') {
        final conflictMsg =
            r['conflict'] as String? ?? 'Konflikt při synchronizaci';
        await (_db.update(_db.localOutbox)
              ..where((o) => o.id.equals(pending[i].id)))
            .write(
          LocalOutboxCompanion(
            status: const Value('conflict'),
            conflictMessage: Value(conflictMsg),
          ),
        );
        final sealId = await resolveSealIdForOutbox(_db, pending[i]);
        if (sealId != null) {
          await (_db.update(_db.localSeals)..where((s) => s.id.equals(sealId)))
              .write(
            const LocalSealsCompanion(syncConflict: Value(true)),
          );
        }
      } else {
        final err =
            r['error'] as String? ?? r['conflict'] as String? ?? 'Sync selhal';
        await markOutboxSyncFailure(
          _db,
          pending[i].id,
          currentRetryCount: pending[i].retryCount,
          error: err,
          now: now,
        );
      }
    }
  }

  Future<void> _pullChanges() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    final cursorKey = 'last_pull_$userId';

    var hasMore = true;
    while (hasMore) {
      final cursor = await (_db.select(_db.syncCursor)
            ..where((c) => c.key.equals(cursorKey)))
          .getSingleOrNull();
      final since = cursor?.lastPull ?? DateTime.fromMillisecondsSinceEpoch(0);

      final res = await _dio.get('/api/sync/pull', queryParameters: {
        'since': since.toIso8601String(),
      });
      final data = res.data as Map<String, dynamic>;
      hasMore = data['hasMore'] as bool? ?? false;
      // Kurzor posouváme na nextSince = nejvyšší updatedAt ve stažené dávce,
      // ne na serverTime (čas requestu). Jinak by se přeskočily změny s
      // updatedAt mezi dávkami. Fallback na serverTime kvůli starším serverům.
      final nextSince = DateTime.tryParse(data['nextSince'] as String? ?? '') ??
          DateTime.tryParse(data['serverTime'] as String? ?? '') ??
          since;

      for (final j in (data['jobs'] as List? ?? [])) {
        final m = j as Map<String, dynamic>;
        await _db
            .into(_db.localJobs)
            .insertOnConflictUpdate(LocalJobsCompanion.insert(
              id: m['id'] as String,
              projectNumber: m['projectNumber'] as String,
              name: m['name'] as String,
              address: Value(m['address'] as String?),
              isArchived: Value(m['isArchived'] as bool? ?? false),
              status: Value(
                m['status'] as String? ??
                    ((m['isArchived'] as bool? ?? false) ? 'archived' : 'active'),
              ),
              deletedAt: const Value(null),
              updatedAt: DateTime.parse(m['updatedAt'] as String),
            ));
      }

      for (final f in (data['floors'] as List? ?? [])) {
        final m = f as Map<String, dynamic>;
        await _db
            .into(_db.localFloors)
            .insertOnConflictUpdate(LocalFloorsCompanion.insert(
              id: m['id'] as String,
              jobId: m['jobId'] as String,
              name: m['name'] as String,
              sortOrder: Value(m['sortOrder'] as int? ?? 0),
              deletedAt: const Value(null),
              updatedAt: DateTime.parse(m['updatedAt'] as String),
            ));
      }

      final activeOutboxSealIds = await loadSealIdsWithActiveSyncOutbox(
        _db,
        userId: userId,
      );

      for (final s in (data['seals'] as List? ?? [])) {
        final m = s as Map<String, dynamic>;
        final sealId = m['id'] as String;
        final existing = await (_db.select(_db.localSeals)
              ..where((row) => row.id.equals(sealId)))
            .getSingleOrNull();
        final syncFlags = pullSealSyncFlags(
          existing: existing,
          hasActiveOutbox: activeOutboxSealIds.contains(sealId),
        );
        await _db
            .into(_db.localSeals)
            .insertOnConflictUpdate(LocalSealsCompanion.insert(
              id: sealId,
              jobId: m['jobId'] as String,
              floorId: m['floorId'] as String,
              sealNumber: m['sealNumber'] as String,
              trade: Value(m['trade'] as String? ?? existing?.trade ?? 'neurceno'),
              system: m['system'] as String,
              construction: m['construction'] as String,
              location: m['location'] as String,
              fireRating: m['fireRating'] as String,
              note: Value(m['note'] as String?),
              internalNote: Value(m['internalNote'] as String?),
              status: Value(m['status'] as String? ?? 'draft'),
              version: Value(m['version'] as int? ?? 1),
              isSynced: Value(syncFlags.isSynced),
              syncConflict: Value(syncFlags.syncConflict),
              markerPlacementPending: Value(
                m['markerPlacementPending'] as bool? ??
                    existing?.markerPlacementPending ??
                    false,
              ),
              deletedAt: const Value(null),
              updatedAt: DateTime.parse(m['updatedAt'] as String),
            ));
        if (existing?.jsonPayload != null && existing!.jsonPayload!.isNotEmpty) {
          final patched = patchSealJsonPayloadNotes(
            jsonPayload: existing.jsonPayload,
            note: m['note'] as String?,
            internalNote: m['internalNote'] as String?,
          );
          if (patched != null && patched != existing.jsonPayload) {
            await (_db.update(_db.localSeals)..where((row) => row.id.equals(sealId)))
                .write(LocalSealsCompanion(jsonPayload: Value(patched)));
          }
        }
        await cacheSealPhotosFromApiList(
          _db,
          sealId,
          m['photos'] as List?,
        );
      }

      for (final d in (data['floorDrawings'] as List? ?? [])) {
        final m = d as Map<String, dynamic>;
        final floorId = m['floorId'] as String;
        final floor = await (_db.select(_db.localFloors)
              ..where((f) => f.id.equals(floorId)))
            .getSingleOrNull();
        final jobId = floor?.jobId ?? m['jobId'] as String? ?? '';
        if (jobId.isEmpty) continue;
        await upsertFloorDrawingMetadata(
          _db,
          floorId: floorId,
          jobId: jobId,
          meta: m,
        );
        await downloadFloorDrawingFile(
          dio: _dio,
          db: _db,
          jobId: jobId,
          floorId: floorId,
          meta: m,
        );
      }

      for (final mk in (data['sealMarkers'] as List? ?? [])) {
        final m = mk as Map<String, dynamic>;
        final sealId = m['sealId'] as String;
        final seal = await (_db.select(_db.localSeals)
              ..where((s) => s.id.equals(sealId)))
            .getSingleOrNull();
        await _db.into(_db.localSealMarkers).insertOnConflictUpdate(
              LocalSealMarkersCompanion.insert(
                sealId: sealId,
                floorId: m['floorId'] as String,
                sealNumber: seal?.sealNumber ?? '',
                x: (m['x'] as num).toDouble(),
                y: (m['y'] as num).toDouble(),
                updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                    DateTime.now(),
              ),
            );
      }

      final deleted = data['deleted'] as Map<String, dynamic>? ?? const {};
      for (final j in (deleted['jobs'] as List? ?? [])) {
        final m = j as Map<String, dynamic>;
        await (_db.update(_db.localJobs)
              ..where((row) => row.id.equals(m['id'] as String)))
            .write(
          LocalJobsCompanion(
            deletedAt: Value(DateTime.tryParse(m['deletedAt'] as String? ?? '') ??
                DateTime.now()),
            updatedAt: Value(DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                DateTime.now()),
          ),
        );
      }
      for (final f in (deleted['floors'] as List? ?? [])) {
        final m = f as Map<String, dynamic>;
        await (_db.update(_db.localFloors)
              ..where((row) => row.id.equals(m['id'] as String)))
            .write(
          LocalFloorsCompanion(
            deletedAt: Value(DateTime.tryParse(m['deletedAt'] as String? ?? '') ??
                DateTime.now()),
            updatedAt: Value(DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                DateTime.now()),
          ),
        );
      }
      for (final s in (deleted['seals'] as List? ?? [])) {
        final m = s as Map<String, dynamic>;
        final sealId = m['id'] as String;
        await (_db.update(_db.localSeals)
              ..where((row) => row.id.equals(sealId)))
            .write(
          LocalSealsCompanion(
            deletedAt: Value(DateTime.tryParse(m['deletedAt'] as String? ?? '') ??
                DateTime.now()),
            updatedAt: Value(DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                DateTime.now()),
          ),
        );
        // Smazat i marker, aby na výkrese nezůstala fantomová značka.
        await (_db.delete(_db.localSealMarkers)
              ..where((row) => row.sealId.equals(sealId)))
            .go();
      }

      final archived = data['archived'] as Map<String, dynamic>? ?? const {};
      for (final j in (archived['jobs'] as List? ?? [])) {
        final m = j as Map<String, dynamic>;
        await (_db.update(_db.localJobs)
              ..where((row) => row.id.equals(m['id'] as String)))
            .write(
          LocalJobsCompanion(
            isArchived: const Value(true),
            status: Value(m['status'] as String? ?? 'archived'),
            updatedAt: Value(DateTime.tryParse(m['updatedAt'] as String? ?? '') ??
                DateTime.now()),
          ),
        );
      }

      await _db.into(_db.syncCursor).insertOnConflictUpdate(
            SyncCursorCompanion.insert(key: cursorKey, lastPull: nextSince),
          );
    }
  }

  Future<void> _uploadPendingPhotos(
      {required bool force, required DateTime now}) async {
    final all = await (_db.select(_db.localPhotos)
          ..where((p) => p.status.isIn(['pending', 'failed'])))
        .get();
    final pending =
        force ? all : all.where((p) => photoIsDueForRetry(p, now)).toList();

    for (final photo in pending) {
      final seal = await (_db.select(_db.localSeals)
            ..where((s) => s.id.equals(photo.sealId)))
          .getSingleOrNull();
      if (isPhotoUploadBlockedBySeal(seal)) {
        continue;
      }

      if (!File(photo.localPath).existsSync()) {
        await markPhotoSyncFailure(
          _db,
          photo.id,
          currentRetryCount: photo.retryCount,
          error: 'Lokální soubor fotky nenalezen',
          now: now,
        );
        continue;
      }

      PreparedPhotoUpload? prepared;
      try {
        final sealId = await resolvePhotoUploadSealId(_db, photo);
        if (sealId == null) {
          continue;
        }

        final upload = await sealPhotoMultipartFile(photo.localPath);
        prepared = upload.prepared;
        final formData = FormData.fromMap({
          'photo': upload.multipart,
          'photoType': 'detail',
        });
        final res = await _dio.post('/api/seals/$sealId/photos',
            data: formData);
        final data = res.data is Map ? res.data as Map : const {};
        await markPhotoSyncSuccess(
          _db,
          photo.id,
          serverPath: data['filePath'] as String?,
          serverPhotoId: data['id'] as String?,
        );
      } catch (e) {
        await markPhotoSyncFailure(
          _db,
          photo.id,
          currentRetryCount: photo.retryCount,
          error: photoSyncErrorMessage(e),
          now: now,
        );
      } finally {
        await prepared?.dispose();
      }
    }
  }

}

class SyncResult {
  SyncResult({
    this.success = false,
    this.offline = false,
    this.skipped = false,
    this.error,
  });
  final bool success;
  final bool offline;
  final bool skipped;
  final String? error;
}
