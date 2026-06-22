import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/worksheets/soupisy_screen.dart';

void main() {
  test('SoupisyScreen merges worksheets hub', () {
    const screen = SoupisyScreen();
    expect(screen, isA<ConsumerStatefulWidget>());
  });

  test('SoupisyScreen creates worksheets from report filters', () {
    final source =
        File('lib/features/worksheets/soupisy_screen.dart').readAsStringSync();
    expect(source, contains('_createWorksheetFromFilters'));
    expect(source, isNot(contains("label: 'Nový soupis'")));
  });
}
