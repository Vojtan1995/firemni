/// Central permission matrix — mirrors backend `permissions.ts`.
class AppPermissions {
  static const _matrix = <String, List<String>>{
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

  static bool has(String? role, String permission) {
    if (role == null) return false;
    return _matrix[permission]?.contains(role) ?? false;
  }

  static bool canAccessReports(String? role) => has(role, 'reports.view');

  static bool canViewPriceList(String? role) => has(role, 'priceList.view');

  static bool canManagePriceList(String? role) => has(role, 'priceList.manage');

  static bool canManageJobs(String? role) => has(role, 'job.manage');

  static bool canManageFloorDrawings(String? role) =>
      has(role, 'floor.drawing.manage');

  static bool canManageUsers(String? role) => has(role, 'user.manage');

  static bool canViewLogs(String? role) => has(role, 'logs.view');

  static bool canAccessTrash(String? role) => has(role, 'admin.trash');

  static bool canChangeSealStatus(String? role) => has(role, 'seal.status');

  static bool canViewSealHistory(String? role) => has(role, 'seal.history');

  static bool canOverrideLockedSeal(String? role) =>
      has(role, 'seal.override_locked');

  static bool canAccessAdminBackup(String? role) => has(role, 'admin.backup');

  static bool canViewStats(String? role) => has(role, 'stats.view');

  static bool canManageWorksheets(String? role) =>
      has(role, 'worksheet.create') || has(role, 'worksheet.view');

  static bool canCreateWorksheet(String? role) => has(role, 'worksheet.create');

  static bool canSubmitWorksheet(String? role) => has(role, 'worksheet.submit');

  static bool canReviewWorksheet(String? role) => has(role, 'worksheet.review');

  /// Mazat lze jen draft (vynuceno UI + backendem); worker je navíc omezen na
  /// soupisy, jichž je účastníkem (backend assertWorksheetAccess).
  static bool canDeleteWorksheet(String? role) => has(role, 'worksheet.delete');

  static bool canInvoiceWorksheet(String? role) =>
      has(role, 'worksheet.invoice');

  static bool canArchiveWorksheet(String? role) =>
      has(role, 'worksheet.archive');

  static bool canCreateRepair(String? role) => has(role, 'repair.create');

  static bool canViewRepair(String? role) => has(role, 'repair.view');

  static bool canExportRepair(String? role) => has(role, 'repair.export');

  static String roleLabel(String? role) {
    switch (role) {
      case 'worker':
        return 'Pracovník';
      case 'vedeni':
        return 'Vedení';
      case 'admin':
        return 'Super Admin';
      default:
        return role ?? '';
    }
  }
}
