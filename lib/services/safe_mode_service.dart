import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class SafeModeService {
  SafeModeService._();
  static final SafeModeService instance = SafeModeService._();

  static const String _safeModeEnabledKey = 'safe_mode_enabled';
  static const String _safeModePasswordKey = 'safe_mode_password';
  static const String _safeModePasswordSaltKey = 'safe_mode_password_salt';

  // Notifier pour les changements d'état du mode coffre fort
  final ValueNotifier<bool> _isEnabledNotifier = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isEnabledNotifier => _isEnabledNotifier;

  bool get isEnabled => _isEnabledNotifier.value;

  /// Initialise le service et charge l'état actuel
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool(_safeModeEnabledKey) ?? false;
    _isEnabledNotifier.value = isEnabled;
  }

  /// Génère un salt pour le hachage du mot de passe
  String _generateSalt({int length = 16}) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Hache un mot de passe avec un salt
  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Vérifie si un mot de passe est correct
  Future<bool> verifyPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedHash = prefs.getString(_safeModePasswordKey);
    final storedSalt = prefs.getString(_safeModePasswordSaltKey);
    
    if (storedHash == null || storedSalt == null) {
      return false;
    }

    final providedHash = _hashPassword(password, storedSalt);
    return providedHash == storedHash;
  }

  /// Active le mode coffre fort avec un mot de passe
  Future<bool> enableSafeMode(String password) async {
    if (password.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    final passwordHash = _hashPassword(password, salt);

    await prefs.setString(_safeModePasswordKey, passwordHash);
    await prefs.setString(_safeModePasswordSaltKey, salt);
    await prefs.setBool(_safeModeEnabledKey, true);

    _isEnabledNotifier.value = true;
    return true;
  }

  /// Désactive le mode coffre fort
  Future<bool> disableSafeMode(String password) async {
    if (!isEnabled) return false;

    // Vérifier le mot de passe avant de désactiver
    final isPasswordCorrect = await verifyPassword(password);
    if (!isPasswordCorrect) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_safeModeEnabledKey, false);
    await prefs.remove(_safeModePasswordKey);
    await prefs.remove(_safeModePasswordSaltKey);

    _isEnabledNotifier.value = false;
    return true;
  }

  /// Change le mot de passe du mode coffre fort
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    if (!isEnabled || newPassword.isEmpty) return false;

    // Vérifier le mot de passe actuel
    final isCurrentPasswordCorrect = await verifyPassword(currentPassword);
    if (!isCurrentPasswordCorrect) return false;

    // Mettre à jour avec le nouveau mot de passe
    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    final passwordHash = _hashPassword(newPassword, salt);

    await prefs.setString(_safeModePasswordKey, passwordHash);
    await prefs.setString(_safeModePasswordSaltKey, salt);

    return true;
  }

  /// Vérifie si une action est autorisée (non bloquée par le mode coffre fort)
  bool isActionAllowed() {
    return !isEnabled;
  }

  /// Obtient le message d'erreur pour les actions bloquées
  String getBlockedActionMessage() {
    return 'Cette action est bloquée car le mode coffre fort est activé. Veuillez désactiver le mode coffre fort pour continuer.';
  }

  /// Libère les ressources
  void dispose() {
    _isEnabledNotifier.dispose();
  }
}