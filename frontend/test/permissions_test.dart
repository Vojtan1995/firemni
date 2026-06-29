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
    // Worker nesmí mazat fotky.
    expect(AppPermissions.has('worker', 'photo.delete'), isFalse);
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
    // Vedení má kompletní práva k soupisům včetně odeslání a smí mazat fotky.
    expect(AppPermissions.canSubmitWorksheet('vedeni'), isTrue);
    expect(AppPermissions.has('vedeni', 'photo.delete'), isTrue);
  });

  test('admin permissions', () {
    expect(AppPermissions.canAccessTrash('admin'), isTrue);
    expect(AppPermissions.has('admin', 'photo.delete'), isTrue);
  });

  test('frontend matrix mirrors backend permission roles', () {
    const expected = <String, List<String>>{
      'seal.create': ['worker', 'vedeni', 'admin'],
      'seal.edit': ['worker', 'vedeni', 'admin'],
      'seal.status': ['vedeni', 'admin'],
      'seal.delete': ['vedeni', 'admin'],
      'seal.restore': ['admin'],
      'seal.history': ['vedeni', 'admin'],
      'seal.override_locked': ['vedeni', 'admin'],
      'photo.upload': ['worker', 'vedeni', 'admin'],
      'photo.delete': ['vedeni', 'admin'],
      'job.manage': ['vedeni', 'admin'],
      'floor.manage': ['vedeni', 'admin'],
      'floor.drawing.manage': ['vedeni', 'admin'],
      'user.manage': ['vedeni', 'admin'],
      'reports.view': ['worker', 'vedeni', 'admin'],
      'reports.export': ['worker', 'vedeni', 'admin'],
      'priceList.view': ['worker', 'vedeni', 'admin'],
      'priceList.manage': ['vedeni', 'admin'],
      'logs.view': ['vedeni', 'admin'],
      'admin.trash': ['admin'],
      'admin.backup': ['admin'],
      'worksheet.create': ['worker', 'vedeni', 'admin'],
      'worksheet.view': ['worker', 'vedeni', 'admin'],
      'worksheet.delete': ['worker', 'vedeni', 'admin'],
      'worksheet.submit': ['worker', 'vedeni', 'admin'],
      'worksheet.review': ['vedeni', 'admin'],
      'worksheet.invoice': ['vedeni', 'admin'],
      'worksheet.archive': ['vedeni', 'admin'],
      'stats.view': ['worker', 'vedeni', 'admin'],
      'repair.create': ['worker', 'vedeni', 'admin'],
      'repair.view': ['worker', 'vedeni', 'admin'],
      'repair.export': ['vedeni', 'admin'],
    };
    const roles = ['worker', 'vedeni', 'admin'];

    for (final entry in expected.entries) {
      for (final role in roles) {
        expect(
          AppPermissions.has(role, entry.key),
          entry.value.contains(role),
          reason: '$role / ${entry.key}',
        );
      }
    }
  });
}
