import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/core/permissions.dart';

void main() {
  test('worker permissions', () {
    expect(AppPermissions.has('worker', 'seal.create'), isTrue);
    expect(AppPermissions.has('worker', 'reports.view'), isFalse);
  });

  test('ucetni permissions', () {
    expect(AppPermissions.canAccessReports('ucetni'), isTrue);
    expect(AppPermissions.canManageJobs('ucetni'), isFalse);
  });

  test('vedeni permissions', () {
    expect(AppPermissions.canManageJobs('vedeni'), isTrue);
    expect(AppPermissions.canAccessTrash('vedeni'), isFalse);
  });

  test('admin permissions', () {
    expect(AppPermissions.canAccessTrash('admin'), isTrue);
  });
}
