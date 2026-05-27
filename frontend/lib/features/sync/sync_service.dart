import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../core/api/api_client.dart';
import '../../database/database.dart';
import '../../database/database_provider.dart';

final syncServiceProvider = Provider((ref) => SyncService(ref));

final syncPendingCountProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(databaseProvider);
  while (true) {
    final pending = await (db.select(db.localOutbox)
          ..where((o) => o.status.isIn(['pending', 'failed'])))
        .get();
    final photos = await (db.select(db.localPhotos)..where((p) => p.status.equals('pending'))).get();
    yield pending.length + photos.length;
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
  }) async {
    final deviceId = await _deviceId();
    await _db.into(_db.localOutbox).insert(LocalOutboxCompanion.insert(
      id: _uuid.v4(),
      mutationId: _uuid.v4(),
      deviceId: deviceId,
      entityType: entityType,
      operation: operation,
      payload: jsonEncode(payload),
      baseVersion: Value(baseVersion),
      status: const Value('pending'),
      createdAt: DateTime.now(),
    ));
  }

  Future<SyncResult> syncAll() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      return SyncResult(offline: true);
    }

    await _uploadPendingPhotos();
    await _pushOutbox();
    await _pullChanges();
    return SyncResult(success: true);
  }

  Future<void> _pushOutbox() async {
    final pending = await (_db.select(_db.localOutbox)
          ..where((o) => o.status.isIn(['pending', 'failed'])))
        .get();

    if (pending.isEmpty) return;

    final deviceId = await _deviceId();
    final mutations = pending.map((o) => {
      'mutationId': o.mutationId,
      'deviceId': deviceId,
      'entityType': o.entityType,
      'operation': o.operation,
      'payload': jsonDecode(o.payload) as Map<String, dynamic>,
      if (o.baseVersion != null) 'baseVersion': o.baseVersion,
    }).toList();

    final res = await _dio.post('/api/sync/push', data: {'mutations': mutations});
    final results = (res.data['results'] as List).cast<Map<String, dynamic>>();

    for (var i = 0; i < pending.length && i < results.length; i++) {
      final r = results[i];
      final status = r['status'] as String;
      if (status == 'ok' || status == 'already_processed') {
        await (_db.update(_db.localOutbox)..where((o) => o.id.equals(pending[i].id)))
            .write(const LocalOutboxCompanion(status: Value('done')));
        if (r['entityId'] != null) {
          await (_db.update(_db.localSeals)..where((s) => s.id.equals(pending[i].id)))
              .write(LocalSealsCompanion(
            isSynced: const Value(true),
            syncConflict: const Value(false),
          ));
        }
      } else if (status == 'conflict') {
        await (_db.update(_db.localOutbox)..where((o) => o.id.equals(pending[i].id)))
            .write(const LocalOutboxCompanion(status: Value('conflict')));
        final sealId = jsonDecode(pending[i].payload)['id'] ?? jsonDecode(pending[i].payload)['sealId'];
        if (sealId != null) {
          await (_db.update(_db.localSeals)..where((s) => s.id.equals(sealId.toString())))
              .write(const LocalSealsCompanion(syncConflict: Value(true)));
        }
      } else {
        await (_db.update(_db.localOutbox)..where((o) => o.id.equals(pending[i].id)))
            .write(LocalOutboxCompanion(
          status: const Value('failed'),
          nextRetryAt: Value(DateTime.now().add(const Duration(minutes: 2))),
        ));
      }
    }
  }

  Future<void> _pullChanges() async {
    final cursor = await (_db.select(_db.syncCursor)..where((c) => c.key.equals('last_pull'))).getSingleOrNull();
    final since = cursor?.lastPull ?? DateTime.fromMillisecondsSinceEpoch(0);

    final res = await _dio.get('/api/sync/pull', queryParameters: {
      'since': since.toIso8601String(),
    });
    final data = res.data as Map<String, dynamic>;

    for (final j in (data['jobs'] as List? ?? [])) {
      final m = j as Map<String, dynamic>;
      await _db.into(_db.localJobs).insertOnConflictUpdate(LocalJobsCompanion.insert(
        id: m['id'] as String,
        projectNumber: m['projectNumber'] as String,
        name: m['name'] as String,
        address: Value(m['address'] as String?),
        isArchived: Value(m['isArchived'] as bool? ?? false),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      ));
    }

    for (final f in (data['floors'] as List? ?? [])) {
      final m = f as Map<String, dynamic>;
      await _db.into(_db.localFloors).insertOnConflictUpdate(LocalFloorsCompanion.insert(
        id: m['id'] as String,
        jobId: m['jobId'] as String,
        name: m['name'] as String,
        sortOrder: Value(m['sortOrder'] as int? ?? 0),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      ));
    }

    for (final s in (data['seals'] as List? ?? [])) {
      final m = s as Map<String, dynamic>;
      await _db.into(_db.localSeals).insertOnConflictUpdate(LocalSealsCompanion.insert(
        id: m['id'] as String,
        jobId: m['jobId'] as String,
        floorId: m['floorId'] as String,
        sealNumber: m['sealNumber'] as String,
        system: m['system'] as String,
        construction: m['construction'] as String,
        location: m['location'] as String,
        fireRating: m['fireRating'] as String,
        note: Value(m['note'] as String?),
        status: Value(m['status'] as String? ?? 'draft'),
        version: Value(m['version'] as int? ?? 1),
        isSynced: const Value(true),
        syncConflict: const Value(false),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      ));
    }

    await _db.into(_db.syncCursor).insertOnConflictUpdate(
      SyncCursorCompanion.insert(key: 'last_pull', lastPull: DateTime.now()),
    );
  }

  Future<void> _uploadPendingPhotos() async {
    final pending = await (_db.select(_db.localPhotos)..where((p) => p.status.equals('pending'))).get();
    for (final photo in pending) {
      try {
        final formData = FormData.fromMap({
          'photo': await MultipartFile.fromFile(photo.localPath, filename: 'photo.webp'),
        });
        await _dio.post('/api/seals/${photo.sealId}/photos', data: formData);
        await (_db.update(_db.localPhotos)..where((p) => p.id.equals(photo.id)))
            .write(const LocalPhotosCompanion(status: Value('done')));
      } catch (_) {}
    }
  }
}

class SyncResult {
  SyncResult({this.success = false, this.offline = false});
  final bool success;
  final bool offline;
}
