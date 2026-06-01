import 'package:drift/drift.dart';

import '../../database/database.dart';

/// Intervaly dle [docs/SYNC.md]: 30 s → 2 min → 5 min (poté držet 5 min).
Duration syncRetryDelayForCount(int retryCount) {
  if (retryCount <= 1) return const Duration(seconds: 30);
  if (retryCount == 2) return const Duration(minutes: 2);
  return const Duration(minutes: 5);
}

DateTime syncNextRetryAt(int retryCountAfterFailure, DateTime from) {
  return from.add(syncRetryDelayForCount(retryCountAfterFailure));
}

bool syncIsDueForRetry(
    {required String status, DateTime? nextRetryAt, required DateTime now}) {
  if (status == 'conflict' || status == 'done' || status == 'sending') {
    return false;
  }
  if (status != 'pending' && status != 'failed') return false;
  if (nextRetryAt == null) return true;
  return !nextRetryAt.isAfter(now);
}

bool outboxIsDueForRetry(LocalOutboxData row, DateTime now) {
  return syncIsDueForRetry(
      status: row.status, nextRetryAt: row.nextRetryAt, now: now);
}

bool photoIsDueForRetry(LocalPhoto row, DateTime now) {
  return syncIsDueForRetry(
      status: row.status, nextRetryAt: row.nextRetryAt, now: now);
}

/// Indices in [pending] with no matching push result (T3 / S7).
List<int> pushResultGapIndices(int pendingLength, int resultsLength) {
  if (resultsLength >= pendingLength) return const [];
  return List.generate(
    pendingLength - resultsLength,
    (i) => resultsLength + i,
  );
}

Future<void> markOutboxSyncSuccess(AppDatabase db, String outboxId) async {
  await (db.update(db.localOutbox)..where((o) => o.id.equals(outboxId))).write(
    const LocalOutboxCompanion(
      status: Value('done'),
      retryCount: Value(0),
      lastError: Value(null),
      nextRetryAt: Value(null),
    ),
  );
}

Future<void> markOutboxSyncFailure(
  AppDatabase db,
  String outboxId, {
  required int currentRetryCount,
  required String error,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final nextCount = currentRetryCount + 1;
  await (db.update(db.localOutbox)..where((o) => o.id.equals(outboxId))).write(
    LocalOutboxCompanion(
      status: const Value('failed'),
      retryCount: Value(nextCount),
      lastError: Value(error),
      nextRetryAt: Value(syncNextRetryAt(nextCount, at)),
    ),
  );
}

Future<void> markPhotoSyncSuccess(AppDatabase db, String photoId,
    {String? serverPath}) async {
  await (db.update(db.localPhotos)..where((p) => p.id.equals(photoId))).write(
    LocalPhotosCompanion(
      status: const Value('done'),
      retryCount: const Value(0),
      lastError: const Value(null),
      nextRetryAt: const Value(null),
      serverPath: serverPath == null ? const Value.absent() : Value(serverPath),
    ),
  );
}

Future<void> markPhotoSyncFailure(
  AppDatabase db,
  String photoId, {
  required int currentRetryCount,
  required String error,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final nextCount = currentRetryCount + 1;
  await (db.update(db.localPhotos)..where((p) => p.id.equals(photoId))).write(
    LocalPhotosCompanion(
      status: const Value('failed'),
      retryCount: Value(nextCount),
      lastError: Value(error),
      nextRetryAt: Value(syncNextRetryAt(nextCount, at)),
    ),
  );
}

Future<bool> hasDueSyncWork(AppDatabase db, DateTime now) async {
  final outbox = await (db.select(db.localOutbox)
        ..where((o) => o.status.isIn(['pending', 'failed'])))
      .get();
  if (outbox.any((o) => outboxIsDueForRetry(o, now))) return true;

  final photos = await (db.select(db.localPhotos)
        ..where((p) => p.status.isIn(['pending', 'failed'])))
      .get();
  return photos.any((p) => photoIsDueForRetry(p, now));
}
