import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/seal_constants.dart';

void main() {
  test('dimensionPresetsForEntry returns EL.V. presets', () {
    expect(dimensionPresetsForEntry('EL.V.', 'žádná'), contains('Ø50'));
    expect(dimensionPresetsForEntry('EL.V.', 'žádná').length, 10);
  });

  test('PROSTUP uses OC presets by insulation', () {
    expect(dimensionPresetsForEntry('PROSTUP', 'nehořlavá'), contains('Ø20-100'));
    expect(dimensionPresetsForEntry('PROSTUP', 'hořlavá'), contains('Ø40'));
  });

  test('OCEL has no chip presets', () {
    expect(dimensionPresetsForEntry('OCEL', 'žádná'), isEmpty);
  });

  test('defaultDimensionForEntry', () {
    expect(defaultDimensionForEntry('PVC', 'žádná'), 'Ø40');
    expect(defaultDimensionForEntry('OCEL', 'žádná'), '');
  });
}
