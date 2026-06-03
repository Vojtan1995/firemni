import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../database/database.dart';
import '../../database/database_provider.dart';
import '../auth/auth_provider.dart';
import '../seals/seal_duplicate_local.dart';
import 'sync_outbox_user.dart';

/// Zobrazení jednoho sync konfliktu (FE-03).
class SyncConflictView {
  SyncConflictView({
    required this.outboxId,
    required this.entityType,
    required this.operation,
    required this.conflictMessage,
    required this.createdAt,
    this.sealNumber,
    this.jobLabel,
    this.floorName,
    this.sealId,
  });

  final String outboxId;
  final String entityType;
  final String operation;
  final String conflictMessage;
  final DateTime createdAt;
  final String? sealNumber;
  final String? jobLabel;
  final String? floorName;
  final String? sealId;

  String get operationLabel {
    switch (operation) {
      case 'create':
        return 'Vytvoření';
      case 'update':
        return 'Úprava';
      case 'delete':
        return 'Smazání';
      case 'status':
        return 'Změna statusu';
      default:
        return operation;
    }
  }
}

final syncConflictsProvider = StreamProvider<List<SyncConflictView>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final userId = ref.watch(currentUserIdProvider);
  while (true) {
    yield await loadActiveSyncConflicts(db, userId: userId);
    await Future.delayed(const Duration(seconds: 3));
  }
});

final syncConflictCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(syncConflictsProvider).whenData((list) => list.length);
});

