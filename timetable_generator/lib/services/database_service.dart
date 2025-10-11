// services/database_service.dart
import 'package:hive_flutter/hive_flutter.dart';
import '../models/models.dart';

class DatabaseService {
  static const String _classesBox = 'classes';
  static const String _professeursBox = 'professeurs';
  static const String _matieresBox = 'matieres';
  static const String _sallesBox = 'salles';
  static const String _emploisBox = 'emplois_du_temps';

  /// Initialise Hive et enregistre les adaptateurs
  static Future<void> init() async {
    await Hive.initFlutter();
    
    // Enregistrer les adaptateurs (à créer avec hive_generator)
    Hive.registerAdapter(ClasseAdapter());
    Hive.registerAdapter(ProfesseurAdapter());
    Hive.registerAdapter(MatiereAdapter());
    Hive.registerAdapter(SalleAdapter());
    Hive.registerAdapter(EmploiDuTempsAdapter());
    Hive.registerAdapter(CoursAdapter());
    Hive.registerAdapter(CreneauAdapter());
    
    // Ouvrir les boxes
    await Hive.openBox<Classe>(_classesBox);
    await Hive.openBox<Professeur>(_professeursBox);
    await Hive.openBox<Matiere>(_matieresBox);
    await Hive.openBox<Salle>(_sallesBox);
    await Hive.openBox<EmploiDuTemps>(_emploisBox);
  }

  // ===== CLASSES =====
  
  static Future<void> ajouterClasse(Classe classe) async {
    final box = Hive.box<Classe>(_classesBox);
    await box.put(classe.id, classe);
  }

  static Future<void> modifierClasse(Classe classe) async {
    await ajouterClasse(classe);
  }

  static Future<void> supprimerClasse(String id) async {
    final box = Hive.box<Classe>(_classesBox);
    await box.delete(id);
  }

  static List<Classe> obtenirClasses() {
    final box = Hive.box<Classe>(_classesBox);
    return box.values.toList();
  }

  static Classe? obtenirClasse(String id) {
    final box = Hive.box<Classe>(_classesBox);
    return box.get(id);
  }

  // ===== PROFESSEURS =====
  
  static Future<void> ajouterProfesseur(Professeur prof) async {
    final box = Hive.box<Professeur>(_professeursBox);
    await box.put(prof.id, prof);
  }

  static Future<void> modifierProfesseur(Professeur prof) async {
    await ajouterProfesseur(prof);
  }

  static Future<void> supprimerProfesseur(String id) async {
    final box = Hive.box<Professeur>(_professeursBox);
    await box.delete(id);
  }

  static List<Professeur> obtenirProfesseurs() {
    final box = Hive.box<Professeur>(_professeursBox);
    return box.values.toList();
  }

  static Professeur? obtenirProfesseur(String id) {
    final box = Hive.box<Professeur>(_professeursBox);
    return box.get(id);
  }

  // ===== MATIÈRES =====
  
  static Future<void> ajouterMatiere(Matiere matiere) async {
    final box = Hive.box<Matiere>(_matieresBox);
    await box.put(matiere.id, matiere);
  }

  static Future<void> modifierMatiere(Matiere matiere) async {
    await ajouterMatiere(matiere);
  }

  static Future<void> supprimerMatiere(String id) async {
    final box = Hive.box<Matiere>(_matieresBox);
    await box.delete(id);
  }

  static List<Matiere> obtenirMatieres() {
    final box = Hive.box<Matiere>(_matieresBox);
    return box.values.toList();
  }

  static Matiere? obtenirMatiere(String id) {
    final box = Hive.box<Matiere>(_matieresBox);
    return box.get(id);
  }

  // ===== SALLES =====
  
  static Future<void> ajouterSalle(Salle salle) async {
    final box = Hive.box<Salle>(_sallesBox);
    await box.put(salle.id, salle);
  }

  static Future<void> modifierSalle(Salle salle) async {
    await ajouterSalle(salle);
  }

  static Future<void> supprimerSalle(String id) async {
    final box = Hive.box<Salle>(_sallesBox);
    await box.delete(id);
  }

  static List<Salle> obtenirSalles() {
    final box = Hive.box<Salle>(_sallesBox);
    return box.values.toList();
  }

  static Salle? obtenirSalle(String id) {
    final box = Hive.box<Salle>(_sallesBox);
    return box.get(id);
  }

  // ===== EMPLOIS DU TEMPS =====
  
  static Future<void> sauvegarderEmploiDuTemps(EmploiDuTemps emploi) async {
    final box = Hive.box<EmploiDuTemps>(_emploisBox);
    await box.put(emploi.id, emploi);
  }

  static Future<void> supprimerEmploiDuTemps(String id) async {
    final box = Hive.box<EmploiDuTemps>(_emploisBox);
    await box.delete(id);
  }

  static List<EmploiDuTemps> obtenirEmploisDuTemps() {
    final box = Hive.box<EmploiDuTemps>(_emploisBox);
    return box.values.toList();
  }

