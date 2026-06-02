import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/sync/sync_outbox_user.dart';
import 'package:ucpavky/features/sync/sync_retry.dart';

void main() {
  test('outboxBelongsToUser matches userId only (T6)', () {
    final row = LocalOutboxData(
      id: '1',
      mutationId: 'm',
      userId: 'user-a',
      deviceId: 'd',
      entityType: 'seal',
      operation: 'create',
      payload: '{}',
      baseVersion: null,
      status: 'pending',
      conflictMessage: null,
      dismissedAt: null,
      createdAt: DateTime.now(),
      nextRetryAt: null,
      retryCount: 0,
      lastError: null,
    );
    expect(outboxBelongsToUser(row, 'user-a'), isTrue);
    expect(outboxBelongsToUser(row, 'user-b'), isFalse);
    expect(outboxBelongsToUser(row, null), isFalse);
    expect(
      outboxBelongsToUser(
        LocalOutboxData(
          id: '2',
          mutationId: 'm2',
          userId: null,
          deviceId: 'd',
          entityType: 'seal',
          operation: 'create',
          payload: '{}',
          baseVersion: null,
          status: 'pending',
          conflictMessage: null,
          dismissedAt: null,
          createdAt: DateTime.now(),
          nextRetryAt: null,
          retryCount: 0,
          lastError: null,
        ),
        'user-a',
      ),
      isFalse,
    );
  });

  test('countDueSyncItems ignores other users outbox (T6)', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final now = DateTime(2026, 6, 1);

    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-a',
            mutationId: 'mut-a',
            userId: const Value('user-a'),
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.localOutbox).insert(
          LocalOutboxCompanion.insert(
            id: 'out-b',
            mutationId: 'mut-b',
            userId: const Value('user-b'),
            deviceId: 'dev',
            entityType: 'seal',
            operation: 'create',
            payload: '{}',
            createdAt: now,
          ),
        );

    expect(await countDueSyncItems(db, now, userId: 'user-a'), 1);
    expect(await countDueSyncItems(db, now, userId: 'user-b'), 1);
  });
}
