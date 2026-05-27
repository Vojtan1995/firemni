import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ucpavky/database/database.dart';

const _apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3000');

Future<Map<String, dynamic>> _jsonRequest(
  String method,
  String path, {
  Map<String, String>? headers,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$_apiBase$path');
    late HttpClientRequest req;
    switch (method) {
      case 'GET':
        req = await client.getUrl(uri);
      case 'POST':
        req = await client.postUrl(uri);
      default:
        throw UnsupportedError(method);
    }
    headers?.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}: $text', uri: uri);
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<List<dynamic>> _jsonListRequest(String path, {Map<String, String>? headers}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$_apiBase$path');
    final req = await client.getUrl(uri);
    headers?.forEach(req.headers.set);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}: $text', uri: uri);
    }
    return jsonDecode(text) as List<dynamic>;
  } finally {
    client.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Frontend runtime verification (real backend)', () {
    late String token;
    late String jobId;
    late String floorId;

    test('health endpoint is reachable', () async {
      final data = await _jsonRequest('GET', '/health');
      expect(data['status'], 'ok');
    });

    test('login returns token for seed user worker1', () async {
      final data = await _jsonRequest('POST', '/api/auth/login', body: {
        'username': 'worker1',
        'pin': '1234',
      });
      expect(data['token'], isNotNull);
      expect((data['user'] as Map)['role'], 'worker');
      token = data['token'] as String;
    });

    test('job by number 12345678 loads with floors', () async {
      final data = await _jsonRequest('GET', '/api/jobs/by-number/12345678', headers: {
        'Authorization': 'Bearer $token',
      });
      expect(data['projectNumber'], '12345678');
      final floors = data['floors'] as List;
      expect(floors.length, greaterThanOrEqualTo(1));
      jobId = data['id'] as String;
      floorId = (floors.first as Map)['id'] as String;
    });

    test('floors endpoint returns list for job', () async {
      final floors = await _jsonListRequest('/api/jobs/$jobId/floors', headers: {
        'Authorization': 'Bearer $token',
      });
      expect(floors, isNotEmpty);
    });

    test('seals list for floor returns array', () async {
      final seals = await _jsonListRequest('/api/seals/floors/$floorId/seals', headers: {
        'Authorization': 'Bearer $token',
      });
      expect(seals, isA<List>());
    });

    test('management can download reports CSV export', () async {
      final data = await _jsonRequest('POST', '/api/auth/login', body: {
        'username': 'vedeni',
        'pin': '1234',
      });
      final mgmtToken = data['token'] as String;
      expect((data['user'] as Map)['role'], 'management');

      final client = HttpClient();
      try {
        final uri = Uri.parse('$_apiBase/api/reports/export/csv');
        final req = await client.getUrl(uri);
        req.headers.set('Authorization', 'Bearer $mgmtToken');
        final res = await req.close();
        final bytes = await res.fold<List<int>>(
          <int>[],
          (prev, chunk) => prev..addAll(chunk),
        );
        expect(res.statusCode, 200);
        expect(bytes, isNotEmpty);
        final hasUtf8Bom = bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF;
        expect(hasUtf8Bom, isTrue);
        final text = utf8.decode(bytes);
        expect(text, contains('Stavba'));
      } finally {
        client.close();
      }
    });

    test('worker cannot access reports CSV export', () async {
      final login = await _jsonRequest('POST', '/api/auth/login', body: {
        'username': 'worker1',
        'pin': '1234',
      });
      final workerToken = login['token'] as String;

      final client = HttpClient();
      try {
        final uri = Uri.parse('$_apiBase/api/reports/export/csv');
        final req = await client.getUrl(uri);
        req.headers.set('Authorization', 'Bearer $workerToken');
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        expect(res.statusCode, 403);
        expect(text, contains('FORBIDDEN'));
      } finally {
        client.close();
      }
    });

    test('Drift SQLite initializes and outbox queue works', () async {
      final db = AppDatabase.forTesting();
      addTearDown(() => db.close());

      await db.into(db.localJobs).insertOnConflictUpdate(
        LocalJobsCompanion.insert(
          id: 'test-job',
          projectNumber: '12345678',
          name: 'Test',
          updatedAt: DateTime.now(),
        ),
      );

      final jobs = await db.select(db.localJobs).get();
      expect(jobs.length, 1);

      await db.into(db.localOutbox).insert(
        LocalOutboxCompanion.insert(
          id: 'out-1',
          mutationId: 'mut-1',
          deviceId: 'dev-1',
          entityType: 'seal',
          operation: 'create',
          payload: jsonEncode({'test': true}),
          createdAt: DateTime.now(),
        ),
      );

      final outbox = await db.select(db.localOutbox).get();
      expect(outbox.length, 1);
      expect(outbox.first.status, 'pending');
    });
  });
}
