import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/core/desktop_esc_handler.dart';

void main() {
  test('EscapeIntent is defined', () {
    expect(const EscapeIntent(), isA<EscapeIntent>());
  });

  test('DesktopEscScope.enabled is false on test VM (not desktop target)', () {
    // flutter test runs on VM — ESC handler stays disabled (Android-like).
    expect(DesktopEscScope.enabled, isFalse);
  });
}
