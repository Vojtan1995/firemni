import 'package:dio/dio.dart';

String jobNumberErrorMessage(DioException error) {
  final status = error.response?.statusCode;
  final data = error.response?.data;
  final serverMessage = data is Map ? data['error']?.toString().trim() : null;

  if (status == 403) {
    return 'K této stavbě nemáte přístup';
  }
  if (status == 404) {
    final normalized = serverMessage?.toLowerCase() ?? '';
    if (normalized.contains('aktivní') ||
        normalized.contains('archiv') ||
        normalized.contains('dokonč')) {
      return serverMessage!;
    }
    return 'Stavba s tímto číslem neexistuje';
  }
  if (status == 429) {
    return 'Příliš mnoho pokusů. Zkuste to znovu později.';
  }
  if (status != null && status >= 500) {
    return 'Server je dočasně nedostupný';
  }
  if (error.response == null) {
    return 'Nepodařilo se připojit k serveru';
  }
  if (serverMessage != null && serverMessage.isNotEmpty) {
    return serverMessage;
  }
  return 'Stavbu se nepodařilo otevřít';
}

bool shouldTryOfflineJobCache(DioException error) {
  final status = error.response?.statusCode;
  return error.response == null || (status != null && status >= 500);
}
