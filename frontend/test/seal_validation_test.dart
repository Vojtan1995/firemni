import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/seal_validation.dart';

void main() {
  test('validateSealForChecked detects missing photo', () {
    final issues = validateSealForChecked({
      'system': 'S',
      'construction': 'C',
      'location': 'L',
      'fireRating': 'EI',
      'photos': [],
      'entries': [
        {
          'entryType': 'EL.V.',
          'dimension': '10',
          'quantity': 1,
          'materials': [
            {'material': 'Pena'},
          ],
        },
      ],
    });
    expect(issues.any((i) => i.field == 'photos'), isTrue);
  });
}
