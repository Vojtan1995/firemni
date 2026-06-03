/// Central permission matrix — mirrors backend `permissions.ts`.
class AppPermissions {
  static const _matrix = <String, List<String>>{
    'seal.create': ['worker', 'vedeni', 'admin'],
    'seal.edit': ['worker', 'vedeni', 'admin'],
    'seal.status': ['vedeni', 'ucetni', 'admin'],
    'seal.delete': ['vedeni', 'admin'],
    'seal.restore': ['admin'],
    'photo.upload': ['worker', 'vedeni', 'admin'],
    'photo.delete': ['vedeni', 'admin'],
    'job.manage': ['vedeni', 'admin'],
    'floor.manage': ['vedeni', 'admin'],
    'user.manage': ['vedeni', 'admin'],
    'reports.view': ['vedeni', 'ucetni', 'admin'],
    'reports.export': ['vedeni', 'ucetni', 'admin'],
    'logs.view': ['vedeni', 'admin'],
    'admin.trash': ['admin'],
  };

  static bool has(String? role, String permission) {
    if (role == null) return false;
    return _matrix[permission]?.contains(role) ?? false;
  }

  static bool canAccessReports(String? role) =>
      has(role, 'reports.view');

  static bool canManageJobs(String? role) => has(role, 'job.manage');

  static bool canManageUsers(String? role) => has(role, 'user.manage');

  static bool canViewLogs(String? role) => has(role, 'logs.view');

  static bool canAccessTrash(String? role) => has(role, 'admin.trash');
}
