import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/seal_form_loader.dart';

void main() {
  test('entryDraftsFromSealMap parses entries (T11)', () {
    final drafts = entryDraftsFromSealMap({
      'entries': [
        {
          'entryType': 'PVC',
          'dimension': '110',
          'quantity': 2,
          'insulation': 'žádná',
          'materials': [
            {'material': 'INTU FR'},
          ],
        },
      ],
    });
    expect(drafts.length, 1);
    expect(drafts.first.entryType, 'PVC');
    expect(drafts.first.materials, ['INTU FR']);
  });
}
