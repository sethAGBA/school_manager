// providers/timetable_provider.dart
import 'package:flutter/foundation.dart';
import '../../models/models.dart';
import '../../services/database_service.dart';
import '../../services/timetable_generator.dart';

class TimetableProvider extends ChangeNotifier {
  List<Classe> _classes = [];
  List<Professeur> _professeurs = [];
  List<Matiere> _matieres = [];
  List<Salle> _salles = [];
  List<EmploiDuTemps> _emploisDuTemps = [];
  
  EmploiDuTemps? _emploiDuTempsCourant;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<Classe> get classes => _classes;
  List<Professeur> get professeurs => _professeurs;
  List<Matiere> get matieres => _matieres;
  List<Salle> get salles => _salles;
  List<EmploiDuTemps> get emploisDuTemps => _emploisDuTemps;
  EmploiDuTemps? get emploiDuTempsCourant => _emploiDuTempsCourant;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Charge toutes les données depuis la base de données
  Future<void> chargerDonnees() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _classes = DatabaseService.obtenirClasses();
      _professeurs = DatabaseService.obtenirProfesseurs();
      _matieres = DatabaseService.obtenirMatieres();
      _salles = DatabaseService.obtenirSalles();
      _emploisDuTemps = DatabaseService.obtenirEmploisDuTemps();

