import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/features/sync/sync_conflict.dart';

void main() {
  group('pullSealSyncFlags', () {
    test('server defaults when no local row and no outbox', () {
      final flags = pullSealSyncFlags(existing: null, hasActiveOutbox: false);
      expect(flags.isSynced, isTrue);
      expect(flags.syncConflict, isFalse);
    });

    test('preserves unsynced local row', () {
      final existing = LocalSeal(
        id: 'seal-1',
        jobId: 'j',
        floorId: 'f',
        sealNumber: '1',
        system: 'S',
        construction: 'C',
        location: 'L',
        fireRating: '60',
        note: null,
        status: 'draft',
        version: 1,
        isSynced: false,
        syncConflict: false,
        markerPlacementPending: false,
        jsonPayload: null,
        deletedAt: null,
        updatedAt: DateTime.now(),
      );
      final flags = pullSealSyncFlags(existing: existing, hasActiveOutbox: false);
      expect(flags.isSynced, isFalse);
      expect(flags.syncConflict, isFalse);
    });

    test('preserves syncConflict when active outbox', () {
      final existing = LocalSeal(
        id: 'seal-1',
        jobId: 'j',
        floorId: 'f',
        sealNumber: '1',
        system: 'S',
        construction: 'C',
        location: 'L',
        fireRating: '60',
        note: null,
        status: 'draft',
        version: 1,
        isSynced: true,
        syncConflict: true,
        markerPlacementPending: false,
        jsonPayload: null,
        deletedAt: null,
        updatedAt: DateTime.now(),
      );
      final flags = pullSealSyncFlags(existing: existing, hasActiveOutbox: true);
      expect(flags.syncConflict, isTrue);
    });
  });
}