  static EmploiDuTemps? obtenirEmploiDuTemps(String id) {
    final box = Hive.box<EmploiDuTemps>(_emploisBox);
    return box.get(id);
  }

  // ===== UTILITAIRES =====
  
  static Future<void> effacerToutesDonnees() async {
    await Hive.box<Classe>(_classesBox).clear();
    await Hive.box<Professeur>(_professeursBox).clear();
    await Hive.box<Matiere>(_matieresBox).clear();
    await Hive.box<Salle>(_sallesBox).clear();
    await Hive.box<EmploiDuTemps>(_emploisBox).clear();
  }

  static Future<void> chargerDonneesExemple() async {
    // Classes
    await ajouterClasse(Classe(
      id: 'c1',
      nom: '6ème A',
      niveau: '6ème',
      section: 'A',
      nombreEleves: 30,
    ));
    await ajouterClasse(Classe(
      id: 'c2',
      nom: '6ème B',
      niveau: '6ème',
      section: 'B',
      nombreEleves: 28,
    ));
    await ajouterClasse(Classe(
      id: 'c3',
      nom: '5ème A',
      niveau: '5ème',
      section: 'A',
      nombreEleves: 32,
    ));

    // Professeurs
    await ajouterProfesseur(Professeur(
      id: 'p1',
      nom: 'Dupont',
      prenom: 'Jean',
      matieresIds: ['m1'],
      maxHeuresParJour: 6,
      maxHeuresParSemaine: 24,
    ));
    await ajouterProfesseur(Professeur(
      id: 'p2',
      nom: 'Martin',
      prenom: 'Marie',
      matieresIds: ['m2'],
      maxHeuresParJour: 6,
      maxHeuresParSemaine: 24,
    ));
    await ajouterProfesseur(Professeur(
      id: 'p3',
      nom: 'Bernard',
      prenom: 'Paul',
      matieresIds: ['m3'],
      maxHeuresParJour: 5,
      maxHeuresParSemaine: 20,
    ));
    await ajouterProfesseur(Professeur(
      id: 'p4',
      nom: 'Dubois',
      prenom: 'Sophie',
      matieresIds: ['m4'],
      maxHeuresParJour: 6,
      maxHeuresParSemaine: 18,
    ));
    await ajouterProfesseur(Professeur(
      id: 'p5',
      nom: 'Moreau',
      prenom: 'Luc',
      matieresIds: ['m5'],
      maxHeuresParJour: 4,
      maxHeuresParSemaine: 16,
    ));

    // Matières
    await ajouterMatiere(Matiere(
      id: 'm1',
      nom: 'Mathématiques',
      volumeHoraireHebdo: 4,
      dureeSceance: 60,
      niveauDifficulte: 5,
      type: TypeMatiere.theorique,
    ));
    await ajouterMatiere(Matiere(
      id: 'm2',
      nom: 'Français',
      volumeHoraireHebdo: 4,
      dureeSceance: 60,
      niveauDifficulte: 4,
      type: TypeMatiere.theorique,
    ));
    await ajouterMatiere(Matiere(
      id: 'm3',
      nom: 'Anglais',
      volumeHoraireHebdo: 3,
      dureeSceance: 60,
      niveauDifficulte: 3,
      type: TypeMatiere.theorique,
    ));
    await ajouterMatiere(Matiere(
      id: 'm4',
      nom: 'Histoire-Géo',
      volumeHoraireHebdo: 3,
      dureeSceance: 60,
      niveauDifficulte: 3,
      type: TypeMatiere.theorique,
    ));
    await ajouterMatiere(Matiere(
      id: 'm5',
      nom: 'EPS',
      volumeHoraireHebdo: 2,
      dureeSceance: 120,
      type: TypeMatiere.sport,
      necessiteSalleSpeciale: true,
      niveauDifficulte: 1,
    ));

    // Salles
    await ajouterSalle(Salle(
      id: 's1',
      nom: 'Salle 101',
      capacite: 35,
      type: TypeSalle.standard,
    ));
    await ajouterSalle(Salle(
      id: 's2',
      nom: 'Salle 102',
      capacite: 35,
      type: TypeSalle.standard,
    ));
    await ajouterSalle(Salle(
      id: 's3',
      nom: 'Salle 103',
      capacite: 35,
      type: TypeSalle.standard,
    ));
    await ajouterSalle(Salle(
      id: 's4',
      nom: 'Salle 201',
      capacite: 30,
      type: TypeSalle.standard,
    ));
    await ajouterSalle(Salle(
      id: 's5',
      nom: 'Gymnase',
      capacite: 50,
      type: TypeSalle.sport,
    ));
  }
}

// Adaptateurs Hive (à générer avec build_runner)
// Ajoutez ces annotations dans vos models :
/*
@HiveType(typeId: 0)
class Classe extends HiveObject {
  @HiveField(0)
  final String id;
  // ... etc
}
*/