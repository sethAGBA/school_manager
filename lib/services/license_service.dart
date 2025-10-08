import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LicenseStatus {
  final String? key;
  final DateTime? registeredAt;
  final DateTime? expiry;

  const LicenseStatus({this.key, this.registeredAt, this.expiry});

  bool get isLifetime {
    if (registeredAt == null || expiry == null) return false;
    // Consider lifetime if duration is > 800 years
    return expiry!.difference(registeredAt!).inDays > (800 * 365);
  }

  bool get hasKey => (key != null && key!.trim().isNotEmpty);
  bool get hasExpiry => expiry != null;
  bool get isExpired => hasExpiry ? DateTime.now().isAfter(expiry!) : false;
  bool get isActive => hasKey && hasExpiry && !isExpired;
  int get daysRemaining {
    if (!hasExpiry) return 0;
    return expiry!.difference(DateTime.now()).inDays;
  }
}

class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  // 12 random, single-use license keys (format: 4-4-4-4 alphanum, case-insensitive)
  static const List<String> validKeys = [
    'Z7KJ-3PMQ-XA49-NE2T',
    'Q5HL-UD93-RBKN-17ZX',
    'T9MW-2GQF-LA58-Y3RD',
    'P6VN-X4JE-8KQT-5H2C',
    'H4DQ-RT2N-9SVE-M7K1',
    'B2YM-5ZQ8-CLN7-J4TX',
    'N8KF-3RJL-7Q2P-VD65',
    'R1TE-6H9M-PQ47-X2LB',
    'C7PX-M2Q8-9LRT-HE54',
    'J5QN-7K2V-U8RD-3XLP',
    'L9HT-4MVE-2QX7-BK13',
    'V3ZP-8Q1N-R6JL-D5TC',
  ];

  static String _normalize(String input) =>
      input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  static final Set<String> _validNormalized = validKeys.map(_normalize).toSet();

  // Special test keys: single-use, custom validity (months), do not count towards the 12-license quota
  static const Map<String, int> _specialKeysMonths = {
    // normalized form (no dashes, uppercase) : months
    'ACTETEST3MALPHA': 3,
    'ACTELIFE2025': 9999, // Clé à vie
  };

  // Preference keys
  static const _keyActive = 'license_key';
  static const _keyRegisteredAt = 'license_registered_at';
  static const _keyExpiry = 'license_expiry';
  static const _keyUsedList = 'license_used_keys'; // string list (normalized)
  // SupAdmin secret: fixed at build-time, not changeable in app
  static const String _supAdminSecret = String.fromEnvironment(
    'SUPADMIN_PASSWORD',
    defaultValue: 'ACTE#SupAdmin2025!',
  );

  // Reactive notifier for UI to gate features
  final ValueListenable<bool> activeNotifier = _LicenseActiveNotifier();

  Future<LicenseStatus> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_keyActive);
    final regStr = prefs.getString(_keyRegisteredAt);
    final expiryStr = prefs.getString(_keyExpiry);
    DateTime? regAt;
    DateTime? expiry;
    if (regStr != null && regStr.isNotEmpty) {
      try {
        regAt = DateTime.parse(regStr);
      } catch (_) {}
    }
    if (expiryStr != null && expiryStr.isNotEmpty) {
      try {
        expiry = DateTime.parse(expiryStr);
      } catch (_) {}
    }
    return LicenseStatus(key: key, registeredAt: regAt, expiry: expiry);
  }

  Future<bool> hasActive() async {
    final st = await getStatus();
    return st.isActive;
  }

  // Register a license key if valid and not previously used.
  // Sets expiry to 12 months from registration date.
  Future<void> saveLicense({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalize(key);
    final used = prefs.getStringList(_keyUsedList) ?? <String>[];
    final isStandard = _validNormalized.contains(normalized);
    final isSpecial = _specialKeysMonths.containsKey(normalized);
    final alreadyUsed = used.contains(normalized);
    if (!(isStandard || isSpecial) || alreadyUsed) {
      throw Exception('Clé invalide ou déjà utilisée');
    }
    final now = DateTime.now();
    final months = isStandard ? 12 : (_specialKeysMonths[normalized] ?? 12);
    final expiry = DateTime(now.year, now.month + months, now.day, 23, 59, 59);
    await prefs.setString(_keyActive, normalized);
    await prefs.setString(_keyRegisteredAt, now.toIso8601String());
    await prefs.setString(_keyExpiry, expiry.toIso8601String());
    await prefs.setStringList(_keyUsedList, [...used, normalized]);
    await refreshActive();
  }

  Future<void> clearLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActive);
    await prefs.remove(_keyRegisteredAt);
    await prefs.remove(_keyExpiry);
    // Important: do NOT remove from used list; single-use remains enforced
    await refreshActive();
  }

  Future<void> refreshActive() async {
    final st = await getStatus();
    (_licenseNotifier as _LicenseActiveNotifier).update(st.isActive);
  }

  Future<bool> allKeysUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final used = (prefs.getStringList(_keyUsedList) ?? <String>[]).toSet();
    return _validNormalized.difference(used).isEmpty;
  }

  // Internal notifier impl
  static final _LicenseActiveNotifier _licenseNotifier =
      _LicenseActiveNotifier();

  // Verify SupAdmin using the build-time secret
  Future<bool> verifySupAdmin(String password) async {
    // Hash both sides with SHA-256 and compare hex strings
    String h(String s) => sha256.convert(utf8.encode(s)).toString();
    return constantTimeEquals(h(password), h(_supAdminSecret));
  }

  // Prevent timing attacks for short secrets
  bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

class _LicenseActiveNotifier extends ValueNotifier<bool>
    implements ValueListenable<bool> {
  _LicenseActiveNotifier() : super(false);
  void update(bool v) {
    if (value != v) value = v;
  }
}
