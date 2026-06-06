import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/core/permissions.dart';

void main() {
  test('worker permissions', () {
    expect(AppPermissions.has('worker', 'seal.create'), isTrue);
    expect(AppPermissions.has('worker', 'reports.view'), isTrue);
    expect(AppPermissions.has('worker', 'worksheet.create'), isTrue);
    expect(AppPermissions.canViewStats('worker'), isTrue);
    expect(AppPermissions.canManageJobs('worker'), isFalse);
    expect(AppPermissions.canViewSealHistory('worker'), isFalse);
  });

  test('ucetni permissions', () {
    expect(AppPermissions.canAccessReports('ucetni'), isTrue);
    expect(AppPermissions.canManageJobs('ucetni'), isFalse);
    expect(AppPermissions.canChangeSealStatus('ucetni'), isTrue);
    expect(AppPermissions.has('ucetni', 'seal.edit'), isFalse);
    expect(AppPermissions.has('ucetni', 'worksheet.invoice'), isTrue);
    expect(AppPermissions.roleLabel('ucetni'), 'Administrativa');
  });

  test('vedeni permissions', () {
    expect(AppPermissions.canManageJobs('vedeni'), isTrue);
    expect(AppPermissions.canAccessTrash('vedeni'), isFalse);
    expect(AppPermissions.canViewSealHistory('vedeni'), isTrue);
  });

  test('admin permissions', () {
    expect(AppPermissions.canAccessTrash('admin'), isTrue);
    expect(AppPermissions.has('admin', 'photo.delete'), isFalse);
  });
}
