import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/reports/export_service.dart';

void main() {
  group('normalizeExportBytes', () {
    test('accepts Uint8List', () {
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
      expect(normalizeExportBytes(bytes, exportLabel: 'PDF'), bytes);
    });

    test('accepts List<int>', () {
      final bytes = normalizeExportBytes(
        [0x25, 0x50, 0x44, 0x46],
        exportLabel: 'PDF',
      );
      expect(bytes, Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));
    });

    test('rejects null', () {
      expect(
        () => normalizeExportBytes(null, exportLabel: 'PDF'),
        throwsStateError,
      );
    });

    test('rejects empty bytes', () {
      expect(
        () => normalizeExportBytes(Uint8List(0), exportLabel: 'PDF'),
        throwsStateError,
      );
    });

    test('rejects unsupported type', () {
      expect(
        () => normalizeExportBytes('not bytes', exportLabel: 'CSV'),
        throwsStateError,
      );
    });
  });

  group('saveFileRequiresBytes', () {
    test('returns bool without throwing', () {
      expect(saveFileRequiresBytes(), isA<bool>());
    });
  });
}
