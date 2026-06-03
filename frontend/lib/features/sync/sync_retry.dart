import 'package:drift/drift.dart';

import '../../database/database.dart';
import 'sync_outbox_user.dart';

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

Future<void> markPhotoSyncSuccess(
  AppDatabase db,
  String photoId, {
  String? serverPath,
  String? serverPhotoId,
}) async {
  final row = await (db.select(db.localPhotos)
        ..where((p) => p.id.equals(photoId)))
      .getSingleOrNull();
  if (row == null) return;

  final resolvedServerPath = serverPath ?? row.serverPath;
  final targetId = serverPhotoId ?? photoId;

  if (serverPhotoId != null && serverPhotoId != photoId) {
    await db.transaction(() async {
      await (db.delete(db.localPhotos)..where((p) => p.id.equals(photoId)))
          .go();
      await db.into(db.localPhotos).insert(
            LocalPhotosCompanion.insert(
              id: targetId,
              sealId: row.sealId,
              localPath: row.localPath,
              serverPath: resolvedServerPath == null
                  ? const Value.absent()
                  : Value(resolvedServerPath),
              status: const Value('done'),
              createdAt: row.createdAt,
              retryCount: const Value(0),
              lastError: const Value(null),
              nextRetryAt: const Value(null),
            ),
          );
    });
    return;
  }

  await (db.update(db.localPhotos)..where((p) => p.id.equals(photoId))).write(
    LocalPhotosCompanion(
      status: const Value('done'),
      retryCount: const Value(0),
      lastError: const Value(null),
      nextRetryAt: const Value(null),
      serverPath: resolvedServerPath == null
          ? const Value.absent()
          : Value(resolvedServerPath),
    ),
  );
}

/// All photos waiting for upload (including blocked-by-seal and backoff).
Future<int> countUnsentPhotos(AppDatabase db) async {
  final photos = await (db.select(db.localPhotos)
        ..where((p) => p.status.isIn(['pending', 'failed'])))
      .get();
  return photos.length;
}

/// Pending/failed photos with seal number for SyncScreen.
Future<List<({LocalPhoto photo, String? sealNumber})>> loadUnsentPhotosWithSeal(
  AppDatabase db,
) async {
  final photos = await (db.select(db.localPhotos)
        ..where((p) => p.status.isIn(['pending', 'failed']))
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
      .get();
  final result = <({LocalPhoto photo, String? sealNumber})>[];
  for (final photo in photos) {
    final seal = await (db.select(db.localSeals)
          ..where((s) => s.id.equals(photo.sealId)))
        .getSingleOrNull();
    result.add((photo: photo, sealNumber: seal?.sealNumber));
  }
  return result;
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

/// Whether upload must wait until the seal is synced (T5 / P1).
bool isPhotoUploadBlockedBySeal(LocalSeal? seal) {
  return seal == null || !seal.isSynced || seal.syncConflict;
}

/// Count of outbox rows and photos ready for sync now (T4 / S3, T5 photos).
Future<int> countDueSyncItems(
  AppDatabase db,
  DateTime now, {
  String? userId,
}) async {
  final outbox = filterOutboxForUser(
    await (db.select(db.localOutbox)
          ..where((o) => o.status.isIn(['pending', 'failed'])))
        .get(),
    userId,
  );
  var count = outbox.where((o) => outboxIsDueForRetry(o, now)).length;

  final photos = await (db.select(db.localPhotos)
        ..where((p) => p.status.isIn(['pending', 'failed'])))
      .get();
  for (final photo in photos) {
    if (!photoIsDueForRetry(photo, now)) continue;
    final seal = await (db.select(db.localSeals)
          ..where((s) => s.id.equals(photo.sealId)))
        .getSingleOrNull();
    if (!isPhotoUploadBlockedBySeal(seal)) count++;
  }
  return count;
}

Future<bool> hasDueSyncWork(
  AppDatabase db,
  DateTime now, {
  String? userId,
}) async {
  return (await countDueSyncItems(db, now, userId: userId)) > 0;
}
