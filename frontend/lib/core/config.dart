import 'package:flutter/foundation.dart';

class AppConfig {
  /// Povinné v release buildu: `--dart-define=API_BASE_URL=https://api.example.com`
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Debug APK na fyzickém zařízení ve stejné Wi‑Fi → backend na PC.
  static const String _debugLanApiBaseUrl = 'http://192.168.1.105:3000';

  @visibleForTesting
  static String resolveApiBaseUrl({
    required String envApiBaseUrl,
    required bool debugMode,
  }) {
    if (envApiBaseUrl.isNotEmpty) return envApiBaseUrl;
    if (debugMode) return _debugLanApiBaseUrl;
    throw StateError(
      'Release build vyžaduje --dart-define=API_BASE_URL=<url backendu>',
    );
  }

  static String get apiBaseUrl =>
      resolveApiBaseUrl(envApiBaseUrl: _envApiBaseUrl, debugMode: kDebugMode);
}