      if (_emploisDuTemps.isNotEmpty) {
        _emploiDuTempsCourant = _emploisDuTemps.first;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors du chargement des données: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // ===== GESTION DES CLASSES =====

  Future<void> ajouterClasse(Classe classe) async {
    try {
      await DatabaseService.ajouterClasse(classe);
      _classes.add(classe);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de l\'ajout de la classe: $e';
      notifyListeners();
    }
  }

  Future<void> modifierClasse(Classe classe) async {
    try {
      await DatabaseService.modifierClasse(classe);
      final index = _classes.indexWhere((c) => c.id == classe.id);
      if (index != -1) {
        _classes[index] = classe;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Erreur lors de la modification de la classe: $e';
      notifyListeners();
    }
  }

  Future<void> supprimerClasse(String id) async {
    try {
      await DatabaseService.supprimerClasse(id);
      _classes.removeWhere((c) => c.id == id);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de la suppression de la classe: $e';
      notifyListeners();
    }
  }

  // ===== GESTION DES PROFESSEURS =====

  Future<void> ajouterProfesseur(Professeur prof) async {
    try {
      await DatabaseService.ajouterProfesseur(prof);
      _professeurs.add(prof);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de l\'ajout du professeur: $e';
      notifyListeners();
    }
  }

  Future<void> modifierProfesseur(Professeur prof) async {
    try {
      await DatabaseService.modifierProfesseur(prof);
      final index = _professeurs.indexWhere((p) => p.id == prof.id);
      if (index != -1) {
        _professeurs[index] = prof;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Erreur lors de la modification du professeur: $e';
      notifyListeners();
    }
  }

  Future<void> supprimerProfesseur(String id) async {
    try {
      await DatabaseService.supprimerProfesseur(id);
      _professeurs.removeWhere((p) => p.id == id);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de la suppression du professeur: $e';
      notifyListeners();
    }
  }

  // ===== GESTION DES MATIÈRES =====

  Future<void> ajouterMatiere(Matiere matiere) async {
    try {
      await DatabaseService.ajouterMatiere(matiere);
      _matieres.add(matiere);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de l\'ajout de la matière: $e';
      notifyListeners();
    }
  }

  Future<void> modifierMatiere(Matiere matiere) async {
    try {
      await DatabaseService.modifierMatiere(matiere);
      final index = _matieres.indexWhere((m) => m.id == matiere.id);
      if (index != -1) {
        _matieres[index] = matiere;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Erreur lors de la modification de la matière: $e';
      notifyListeners();
    }
  }

  Future<void> supprimerMatiere(String id) async {
    try {
      await DatabaseService.supprimerMatiere(id);
      _matieres.removeWhere((m) => m.id == id);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de la suppression de la matière: $e';
      notifyListeners();
    }
  }

  // ===== GESTION DES SALLES =====

  Future<void> ajouterSalle(Salle salle) async {
    try {
      await DatabaseService.ajouterSalle(salle);
      _salles.add(salle);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de l\'ajout de la salle: $e';
      notifyListeners();
    }
  }

  Future<void> modifierSalle(Salle salle) async {
    try {
      await DatabaseService.modifierSalle(salle);
      final index = _salles.indexWhere((s) => s.id == salle.id);
      if (index != -1) {
        _salles[index] = salle;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Erreur lors de la modification de la salle: $e';
      notifyListeners();
    }
  }

  Future<void> supprimerSalle(String id) async {
    try {
      await DatabaseService.supprimerSalle(id);
      _salles.removeWhere((s) => s.id == id);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de la suppression de la salle: $e';
      notifyListeners();
    }
  }

  // ===== GÉNÉRATION DE L'EMPLOI DU TEMPS =====

  Future<bool> genererEmploiDuTemps({
    ConfigurationHoraire? config,
  }) async {
    if (_classes.isEmpty || _professeurs.isEmpty || 
        _matieres.isEmpty || _salles.isEmpty) {
      _errorMessage = 'Données incomplètes. Veuillez ajouter des classes, professeurs, matières et salles.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final generator = TimetableGenerator(
        classes: _classes,
        professeurs: _professeurs,
        matieres: _matieres,
        salles: _salles,
        config: config ?? ConfigurationHoraire(),
      );

      final emploiDuTemps = await generator.generer();
      
      await DatabaseService.sauvegarderEmploiDuTemps(emploiDuTemps);
      
      _emploiDuTempsCourant = emploiDuTemps;
      _emploisDuTemps.insert(0, emploiDuTemps);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Erreur lors de la génération: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sélectionne un emploi du temps existant
  void selectionnerEmploiDuTemps(String id) {
    _emploiDuTempsCourant = _emploisDuTemps.firstWhere(
      (e) => e.id == id,
      orElse: () => _emploisDuTemps.first,
    );
    notifyListeners();
  }

  /// Supprime un emploi du temps
  Future<void> supprimerEmploiDuTemps(String id) async {
    try {
      await DatabaseService.supprimerEmploiDuTemps(id);
      _emploisDuTemps.removeWhere((e) => e.id == id);
      
      if (_emploiDuTempsCourant?.id == id) {
        _emploiDuTempsCourant = _emploisDuTemps.isNotEmpty ? _emploisDuTemps.first : null;
      }
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de la suppression: $e';
      notifyListeners();
    }
  }

  /// Charge les données d'exemple
  Future<void> chargerDonneesExemple() async {
    _isLoading = true;
    notifyListeners();

    try {
      await DatabaseService.chargerDonneesExemple();
      await chargerDonnees();
    } catch (e) {
      _errorMessage = 'Erreur lors du chargement des données exemple: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Efface toutes les données
  Future<void> effacerToutesDonnees() async {
    _isLoading = true;
    notifyListeners();

    try {
      await DatabaseService.effacerToutesDonnees();
      _classes = [];
      _professeurs = [];
      _matieres = [];
      _salles = [];
      _emploisDuTemps = [];
      _emploiDuTempsCourant = null;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Erreur lors de l\'effacement: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Réinitialise le message d'erreur
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Obtient les statistiques de l'emploi du temps
  Map<String, dynamic> obtenirStatistiques() {
    if (_emploiDuTempsCourant == null) {
      return {
        'coursTotal': 0,
        'coursPlaces': 0,
        'tauxRemplissage': 0.0,
        'heuresParClasse': {},
        'heuresParProf': {},
      };
    }

    final coursPlaces = _emploiDuTempsCourant!.cours.length;
    int coursTotal = 0;
    
    for (var classe in _classes) {
      for (var matiere in _matieres) {
        coursTotal += matiere.nombreSeances;
      }
    }

    Map<String, int> heuresParClasse = {};
    Map<String, int> heuresParProf = {};

    for (var cours in _emploiDuTempsCourant!.cours) {
      // Heures par classe
      heuresParClasse[cours.classeId] = (heuresParClasse[cours.classeId] ?? 0) + 
          (cours.creneau?.duree ?? 0);
      
      // Heures par prof
      heuresParProf[cours.professeurId] = (heuresParProf[cours.professeurId] ?? 0) + 
          (cours.creneau?.duree ?? 0);
    }

    return {
      'coursTotal': coursTotal,
      'coursPlaces': coursPlaces,
      'tauxRemplissage': (coursPlaces / coursTotal * 100).toStringAsFixed(1),
      'heuresParClasse': heuresParClasse,
      'heuresParProf': heuresParProf,
      'score': _emploiDuTempsCourant!.score,
    };
  }
}