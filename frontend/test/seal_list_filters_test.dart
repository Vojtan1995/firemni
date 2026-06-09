import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/seal_list_filters.dart';

void main() {
  test('filters no_photo and pending_sync', () {
    final seals = [
      {
        'photoCount': 0,
        'status': 'draft',
        'isSynced': false,
      },
      {
        'photoCount': 2,
        'status': 'draft',
        'isSynced': true,
      },
    ];

    final noPhoto = applySealListFilters(
      seals,
      filters: {SealProblemFilter.noPhoto},
      isWorker: true,
    );
    expect(noPhoto.length, 1);
    expect(noPhoto.first['photoCount'], 0);

    final pending = applySealListFilters(
      seals,
      filters: {SealProblemFilter.pendingSync},
      isWorker: true,
    );
    expect(pending.length, 1);
    expect(pending.first['isSynced'], false);
  });
}
