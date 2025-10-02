import 'dart:convert';

class PermissionService {
  static const defaultAdminPermissions = <String>{
    'view_dashboard',
    'view_students',
    'view_staff',
    'view_grades',
    'view_payments',
    'view_settings',
    'view_users',
    'manage_users',
    'manage_permissions',
    'view_timetables',
    'view_license',
    'view_subjects',
  };

  static const defaultStaffPermissions = <String>{
    'view_dashboard',
    'view_students',
    'view_grades',
    'view_payments',
    'view_subjects',
  };

  static const defaultTeacherPermissions = <String>{
    'view_dashboard',
    'view_grades',
    'view_subjects',
  };

  static Set<String> decodePermissions(String? jsonStr, {required String role}) {
    if (jsonStr == null || jsonStr.isEmpty) {
      return defaultForRole(role);
    }
    try {
      final data = json.decode(jsonStr);
      if (data is List) {
        return data.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return defaultForRole(role);
  }

  static String encodePermissions(Set<String> permissions) {
    return json.encode(permissions.toList());
  }

  static Set<String> defaultForRole(String role) {
    switch (role) {
      case 'admin':
        return defaultAdminPermissions;
      case 'prof':
      case 'teacher':
        return defaultTeacherPermissions;
      case 'staff':
        return defaultStaffPermissions;
      default:
        return <String>{'view_dashboard'};
    }
  }
}
