import 'package:school_manager/services/signature_assignment_service.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/models/signature.dart';

/// Test simple pour vérifier le fonctionnement du système de signatures
class SignatureSystemTest {
  final SignatureAssignmentService _assignmentService = SignatureAssignmentService();
  final DatabaseService _dbService = DatabaseService();

  /// Test de création d'une signature de test
  Future<void> createTestSignature() async {
    try {
      final signature = Signature(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Signature Test Directeur',
        type: 'signature',
        description: 'Signature de test pour le directeur',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        associatedRole: 'directeur',
        isDefault: true,
      );

      await _dbService.insertSignature(signature);
      print('✅ Signature de test créée avec succès');
    } catch (e) {
      print('❌ Erreur lors de la création de la signature: $e');
    }
  }

  /// Test de création d'un cachet de test
  Future<void> createTestCachet() async {
    try {
      final cachet = Signature(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'Cachet Test Établissement',
        type: 'cachet',
        description: 'Cachet de test pour l\'établissement',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        associatedRole: 'directeur',
        isDefault: true,
      );

      await _dbService.insertSignature(cachet);
      print('✅ Cachet de test créé avec succès');
    } catch (e) {
      print('❌ Erreur lors de la création du cachet: $e');
    }
  }

  /// Test de récupération des signatures
  Future<void> testGetSignatures() async {
    try {
      final signatures = await _assignmentService.getSignaturesByRole('directeur');
      print('✅ Récupération des signatures: ${signatures.length} signatures trouvées');
      
      for (final signature in signatures) {
        print('  - ${signature.name} (${signature.type})');
      }
    } catch (e) {
      print('❌ Erreur lors de la récupération des signatures: $e');
    }
  }

  /// Test de récupération des classes avec signatures
  Future<void> testGetClassesWithSignatures() async {
    try {
      final classesWithSignatures = await _assignmentService.getAllClassesWithSignatures();
      print('✅ Classes avec signatures: ${classesWithSignatures.length} classes');
      
      for (final entry in classesWithSignatures.entries) {
        print('  - ${entry.key}: ${entry.value.length} signatures');
      }
    } catch (e) {
      print('❌ Erreur lors de la récupération des classes: $e');
    }
  }

  /// Test complet du système
  Future<void> runAllTests() async {
    print('🧪 Début des tests du système de signatures...\n');
    
    await createTestSignature();
    await createTestCachet();
    await testGetSignatures();
    await testGetClassesWithSignatures();
    
    print('\n✅ Tests terminés !');
  }
}