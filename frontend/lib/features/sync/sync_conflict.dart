import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database.dart';
import '../../database/database_provider.dart';

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
  while (true) {
    yield await loadActiveSyncConflicts(db);
    await Future.delayed(const Duration(seconds: 3));
  }
});

final syncConflictCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(syncConflictsProvider).whenData((list) => list.length);
});

Future<List<SyncConflictView>> loadActiveSyncConflicts(AppDatabase db) async {
  final rows = await (db.select(db.localOutbox)
        ..where((o) => o.status.equals('conflict') & o.dismissedAt.isNull())
        ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
      .get();

  final views = <SyncConflictView>[];
  for (final row in rows) {
    views.add(await _toConflictView(db, row));
  }
  return views;
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
