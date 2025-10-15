import 'package:school_manager/models/signature.dart';
import 'package:school_manager/services/database_service.dart';

class SignatureAssignmentService {
  final DatabaseService _dbService = DatabaseService();

  /// Récupère toutes les signatures associées à une classe spécifique
  Future<List<Signature>> getSignaturesForClass(String className) async {
    try {
      final signatures = await _dbService.getAllSignatures();
      return signatures.where((s) => s.associatedClass == className).toList();
    } catch (e) {
      throw Exception('Erreur lors de la récupération des signatures pour la classe $className: $e');
    }
  }

  /// Récupère les signatures par rôle (titulaire, directeur, etc.)
  Future<List<Signature>> getSignaturesByRole(String role) async {
    try {
      final signatures = await _dbService.getAllSignatures();
      return signatures.where((s) => s.associatedRole == role).toList();
    } catch (e) {
      throw Exception('Erreur lors de la récupération des signatures pour le rôle $role: $e');
    }
  }

  /// Récupère la signature par défaut pour un rôle et une classe
  /// Si className est vide, considère les signatures "globales" (associatedClass null ou vide)
  Future<Signature?> getDefaultSignatureForClassAndRole(String className, String role) async {
    try {
      final signatures = await _dbService.getAllSignatures();
      final normalized = className.trim();
      // 1) Chercher une correspondance stricte classe+role par défaut
      final exact = signatures.firstWhere(
        (s) => ((s.associatedClass ?? '').trim() == normalized) &&
               s.associatedRole == role &&
               s.isDefault == true,
        orElse: () => Signature.empty(),
      );
      if (exact.id.isNotEmpty) return exact;

      // 2) Si classe vide => fallback sur signature globale (associatedClass null/"")
      if (normalized.isEmpty) {
        final global = signatures.firstWhere(
          (s) => ((s.associatedClass == null) || (s.associatedClass?.trim().isEmpty ?? true)) &&
                 s.associatedRole == role &&
                 s.isDefault == true,
          orElse: () => Signature.empty(),
        );
        if (global.id.isNotEmpty) return global;
      }

      return Signature.empty();
    } catch (e) {
      return null;
    }
  }

  /// Récupère la signature du titulaire d'une classe
  Future<Signature?> getTitulaireSignature(String className) async {
    return await getDefaultSignatureForClassAndRole(className, 'titulaire');
  }

  /// Récupère la signature du directeur
  Future<Signature?> getDirecteurSignature() async {
    // Essayer d'abord la signature globale (classe vide), sinon n'importe quelle signature par défaut pour le rôle
    final exact = await getDefaultSignatureForClassAndRole('', 'directeur');
    if (exact != null && exact.id.isNotEmpty) return exact;
    try {
      final signatures = await _dbService.getAllSignatures();
      final anyDefault = signatures.firstWhere(
        (s) => s.associatedRole == 'directeur' && s.isDefault == true,
        orElse: () => Signature.empty(),
      );
      return anyDefault.id.isNotEmpty ? anyDefault : null;
    } catch (_) {
      return null;
    }
  }

  /// Récupère la signature du proviseur
  Future<Signature?> getProviseurSignature() async {
    final exact = await getDefaultSignatureForClassAndRole('', 'proviseur');
    if (exact != null && exact.id.isNotEmpty) return exact;
    try {
      final signatures = await _dbService.getAllSignatures();
      final anyDefault = signatures.firstWhere(
        (s) => s.associatedRole == 'proviseur' && s.isDefault == true,
        orElse: () => Signature.empty(),
      );
      return anyDefault.id.isNotEmpty ? anyDefault : null;
    } catch (_) {
      return null;
    }
  }

  /// Récupère la signature par défaut pour un rôle global (sans classe)
  Future<Signature?> getDefaultSignatureByRole(String role) async {
    final res = await getDefaultSignatureForClassAndRole('', role);
    if (res != null && res.id.isNotEmpty) return res;
    try {
      final signatures = await _dbService.getAllSignatures();
      final anyDefault = signatures.firstWhere(
        (s) => s.associatedRole == role && s.isDefault == true,
        orElse: () => Signature.empty(),
      );
      return anyDefault.id.isNotEmpty ? anyDefault : null;
    } catch (_) {
      return null;
    }
  }

  /// Récupère le cachet du directeur
  Future<Signature?> getDirecteurCachet() async {
    try {
      final signatures = await _dbService.getAllSignatures();
      // 1) Préférence: cachet par défaut de rôle 'directeur' (global ou classe vide)
      final preferred = signatures.firstWhere(
        (s) => s.type == 'cachet' &&
               s.isDefault == true &&
               s.associatedRole == 'directeur' &&
               ((s.associatedClass == null) || (s.associatedClass?.trim().isEmpty ?? true)),
        orElse: () => Signature.empty(),
      );
      if (preferred.id.isNotEmpty) return preferred;

      // 2) Fallback: tout cachet par défaut global, quel que soit le rôle
      final globalDefault = signatures.firstWhere(
        (s) => s.type == 'cachet' &&
               s.isDefault == true &&
               ((s.associatedClass == null) || (s.associatedClass?.trim().isEmpty ?? true)),
        orElse: () => Signature.empty(),
      );
      if (globalDefault.id.isNotEmpty) return globalDefault;

      // 3) Dernier recours: n'importe quel cachet par défaut
      final anyDefault = signatures.firstWhere(
        (s) => s.type == 'cachet' && s.isDefault == true,
        orElse: () => Signature.empty(),
      );
      return anyDefault.id.isNotEmpty ? anyDefault : null;
    } catch (e) {
      return null;
    }
  }

