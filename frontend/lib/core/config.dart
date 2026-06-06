import 'package:flutter/foundation.dart';

class AppConfig {
  /// Volitelné přepsání při buildu: `--dart-define=API_BASE_URL=...`
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Release / výchozí (beze změny – produkce se nastavuje až přes dart-define).
  static const String _releaseDefaultApiBaseUrl = 'http://localhost:3000';

  /// Debug APK na fyzickém zařízení ve stejné Wi‑Fi → backend na PC.
  static const String _debugLanApiBaseUrl = 'http://192.168.1.110:3000';

  static String get apiBaseUrl {
    if (_envApiBaseUrl.isNotEmpty) return _envApiBaseUrl;
    if (kDebugMode) return _debugLanApiBaseUrl;
    return _releaseDefaultApiBaseUrl;
  }
}
