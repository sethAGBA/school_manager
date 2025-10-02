class AppUser {
  final String username;
  final String displayName;
  final String role; // e.g., admin, staff, viewer
  final String passwordHash;
  final String salt;
  final bool isTwoFactorEnabled;
  final String? totpSecret;
  final bool isActive;
  final String? createdAt;
  final String? lastLoginAt;
  final String? permissions; // JSON string of permissions

  AppUser({
    required this.username,
    required this.displayName,
    required this.role,
    required this.passwordHash,
    required this.salt,
    required this.isTwoFactorEnabled,
    required this.totpSecret,
    required this.isActive,
    this.createdAt,
    this.lastLoginAt,
    this.permissions,
  });

  Map<String, dynamic> toMap() => {
        'username': username,
        'displayName': displayName,
        'role': role,
        'passwordHash': passwordHash,
        'salt': salt,
        'isTwoFactorEnabled': isTwoFactorEnabled ? 1 : 0,
        'totpSecret': totpSecret,
        'isActive': isActive ? 1 : 0,
        'createdAt': createdAt,
        'lastLoginAt': lastLoginAt,
        'permissions': permissions,
      };

  static AppUser fromMap(Map<String, dynamic> map) => AppUser(
        username: map['username'] as String,
        displayName: (map['displayName'] as String?) ?? '',
        role: (map['role'] as String?) ?? 'admin',
        passwordHash: map['passwordHash'] as String,
        salt: map['salt'] as String,
        isTwoFactorEnabled: (map['isTwoFactorEnabled'] as int? ?? 0) == 1,
        totpSecret: map['totpSecret'] as String?,
        isActive: (map['isActive'] as int? ?? 1) == 1,
        createdAt: map['createdAt'] as String?,
        lastLoginAt: map['lastLoginAt'] as String?,
        permissions: map['permissions'] as String?,
      );
}
