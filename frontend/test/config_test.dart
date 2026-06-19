import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/core/config.dart';

void main() {
  group('AppConfig', () {
    test('uses env URL when provided', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          envApiBaseUrl: 'https://api.example.com',
          debugMode: false,
        ),
        'https://api.example.com',
      );
    });

    test('uses LAN default in debug when env is empty', () {
      expect(
        AppConfig.resolveApiBaseUrl(envApiBaseUrl: '', debugMode: true),
        AppConfig.debugLanApiBaseUrl,
      );
    });

    test('throws in release when API_BASE_URL is missing', () {
      expect(
        () => AppConfig.resolveApiBaseUrl(envApiBaseUrl: '', debugMode: false),
        throwsStateError,
      );
    });
  });
}
