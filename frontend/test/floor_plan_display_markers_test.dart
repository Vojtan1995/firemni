import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/floor_plan_screen.dart';

void main() {
  final floorSeals = [
    {
      'id': 'a',
      'sealNumber': '10',
      'status': 'draft',
      'createdById': 'u1',
    },
    {
      'id': 'b',
      'sealNumber': '20',
      'status': 'checked',
      'createdById': 'u2',
    },
  ];

  test('adds pending marker for new placement', () {
    final markers = floorPlanDisplayMarkers(
      visibleMarkers: const [],
      floorSeals: floorSeals,
      placingSealId: 'a',
      pendingX: 0.25,
      pendingY: 0.75,
    );

    expect(markers, hasLength(1));
    expect(markers.single['sealId'], 'a');
    expect(markers.single['sealNumber'], '10');
    expect(markers.single['x'], 0.25);
    expect(markers.single['y'], 0.75);
    expect(markers.single['pending'], isTrue);
  });

  test('pending move replaces existing marker', () {
    final markers = floorPlanDisplayMarkers(
      visibleMarkers: const [
        {
          'sealId': 'a',
          'sealNumber': '10',
          'x': 0.1,
          'y': 0.2,
          'status': 'draft',
        },
      ],
      floorSeals: floorSeals,
      movingSealId: 'a',
      pendingX: 0.8,
      pendingY: 0.9,
    );

    expect(markers, hasLength(1));
    expect(markers.single['sealId'], 'a');
    expect(markers.single['x'], 0.8);
    expect(markers.single['y'], 0.9);
    expect(markers.single['pending'], isTrue);
  });

  test('pending marker remains visible when filter hides normal markers', () {
    final markers = floorPlanDisplayMarkers(
      visibleMarkers: const [],
      floorSeals: floorSeals,
      movingSealId: 'b',
      pendingX: 0.4,
      pendingY: 0.6,
    );

    expect(markers, hasLength(1));
    expect(markers.single['sealId'], 'b');
    expect(markers.single['sealNumber'], '20');
    expect(markers.single['status'], 'checked');
    expect(markers.single['pending'], isTrue);
  });
}
