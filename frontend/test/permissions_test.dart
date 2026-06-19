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

  test('ucetni role no longer exists', () {
    // Bývalá role účetní/administrativa byla zrušena – nemá žádná oprávnění.
    expect(AppPermissions.canAccessReports('ucetni'), isFalse);
    expect(AppPermissions.canChangeSealStatus('ucetni'), isFalse);
    expect(AppPermissions.has('ucetni', 'worksheet.invoice'), isFalse);
    expect(AppPermissions.roleLabel('ucetni'), 'ucetni');
  });

  test('vedeni permissions (incl. inherited from former ucetni)', () {
    expect(AppPermissions.canManageJobs('vedeni'), isTrue);
    expect(AppPermissions.canManagePriceList('vedeni'), isTrue);
    expect(AppPermissions.canAccessTrash('vedeni'), isFalse);
    expect(AppPermissions.canViewSealHistory('vedeni'), isTrue);
    expect(AppPermissions.canChangeSealStatus('vedeni'), isTrue);
    expect(AppPermissions.canManageFloorDrawings('vedeni'), isTrue);
    expect(AppPermissions.has('vedeni', 'worksheet.invoice'), isTrue);
  });

  test('admin permissions', () {
    expect(AppPermissions.canAccessTrash('admin'), isTrue);
    expect(AppPermissions.has('admin', 'photo.delete'), isFalse);
  });
}
