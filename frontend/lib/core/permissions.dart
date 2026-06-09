/// Central permission matrix — mirrors backend `permissions.ts`.
class AppPermissions {
  static const _matrix = <String, List<String>>{
    'seal.create': ['worker', 'vedeni', 'admin'],
    'seal.edit': ['worker', 'vedeni', 'admin'],
    'seal.status': ['vedeni', 'ucetni', 'admin'],
    'seal.delete': ['vedeni', 'admin'],
    'seal.restore': ['admin'],
    'seal.history': ['vedeni', 'ucetni', 'admin'],
    'photo.upload': ['worker', 'vedeni', 'admin'],
    'photo.delete': [],
    'job.manage': ['vedeni', 'admin'],
    'floor.manage': ['vedeni', 'admin'],
    'floor.drawing.manage': ['vedeni', 'ucetni', 'admin'],
    'user.manage': ['vedeni', 'admin'],
    'reports.view': ['worker', 'vedeni', 'ucetni', 'admin'],
    'reports.export': ['worker', 'vedeni', 'ucetni', 'admin'],
    'priceList.view': ['worker', 'vedeni', 'ucetni', 'admin'],
    'priceList.manage': ['vedeni', 'admin'],
    'logs.view': ['vedeni', 'admin'],
    'admin.trash': ['admin'],
    'worksheet.create': ['worker', 'ucetni', 'vedeni', 'admin'],
    'worksheet.view': ['worker', 'ucetni', 'vedeni', 'admin'],
    'worksheet.submit': ['worker', 'admin'],
    'worksheet.review': ['vedeni', 'admin'],
    'worksheet.invoice': ['ucetni', 'vedeni', 'admin'],
    'stats.view': ['worker', 'ucetni', 'vedeni', 'admin'],
  };

  static bool has(String? role, String permission) {
    if (role == null) return false;
    return _matrix[permission]?.contains(role) ?? false;
  }

  static bool canAccessReports(String? role) =>
      has(role, 'reports.view');

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

  static bool canViewStats(String? role) => has(role, 'stats.view');

  static bool canManageWorksheets(String? role) =>
      has(role, 'worksheet.create') || has(role, 'worksheet.view');

  static bool canCreateWorksheet(String? role) => has(role, 'worksheet.create');

  static bool canSubmitWorksheet(String? role) => has(role, 'worksheet.submit');

  static bool canReviewWorksheet(String? role) => has(role, 'worksheet.review');

  static bool canInvoiceWorksheet(String? role) => has(role, 'worksheet.invoice');

  static String roleLabel(String? role) {
    switch (role) {
      case 'worker':
        return 'Pracovník';
      case 'vedeni':
        return 'Vedení';
      case 'ucetni':
        return 'Administrativa';
      case 'admin':
        return 'Super Admin';
      default:
        return role ?? '';
    }
  }
}
