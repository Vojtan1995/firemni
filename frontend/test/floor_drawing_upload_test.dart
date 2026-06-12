import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/floor_plan/floor_drawing_upload.dart';

void main() {
  group('shouldWarnLowResolution', () {
    test('warns for PNG below threshold', () {
      expect(shouldWarnLowResolution(2499, 'plan.png'), isTrue);
    });

    test('warns for JPEG below threshold', () {
      expect(shouldWarnLowResolution(1000, 'scan.JPG'), isTrue);
    });

    test('does not warn at threshold', () {
      expect(shouldWarnLowResolution(2500, 'plan.png'), isFalse);
    });

    test('does not warn for PDF', () {
      expect(shouldWarnLowResolution(100, 'plan.pdf'), isFalse);
    });

    test('does not warn for webp', () {
      expect(shouldWarnLowResolution(100, 'plan.webp'), isFalse);
    });
  });
}
