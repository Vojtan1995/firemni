import 'package:dio/dio.dart';

/// Extracts a human-readable error message from a thrown error.
///
/// The backend error middleware serializes API errors as JSON
/// `{ error, code }` — the key is `error`, NOT `message`. This helper reads
/// `error` first, then falls back to `message` (for any legacy responses), a
/// plain-string body, and finally [fallback].
String apiErrorMessage(Object e, {String fallback = 'Chyba'}) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = (data['error'] ?? data['message'])?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
    } else if (data is String && data.isNotEmpty) {
      return data;
    }
  }
  return fallback;
}
