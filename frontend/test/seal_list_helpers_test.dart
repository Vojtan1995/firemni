import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/seal_list_helpers.dart';

void main() {
  group('compareSealsByUpdatedAt', () {
    test('sorts newest first', () {
      final list = [
        {'sealNumber': '1', 'updatedAt': '2025-01-01T10:00:00.000Z'},
        {'sealNumber': '2', 'updatedAt': '2025-06-01T10:00:00.000Z'},
        {'sealNumber': '3', 'updatedAt': '2025-03-01T10:00:00.000Z'},
      ];
      sortSealsByUpdatedAt(list);
      expect(list.map((e) => e['sealNumber']).toList(), ['2', '3', '1']);
    });
  });

  group('sealHasNoteForList', () {
    test('worker sees only internal note flag', () {
      expect(
        sealHasNoteForList(
          {'hasPublicNote': true, 'hasInternalNote': false},
          isWorker: true,
        ),
        isFalse,
      );
      expect(
        sealHasNoteForList(
          {'hasPublicNote': false, 'hasInternalNote': true},
          isWorker: true,
        ),
        isTrue,
      );
    });

    test('vedeni sees public or internal note', () {
      expect(
        sealHasNoteForList(
          {'hasPublicNote': true, 'hasInternalNote': false},
          isWorker: false,
        ),
        isTrue,
      );
    });
  });
}
