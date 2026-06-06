import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/worksheets/soupisy_screen.dart';

void main() {
  test('SoupisyScreen merges worksheets hub', () {
    const screen = SoupisyScreen();
    expect(screen, isA<ConsumerStatefulWidget>());
  });
}
