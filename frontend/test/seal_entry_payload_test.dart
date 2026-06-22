import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/seal_constants.dart';
import 'package:ucpavky/features/seals/seal_form_loader.dart';

void main() {
  test('sealEntriesWithSharedMaterials copies first entry materials (T8)', () {
    final entries = sealEntriesWithSharedMaterials([
      {
        'entryType': 'EL.V.',
        'dimension': '20',
        'quantity': 1,
        'insulation': 'žádná',
        'materials': ['INTU FR', 'WRAP'],
      },
      {
        'entryType': 'PVC',
        'dimension': '110',
        'quantity': 2,
        'insulation': 'žádná',
        'materials': <String>[],
      },
    ]);

    expect(entries.length, 2);
    expect(entries[0]['materials'], ['INTU FR', 'WRAP']);
    expect(entries[1]['materials'], ['INTU FR', 'WRAP']);
  });

  test('new seal entry draft starts without selected values', () {
    final draft = SealEntryDraftData();
    expect(draft.entryType, '');
    expect(draft.dimension, '');
    expect(draft.insulation, '');
    expect(draft.materials, isEmpty);
  });
}