  /// Associe une signature à une classe et un rôle
  Future<void> assignSignatureToClass({
    required String signatureId,
    required String className,
    required String role,
    String? staffId,
    bool setAsDefault = false,
  }) async {
    try {
      final signature = await _dbService.getSignatureById(signatureId);
      if (signature == null) {
        throw Exception('Signature non trouvée');
      }

      // Si on définit comme signature par défaut, retirer le statut par défaut des autres signatures
      if (setAsDefault) {
        await _removeDefaultStatusForClassAndRole(className, role, type: signature.type);
      }

      final updatedSignature = signature.copyWith(
        associatedClass: className,
        associatedRole: role,
        staffId: staffId,
        isDefault: setAsDefault,
        updatedAt: DateTime.now(),
      );

      await _dbService.updateSignature(updatedSignature);
    } catch (e) {
      throw Exception('Erreur lors de l\'association de la signature: $e');
    }
  }

  /// Retire le statut par défaut des autres signatures pour une classe et un rôle
  Future<void> _removeDefaultStatusForClassAndRole(String className, String role, {required String type}) async {
    try {
      final signatures = await _dbService.getAllSignatures();
      final normalized = className.trim();
      final signaturesToUpdate = signatures.where((s) {
        final sClass = (s.associatedClass ?? '').trim();
        final sameScope = normalized.isEmpty ? sClass.isEmpty : sClass == normalized;
        return sameScope && s.associatedRole == role && s.type == type && s.isDefault == true;
      });

      for (final signature in signaturesToUpdate) {
        final updatedSignature = signature.copyWith(
          isDefault: false,
          updatedAt: DateTime.now(),
        );
        await _dbService.updateSignature(updatedSignature);
      }
    } catch (e) {
      throw Exception('Erreur lors de la suppression du statut par défaut: $e');
    }
  }

  /// Récupère toutes les classes avec leurs signatures associées
  Future<Map<String, List<Signature>>> getAllClassesWithSignatures() async {
    try {
      final classes = await _dbService.getClasses();
      final Map<String, List<Signature>> result = {};

      for (final classItem in classes) {
        final signatures = await getSignaturesForClass(classItem.name);
        result[classItem.name] = signatures;
      }

      return result;
    } catch (e) {
      throw Exception('Erreur lors de la récupération des classes avec signatures: $e');
    }
  }

  /// Récupère les signatures disponibles pour un rôle spécifique
  Future<List<Signature>> getAvailableSignaturesForRole(String role) async {
    try {
      final signatures = await _dbService.getAllSignatures();
      return signatures.where((s) => 
        s.type == 'signature' && 
        (s.associatedRole == null || s.associatedRole == role)
      ).toList();
    } catch (e) {
      throw Exception('Erreur lors de la récupération des signatures disponibles: $e');
    }
  }

  /// Récupère les cachets disponibles
  Future<List<Signature>> getAvailableCachets() async {
    try {
      final signatures = await _dbService.getAllSignatures();
      return signatures.where((s) => s.type == 'cachet').toList();
    } catch (e) {
      throw Exception('Erreur lors de la récupération des cachets: $e');
    }
  }

  /// Désassocie une signature d'une classe
  Future<void> unassignSignatureFromClass(String signatureId) async {
    try {
      final signature = await _dbService.getSignatureById(signatureId);
      if (signature == null) {
        throw Exception('Signature non trouvée');
      }

      final updatedSignature = signature.copyWith(
        associatedClass: null,
        associatedRole: null,
        staffId: null,
        isDefault: false,
        updatedAt: DateTime.now(),
      );

      await _dbService.updateSignature(updatedSignature);
    } catch (e) {
      throw Exception('Erreur lors de la désassociation de la signature: $e');
    }
  }

  /// Récupère les statistiques des signatures par classe
  Future<Map<String, Map<String, int>>> getSignatureStats() async {
    try {
      final signatures = await _dbService.getAllSignatures();
      final Map<String, Map<String, int>> stats = {};

      for (final signature in signatures) {
        if (signature.associatedClass != null) {
          final className = signature.associatedClass!;
          if (!stats.containsKey(className)) {
            stats[className] = {
              'signatures': 0,
              'cachets': 0,
              'titulaires': 0,
              'directeurs': 0,
            };
          }

          if (signature.type == 'signature') {
            stats[className]!['signatures'] = stats[className]!['signatures']! + 1;
          } else if (signature.type == 'cachet') {
            stats[className]!['cachets'] = stats[className]!['cachets']! + 1;
          }

          if (signature.associatedRole == 'titulaire') {
            stats[className]!['titulaires'] = stats[className]!['titulaires']! + 1;
          } else if (signature.associatedRole == 'directeur') {
            stats[className]!['directeurs'] = stats[className]!['directeurs']! + 1;
          }
        }
      }

      return stats;
    } catch (e) {
      throw Exception('Erreur lors de la récupération des statistiques: $e');
    }
  }
}