Future<List<SyncConflictView>> loadActiveSyncConflicts(
  AppDatabase db, {
  String? userId,
}) async {
  final rows = filterOutboxForUser(
    await (db.select(db.localOutbox)
          ..where((o) => o.status.equals('conflict') & o.dismissedAt.isNull())
          ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
        .get(),
    userId,
  );

  final views = <SyncConflictView>[];
  for (final row in rows) {
    views.add(await _toConflictView(db, row));
  }
  return views;
}

/// After duplicate conflict: new number, new mutationId, re-queue for sync (T12 / D1).
Future<String?> fixDuplicateSealNumberAndRequeue(
  AppDatabase db, {
  required String outboxId,
  required String newSealNumber,
}) async {
  final row = await (db.select(db.localOutbox)
        ..where((o) => o.id.equals(outboxId)))
      .getSingleOrNull();
  if (row == null || row.entityType != 'seal') return 'Konflikt nenalezen';

  final payload = Map<String, dynamic>.from(
    jsonDecode(row.payload) as Map<String, dynamic>,
  );
  final jobId = payload['jobId'] as String?;
  final floorId = payload['floorId'] as String?;
  if (jobId == null || floorId == null) {
    return 'Chybí stavba nebo patro v konfliktu';
  }

  final duplicate = await findLocalDuplicateSeal(
    db,
    jobId: jobId,
    floorId: floorId,
    sealNumber: newSealNumber,
    excludeSealId: await resolveSealIdForOutbox(db, row),
  );
  if (duplicate != null) {
    return duplicateSealNumberMessage;
  }

  payload['sealNumber'] = newSealNumber;
  final sealId = await resolveSealIdForOutbox(db, row);

  if (sealId != null) {
    final seal = await (db.select(db.localSeals)
          ..where((s) => s.id.equals(sealId)))
        .getSingleOrNull();
    var jsonPayload = seal?.jsonPayload;
    if (jsonPayload != null && jsonPayload.isNotEmpty) {
      final decoded =
          Map<String, dynamic>.from(jsonDecode(jsonPayload) as Map);
      decoded['sealNumber'] = newSealNumber;
      jsonPayload = jsonEncode(decoded);
    }
    await (db.update(db.localSeals)..where((s) => s.id.equals(sealId))).write(
      LocalSealsCompanion(
        sealNumber: Value(newSealNumber),
        syncConflict: const Value(false),
        jsonPayload: jsonPayload != null ? Value(jsonPayload) : const Value.absent(),
      ),
    );
  }

  const uuid = Uuid();
  await (db.update(db.localOutbox)..where((o) => o.id.equals(outboxId))).write(
    LocalOutboxCompanion(
      mutationId: Value(uuid.v4()),
      payload: Value(jsonEncode(payload)),
      status: const Value('pending'),
      conflictMessage: const Value(null),
      dismissedAt: const Value(null),
      retryCount: const Value(0),
      nextRetryAt: const Value(null),
      lastError: const Value(null),
    ),
  );

  return null;
}

Future<void> dismissSyncConflict(AppDatabase db, String outboxId) async {
  final row = await (db.select(db.localOutbox)..where((o) => o.id.equals(outboxId))).getSingleOrNull();
  if (row == null) return;

  await (db.update(db.localOutbox)..where((o) => o.id.equals(outboxId))).write(
    LocalOutboxCompanion(dismissedAt: Value(DateTime.now())),
  );

  final sealId = await resolveSealIdForOutbox(db, row);
  if (sealId != null) {
    await (db.update(db.localSeals)..where((s) => s.id.equals(sealId))).write(
      const LocalSealsCompanion(syncConflict: Value(false)),
    );
  }
}

Future<SyncConflictView> _toConflictView(AppDatabase db, LocalOutboxData row) async {
  final payload = jsonDecode(row.payload) as Map<String, dynamic>;
  final sealId = await resolveSealIdForOutbox(db, row);

  String? sealNumber = payload['sealNumber'] as String?;
  String? jobId = payload['jobId'] as String?;
  String? floorId = payload['floorId'] as String?;

  if (sealId != null) {
    final seal = await (db.select(db.localSeals)..where((s) => s.id.equals(sealId))).getSingleOrNull();
    if (seal != null) {
      sealNumber ??= seal.sealNumber;
      jobId ??= seal.jobId;
      floorId ??= seal.floorId;
    }
  }

  String? jobLabel;
  if (jobId != null) {
    final job = await (db.select(db.localJobs)..where((j) => j.id.equals(jobId!))).getSingleOrNull();
    if (job != null) {
      jobLabel = '${job.projectNumber} – ${job.name}';
    }
  }

  String? floorName;
  if (floorId != null) {
    final floor =
        await (db.select(db.localFloors)..where((f) => f.id.equals(floorId!))).getSingleOrNull();
    floorName = floor?.name;
  }

  return SyncConflictView(
    outboxId: row.id,
    entityType: row.entityType,
    operation: row.operation,
    conflictMessage: row.conflictMessage ?? 'Konflikt při synchronizaci',
    createdAt: row.createdAt,
    sealNumber: sealNumber,
    jobLabel: jobLabel,
    floorName: floorName,
    sealId: sealId,
  );
}

/// Seal IDs with outbox rows that still need sync attention (T1 / S2).
Future<Set<String>> loadSealIdsWithActiveSyncOutbox(
  AppDatabase db, {
  String? userId,
}) async {
  final rows = filterOutboxForUser(
    await (db.select(db.localOutbox)
          ..where((o) =>
              o.status.isIn(['pending', 'failed', 'conflict']) &
              o.dismissedAt.isNull()))
        .get(),
    userId,
  );
  final ids = <String>{};
  for (final row in rows) {
    if (row.entityType != 'seal') continue;
    final sealId = await resolveSealIdForOutbox(db, row);
    if (sealId != null) ids.add(sealId);
  }
  return ids;
}

/// Flags for pull upsert — mirrors [cacheSealDetailFromApi] preservation rules.
({bool isSynced, bool syncConflict}) pullSealSyncFlags({
  required LocalSeal? existing,
  required bool hasActiveOutbox,
}) {
  final preserve = hasActiveOutbox ||
      existing?.isSynced == false ||
      (existing?.syncConflict ?? false);
  if (!preserve) {
    return (isSynced: true, syncConflict: false);
  }
  return (
    isSynced: existing?.isSynced ?? false,
    syncConflict: existing?.syncConflict ?? false,
  );
}

/// Sync flags when caching seal list rows from API (S2 / list refresh).
Future<({bool isSynced, bool syncConflict})> sealListCacheSyncFlags(
  AppDatabase db, {
  required String sealId,
  required LocalSeal? existing,
  String? userId,
}) async {
  final activeIds = await loadSealIdsWithActiveSyncOutbox(db, userId: userId);
  return pullSealSyncFlags(
    existing: existing,
    hasActiveOutbox: activeIds.contains(sealId),
  );
}

/// Merges API list with local-only rows; skips duplicates by id or sealNumber (S1).
List<Map<String, dynamic>> mergeSealListWithLocalRows({
  required List<Map<String, dynamic>> apiList,
  required List<LocalSeal> localOnFloor,
  required Map<String, dynamic> Function(LocalSeal row) mapLocal,
}) {
  final apiIds = apiList.map((e) => e['id'] as String).toSet();
  final apiNumbers = apiList.map((e) => e['sealNumber'] as String).toSet();
  final merged = [...apiList];
  for (final row in localOnFloor) {
    if (apiIds.contains(row.id)) continue;
    if (apiNumbers.contains(row.sealNumber)) continue;
    merged.add(mapLocal(row));
  }
  merged.sort((a, b) =>
      (a['sealNumber'] as String).compareTo(b['sealNumber'] as String));
  return merged;
}

/// After push, replace local seal primary key when server assigns a different id.
Future<void> remapLocalSealIdAfterPush(
  AppDatabase db,
  String fromId,
  String toId,
) async {
  if (fromId == toId) return;
  final row = await (db.select(db.localSeals)
        ..where((s) => s.id.equals(fromId)))
      .getSingleOrNull();
  if (row == null) return;

  await db.transaction(() async {
    await (db.delete(db.localSeals)..where((s) => s.id.equals(fromId))).go();
    await db.into(db.localSeals).insert(
          LocalSealsCompanion.insert(
            id: toId,
            jobId: row.jobId,
            floorId: row.floorId,
            sealNumber: row.sealNumber,
            system: row.system,
            construction: row.construction,
            location: row.location,
            fireRating: row.fireRating,
            note: Value(row.note),
            status: Value(row.status),
            version: Value(row.version),
            isSynced: const Value(true),
            syncConflict: const Value(false),
            jsonPayload: Value(row.jsonPayload),
            deletedAt: Value(row.deletedAt),
            updatedAt: row.updatedAt,
          ),
        );
  });

  await (db.update(db.localPhotos)..where((p) => p.sealId.equals(fromId))).write(
    LocalPhotosCompanion(sealId: Value(toId)),
  );
}

Future<String?> resolveSealIdForOutbox(AppDatabase db, LocalOutboxData row) async {
  final payload = jsonDecode(row.payload) as Map<String, dynamic>;
  final explicit = payload['id'] ?? payload['sealId'];
  if (explicit != null) return explicit.toString();

  if (row.entityType != 'seal') return null;

  final jobId = payload['jobId'] as String?;
  final floorId = payload['floorId'] as String?;
  final sealNumber = payload['sealNumber'] as String?;
  if (jobId == null || floorId == null || sealNumber == null) return null;

  final seal = await (db.select(db.localSeals)
        ..where((s) =>
            s.jobId.equals(jobId) &
            s.floorId.equals(floorId) &
            s.sealNumber.equals(sealNumber)))
      .getSingleOrNull();
  return seal?.id;
}
