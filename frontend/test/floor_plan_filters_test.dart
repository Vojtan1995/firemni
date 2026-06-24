import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/floor_plan/floor_plan_filters.dart';

void main() {
  final floorSeals = [
    {'id': 'a', 'sealNumber': '10', 'createdById': 'u1', 'createdByName': 'Jan'},
    {'id': 'b', 'sealNumber': '20', 'createdById': 'u2', 'createdByName': 'Petr'},
    {'id': 'c', 'sealNumber': '30', 'createdById': 'u1', 'createdByName': 'Jan'},
  ];

  group('FloorPlanFilterState.matchesMarker', () {
    test('selected shows only chosen seals', () {
      const filter = FloorPlanFilterState(
        mode: FloorPlanMarkerFilter.selected,
        selectedSealIds: {'a'},
      );
      expect(
        filter.matchesMarker(
          marker: {'sealId': 'a', 'status': 'draft'},
          placedSealIds: {'a'},
          currentUserId: 'u1',
          createdById: 'u1',
        ),
        isTrue,
      );
      expect(
        filter.matchesMarker(
          marker: {'sealId': 'b', 'status': 'draft'},
          placedSealIds: {'b'},
          currentUserId: 'u1',
          createdById: 'u2',
        ),
        isFalse,
      );
    });

    test('byWorker requires workerId', () {
      const noWorker = FloorPlanFilterState(mode: FloorPlanMarkerFilter.byWorker);
      expect(
        noWorker.matchesMarker(
          marker: {'sealId': 'a', 'status': 'draft'},
          placedSealIds: {'a'},
          currentUserId: 'u1',
          createdById: 'u1',
        ),
        isFalse,
      );

      const withWorker = FloorPlanFilterState(
        mode: FloorPlanMarkerFilter.byWorker,
        workerId: 'u1',
      );
      expect(
        withWorker.matchesMarker(
          marker: {'sealId': 'a', 'status': 'draft'},
          placedSealIds: {'a'},
          currentUserId: 'x',
          createdById: 'u1',
        ),
        isTrue,
      );
    });

  });

  group('helpers', () {
    test('sealIdsFromNumbers parses comma-separated input', () {
      final ids = FloorPlanFilterState.sealIdsFromNumbers('10, 20', floorSeals);
      expect(ids, {'a', 'b'});
    });

    test('workersFromSeals returns unique sorted workers', () {
      final workers = FloorPlanFilterState.workersFromSeals(floorSeals);
      expect(workers.length, 2);
      expect(workers.first.name, 'Jan');
    });

    test('toExportQueryParams maps filters to API query', () {
      expect(
        const FloorPlanFilterState().toExportQueryParams(currentUserId: 'u1'),
        {},
      );
      expect(
        const FloorPlanFilterState(mode: FloorPlanMarkerFilter.mine)
            .toExportQueryParams(currentUserId: 'u1'),
        {'workerId': 'u1'},
      );
      expect(
        const FloorPlanFilterState(
          mode: FloorPlanMarkerFilter.byWorker,
          workerId: 'u2',
        ).toExportQueryParams(currentUserId: 'u1'),
        {'workerId': 'u2'},
      );
      expect(
        const FloorPlanFilterState(
          mode: FloorPlanMarkerFilter.selected,
          selectedSealIds: {'a', 'b'},
        ).toExportQueryParams(currentUserId: 'u1'),
        {'sealIds': 'a,b'},
      );
      expect(
        const FloorPlanFilterState(
          mode: FloorPlanMarkerFilter.byStatus,
          status: 'returned',
        ).toExportQueryParams(currentUserId: 'u1'),
        {'status': 'returned'},
      );
      expect(
        const FloorPlanFilterState(mode: FloorPlanMarkerFilter.draftOnly)
            .toExportQueryParams(currentUserId: 'u1'),
        {'status': 'draft'},
      );
      expect(
        const FloorPlanFilterState(mode: FloorPlanMarkerFilter.unplacedOnly)
            .toExportQueryParams(currentUserId: 'u1'),
        isNull,
      );
    });

    test('description includes worker name and selected numbers', () {
      const workerFilter = FloorPlanFilterState(
        mode: FloorPlanMarkerFilter.byWorker,
        workerId: 'u1',
        workerName: 'Jan Novák',
      );
      expect(workerFilter.description, contains('Jan Novák'));

      const selectedFilter = FloorPlanFilterState(
        mode: FloorPlanMarkerFilter.selected,
        selectedSealIds: {'a', 'b'},
        selectedSealNumbers: {'10', '20'},
      );
      expect(selectedFilter.description, contains('10'));
      expect(selectedFilter.description, contains('2'));
    });
  });
}
