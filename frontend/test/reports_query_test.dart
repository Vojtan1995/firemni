import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/reports/reports_query.dart';

void main() {
  test('buildReportsQueryParams includes all filters (T9)', () {
    final params = buildReportsQueryParams(
      jobId: 'job-1',
      status: 'draft',
      workerId: 'user-1',
      floorId: 'floor-1',
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 31),
    );
    expect(params['jobId'], 'job-1');
    expect(params['status'], 'draft');
    expect(params['workerId'], 'user-1');
    expect(params['floorId'], 'floor-1');
    expect(params['from'], '2026-01-01');
    expect(params['to'], '2026-01-31');
  });

  test('buildReportsQueryParams omits empty values', () {
    expect(buildReportsQueryParams(), isEmpty);
  });
}
