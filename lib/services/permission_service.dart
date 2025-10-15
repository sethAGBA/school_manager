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
    'view_finance_inventory',
    'view_audits',
    'view_signatures',
    'manage_safe_mode',
  };

  static const defaultStaffPermissions = <String>{
    'view_dashboard',
    'view_students',
    'view_grades',
    'view_payments',
    'view_subjects',
    'view_finance_inventory',
  };

  static const defaultTeacherPermissions = <String>{
    'view_dashboard',
    'view_grades',
    'view_subjects',
    'view_finance_inventory',
  };

  static Set<String> decodePermissions(
    String? jsonStr, {
    required String role,
  }) {
    if (jsonStr == null || jsonStr.isEmpty) {
      return defaultForRole(role);
    }
    try {
      final data = json.decode(jsonStr);
      if (data is List) {
        final set = data.map((e) => e.toString()).toSet();
        // Normalisation rétrocompatible
        if (set.contains('view_audit_log')) {
          set.add('view_audits');
        }
        return set;
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
