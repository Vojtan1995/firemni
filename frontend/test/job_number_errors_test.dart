import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/jobs/job_number_errors.dart';

DioException _error({
  int? status,
  Map<String, dynamic>? data,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final request = RequestOptions(path: '/api/jobs/by-number/12345678');
  return DioException(
    requestOptions: request,
    type: type,
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: request,
            statusCode: status,
            data: data,
          ),
  );
}

void main() {
  group('job number error handling', () {
    test('distinguishes missing and inactive jobs', () {
      expect(
        jobNumberErrorMessage(_error(
          status: 404,
          data: {'error': 'Stavba s tímto číslem neexistuje'},
        )),
        'Stavba s tímto číslem neexistuje',
      );
      expect(
        jobNumberErrorMessage(_error(
          status: 404,
          data: {'error': 'Stavba není aktivní'},
        )),
        'Stavba není aktivní',
      );
    });

    test('distinguishes forbidden, rate limited and server failures', () {
      expect(
        jobNumberErrorMessage(_error(status: 403)),
        'K této stavbě nemáte přístup',
      );
      expect(
        jobNumberErrorMessage(_error(status: 429)),
        'Příliš mnoho pokusů. Zkuste to znovu později.',
      );
      expect(
        jobNumberErrorMessage(_error(status: 503)),
        'Server je dočasně nedostupný',
      );
    });

    test('uses offline cache only for connection and server failures', () {
      final connection = _error(
        type: DioExceptionType.connectionError,
      );
      expect(
        jobNumberErrorMessage(connection),
        'Nepodařilo se připojit k serveru',
      );
      expect(shouldTryOfflineJobCache(connection), isTrue);
      expect(shouldTryOfflineJobCache(_error(status: 503)), isTrue);
      expect(shouldTryOfflineJobCache(_error(status: 403)), isFalse);
      expect(shouldTryOfflineJobCache(_error(status: 404)), isFalse);
      expect(shouldTryOfflineJobCache(_error(status: 429)), isFalse);
    });
  });
}
