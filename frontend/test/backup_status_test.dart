import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/logs/backup_status.dart';

void main() {
  test('parses healthy backup status summary', () {
    final summary = BackupStatusSummary.fromJson({
      'ok': true,
      'checkedAt': '2026-07-01T12:00:00Z',
      'checks': [
        {
          'type': 'db',
          'label': 'DB záloha',
          'ok': true,
          'status': 'ok',
          'maxAgeHours': 30,
          'latestSuccessAgeHours': 2.4,
          'githubRunUrl': 'https://github.com/example/repo/actions/runs/1',
          'bytes': '1048576',
          'latestSuccess': {
            'finishedAt': '2026-07-01T10:00:00Z',
          },
        },
      ],
    });

    expect(summary.ok, isTrue);
    expect(summary.checkedAt, isNotNull);
    expect(summary.checks, hasLength(1));
    expect(summary.checks.single.title, 'DB záloha');
    expect(summary.checks.single.statusLabel, 'OK');
    expect(summary.checks.single.ageLabel, '2 h');
    expect(summary.checks.single.sizeLabel, '1.0 MB');
  });

  test('parses failed, stale and missing backup states', () {
    final summary = BackupStatusSummary.fromJson({
      'ok': false,
      'checks': [
        {
          'type': 'db',
          'ok': false,
          'status': 'failed',
          'maxAgeHours': 30,
          'errorMessage': 'pg_dump failed',
        },
        {
          'type': 'object',
          'ok': false,
          'status': 'stale',
          'maxAgeHours': 30,
          'latestSuccessAgeHours': 54,
          'objectCount': 12,
        },
        {
          'type': 'restore_test',
          'ok': false,
          'status': 'missing',
          'maxAgeHours': 192,
        },
      ],
    });

    expect(summary.ok, isFalse);
    expect(summary.checks.map((c) => c.statusLabel), [
      'Selhalo',
      'Zastaralé',
      'Chybí',
    ]);
    expect(summary.checks[1].title, 'Fotky/výkresy');
    expect(summary.checks[1].ageLabel, '2 d');
    expect(summary.checks[1].objectCount, 12);
    expect(summary.checks[2].ageLabel, 'bez úspěšného běhu');
  });
}
