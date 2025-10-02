import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:otp/otp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_manager/models/user.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/permission_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String _currentUserKey = 'current_username';

  Future<AppUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_currentUserKey);
    if (username == null) return null;
    final row = await DatabaseService().getUserRowByUsername(username);
    if (row == null) return null;
    return AppUser.fromMap(row);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }

  String _generateSalt({int length = 16}) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<AppUser> createOrUpdateUser({
    required String username,
    required String displayName,
    required String role,
    required String password,
    bool enable2FA = false,
    Set<String>? permissions,
    String? secret2FA, // Add this parameter
  }) async {
    final salt = _generateSalt();
    final passwordHash = _hashPassword(password, salt);
    final String? secret = enable2FA ? (secret2FA ?? OTP.randomSecret()) : null; // Use provided secret2FA or generate new

    final user = AppUser(
      username: username,
      displayName: displayName,
      role: role,
      passwordHash: passwordHash,
      salt: salt,
      isTwoFactorEnabled: enable2FA,
      totpSecret: secret,
      isActive: true,
      createdAt: DateTime.now().toIso8601String(),
      lastLoginAt: null,
      permissions: PermissionService.encodePermissions(
        permissions ?? PermissionService.defaultForRole(role),
      ),
    );

    await DatabaseService().upsertUser(user.toMap());
    return user;
  }

  Future<AppUser?> updateUser({
    required String username,
    String? displayName,
    String? role,
    String? newPassword,
    bool? enable2FA,
    Set<String>? permissions,
  }) async {
    final existing = await DatabaseService().getUserRowByUsername(username);
    if (existing == null) return null;

    final currentUser = AppUser.fromMap(existing);

    final bool next2FA = enable2FA ?? currentUser.isTwoFactorEnabled;
    String? nextSecret;
    if (next2FA) {
      nextSecret = currentUser.totpSecret ?? OTP.randomSecret();
    } else {
      nextSecret = null;
    }

    String nextSalt = currentUser.salt;
    String nextPasswordHash = currentUser.passwordHash;
    if (newPassword != null && newPassword.isNotEmpty) {
      nextSalt = _generateSalt();
      nextPasswordHash = _hashPassword(newPassword, nextSalt);
    }

    final updated = AppUser(
      username: currentUser.username,
      displayName: displayName ?? currentUser.displayName,
      role: role ?? currentUser.role,
      passwordHash: nextPasswordHash,
      salt: nextSalt,
      isTwoFactorEnabled: next2FA,
      totpSecret: nextSecret,
      isActive: currentUser.isActive,
      createdAt: currentUser.createdAt,
      lastLoginAt: currentUser.lastLoginAt,
      permissions: PermissionService.encodePermissions(
        permissions ?? PermissionService.decodePermissions(currentUser.permissions, role: currentUser.role),
      ),
    );

    await DatabaseService().upsertUser(updated.toMap());
    return updated;
  }

  Future<({bool ok, bool requires2FA})> authenticatePassword(String username, String password) async {
    final row = await DatabaseService().getUserRowByUsername(username);
    if (row == null) return (ok: false, requires2FA: false);
    if ((row['isActive'] as int? ?? 1) == 0) return (ok: false, requires2FA: false);
    final salt = row['salt'] as String;
    final expected = row['passwordHash'] as String;
    final provided = _hashPassword(password, salt);
    if (provided != expected) return (ok: false, requires2FA: false);
    final requires2FA = (row['isTwoFactorEnabled'] as int? ?? 0) == 1;
    return (ok: true, requires2FA: requires2FA);
  }

  Future<bool> finalizeLogin(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, username);
    await DatabaseService().updateUserLastLoginAt(username);
    return true;
  }

  bool isTwoFactorRequired(Map<String, dynamic> userRow) {
    return (userRow['isTwoFactorEnabled'] as int? ?? 0) == 1;
  }

  Future<bool> verifyTotpCode(String username, String code) async {
    final row = await DatabaseService().getUserRowByUsername(username);
    if (row == null) return false;
    final secret = row['totpSecret'] as String?;
    if (secret == null || secret.isEmpty) return false;
    final trimmed = code.replaceAll(' ', '');
    // The OTP package expects current time in milliseconds
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    for (int offset = -1; offset <= 1; offset++) {
      try {
        final generated = OTP.generateTOTPCodeString(
          secret,
          nowMillis + (offset * 30000), // +/- 30s windows
          interval: 30,
          length: 6,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );
        if (generated == trimmed) return true;
      } catch (_) {
        // ignore and continue
      }
    }
    return false;
  }

  Future<String?> getTotpProvisioningUri(String username, {String issuer = 'EcoleManager'}) async {
    final row = await DatabaseService().getUserRowByUsername(username);
    if (row == null) return null;
    final secret = row['totpSecret'] as String?;
    if (secret == null) return null;
    final account = Uri.encodeComponent(username);
    final iss = Uri.encodeComponent(issuer);
    return 'otpauth://totp/$iss:$account?secret=$secret&issuer=$iss&algorithm=SHA1&digits=6&period=30';
  }
}
