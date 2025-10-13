// services/timetable_generator.dart
import 'dart:math';

import 'package:school_manager/models/timetable_models.dart';

/// Configuration des horaires de l'établissement
class ConfigurationHoraire {
  final int joursParSemaine;
  final int heureDebut;
  final int heureFin;
  final List<int> heuresDebut;
  final int dureeCreneauStandard;
  final int pauseDejeunerDebut;
  final int pauseDejeunerFin;

  ConfigurationHoraire({
    this.joursParSemaine = 5,
    this.heureDebut = 480, // 8h00
    this.heureFin = 1020, // 17h00
    this.dureeCreneauStandard = 60,
    this.pauseDejeunerDebut = 720, // 12h00
    this.pauseDejeunerFin = 780, // 13h00
  }) : heuresDebut = _genererHeuresDebut(heureDebut, heureFin, dureeCreneauStandard, pauseDejeunerDebut, pauseDejeunerFin);

  static List<int> _genererHeuresDebut(int debut, int fin, int duree, int pauseDebut, int pauseFin) {
    List<int> heures = [];
    for (int h = debut; h < fin; h += duree) {
      // Éviter de commencer un cours pendant la pause déjeuner
      if (h >= pauseDebut && h < pauseFin) continue;
      heures.add(h);
    }
    return heures;
  }
}

/// Générateur principal d'emploi du temps
class TimetableGenerator {
  final List<Classe> classes;
  final List<Professeur> professeurs;
  final List<Matiere> matieres;
  final List<Salle> salles;
  final ConfigurationHoraire config;

  TimetableGenerator({
    required this.classes,
    required this.professeurs,
    required this.matieres,
    required this.salles,
    required this.config,
  });

  /// Génère un emploi du temps complet
  Future<EmploiDuTemps> generer({Function(String)? onProgress, Classe? targetClass}) async {
    onProgress?.call('Préparation des cours...');
    List<Cours> coursAPlaceer = _preparerCoursAPlaceer(targetClass: targetClass);
    List<Cours> coursPlaces = [];

    onProgress?.call('Tri par priorité...');
    coursAPlaceer.sort((a, b) => _calculerPriorite(b).compareTo(_calculerPriorite(a)));

    int total = coursAPlaceer.length;
    int placed = 0;

    for (var cours in coursAPlaceer) {
      onProgress?.call('Placement des cours: $placed/$total');
      
      Cours? coursPlace = await _placerCours(cours, coursPlaces);
      
      if (coursPlace != null) {
        coursPlaces.add(coursPlace);
        placed++;
      } else {
        print('⚠️ Impossible de placer le cours ${cours.id} - Classe: ${cours.classeId}, Matière: ${cours.matiereId}');
      }
    }

    onProgress?.call('Évaluation finale...');
    double score = _evaluerEmploiDuTemps(coursPlaces);

    onProgress?.call('Terminé ! ${coursPlaces.length}/$total cours placés');

    return EmploiDuTemps(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      nom: 'Emploi du temps ${DateTime.now().year}',
      dateDebut: DateTime.now(),
      dateFin: DateTime.now().add(Duration(days: 365)),
      cours: coursPlaces,
      score: score,
    );
  }

  /// Prépare la liste de tous les cours à placer
  List<Cours> _preparerCoursAPlaceer({Classe? targetClass}) {
    List<Cours> cours = [];
    int idCounter = 0;

    final classesToProcess = targetClass != null ? [targetClass] : classes;
    for (var classe in classesToProcess) {
      for (var matiere in matieres) {
        // Trouver un prof qui enseigne cette matière
        var prof = professeurs.firstWhere(
          (p) => p.matieresIds.contains(matiere.id),
          orElse: () {
            print('⚠️ Aucun professeur trouvé pour ${matiere.nom}');
            return professeurs.first;
          },
        );

        // Créer autant de cours que nécessaire selon le volume horaire
        for (int i = 0; i < matiere.nombreSeances; i++) {
          cours.add(Cours(
            id: 'cours_${idCounter++}',
            classeId: classe.id,
            matiereId: matiere.id,
            professeurId: prof.id,
          ));
        }
      }
    }

    return cours;
  }

  /// Place un cours dans un créneau valide
  Future<Cours?> _placerCours(Cours cours, List<Cours> coursPlaces) async {
    List<Creneau> creneauxPossibles = _trouverCreneauxValides(cours, coursPlaces);

    if (creneauxPossibles.isEmpty) {
      print('❌ Aucun créneau valide pour cours ${cours.id}');
      return null;
    }

    // Évaluer chaque créneau et choisir le meilleur
    Creneau? meilleurCreneau;
    double meilleurScore = double.negativeInfinity;

    for (var creneau in creneauxPossibles) {
      double score = _evaluerCreneau(cours, creneau, coursPlaces);
      if (score > meilleurScore) {
        meilleurScore = score;
        meilleurCreneau = creneau;
      }
    }

    if (meilleurCreneau == null) return null;

    // Trouver une salle disponible
    Salle? salle = _trouverSalleDisponible(cours, meilleurCreneau, coursPlaces);

    if (salle == null) {
      print('⚠️ Aucune salle disponible pour cours ${cours.id} au créneau ${meilleurCreneau.jour}-${meilleurCreneau.heureDebutFormat}');
    }

    return cours.copyWith(
      creneau: meilleurCreneau,
      salleId: salle?.id,
    );
  }

  /// Trouve tous les créneaux valides pour un cours
  List<Creneau> _trouverCreneauxValides(Cours cours, List<Cours> coursPlaces) {
    List<Creneau> creneauxValides = [];
    Matiere matiere = matieres.firstWhere((m) => m.id == cours.matiereId);
    Professeur prof = professeurs.firstWhere((p) => p.id == cours.professeurId);

    for (int jour = 0; jour < config.joursParSemaine; jour++) {
      for (var heureDebut in config.heuresDebut) {
        Creneau creneau = Creneau(
          jour: jour,
          heureDebut: heureDebut,
          duree: matiere.dureeSceance,
        );

        // Vérifier que le cours ne déborde pas sur la pause
        if (_debordeSurPause(creneau)) continue;

        if (_estCreneauValide(cours, creneau, coursPlaces, prof)) {
          creneauxValides.add(creneau);
        }
      }
    }

    return creneauxValides;
  }

  /// Vérifie si un créneau déborde sur la pause déjeuner
  bool _debordeSurPause(Creneau creneau) {
    return creneau.heureDebut < config.pauseDejeunerFin && 
           creneau.heureFin > config.pauseDejeunerDebut;
  }

  /// Vérifie si un créneau est valide (contraintes dures)
  bool _estCreneauValide(
    Cours cours,
    Creneau creneau,
    List<Cours> coursPlaces,
    Professeur prof,
  ) {
    // Vérifier disponibilité professeur
    if (prof.disponibilites.isNotEmpty) {
      bool disponible = prof.disponibilites.any((d) => d.contientCreneau(creneau));
      if (!disponible) return false;
    }

    // Vérifier que le prof n'a pas déjà un cours à ce créneau
    bool profOccupe = coursPlaces.any((c) =>
        c.professeurId == cours.professeurId &&
        c.creneau != null &&
        c.creneau!.chevauche(creneau));
    if (profOccupe) return false;

    // Vérifier que la classe n'a pas déjà un cours à ce créneau
    bool classeOccupee = coursPlaces.any((c) =>
        c.classeId == cours.classeId &&
        c.creneau != null &&
        c.creneau!.chevauche(creneau));
    if (classeOccupee) return false;

    // Vérifier que le créneau est dans les heures de cours
    if (creneau.heureFin > config.heureFin) return false;

    // Vérifier le nombre max d'heures par jour du prof
    int heuresProf = _compterHeuresProf(prof.id, creneau.jour, coursPlaces);
    if (heuresProf + creneau.duree > prof.maxHeuresParJour * 60) return false;

    return true;
  }

  /// Compte les heures déjà attribuées à un prof pour un jour donné
  int _compterHeuresProf(String profId, int jour, List<Cours> coursPlaces) {
    return coursPlaces
        .where((c) => c.professeurId == profId && c.creneau?.jour == jour)
        .fold(0, (sum, c) => sum + (c.creneau?.duree ?? 0));
  }

  /// Évalue la qualité d'un créneau (contraintes souples)
  double _evaluerCreneau(Cours cours, Creneau creneau, List<Cours> coursPlaces) {
    double score = 0.0;
    Matiere matiere = matieres.firstWhere((m) => m.id == cours.matiereId);

    // Favoriser le matin pour les matières difficiles
    if (matiere.niveauDifficulte >= 4 && creneau.heureDebut < 720) {
      score += 10.0;
    }

    // Pénaliser l'après-midi tardif pour les matières difficiles
    if (matiere.niveauDifficulte >= 4 && creneau.heureDebut > 840) {
      score -= 15.0;
    }

    // Éviter les trous dans l'emploi du temps de la classe
    var coursClasse = coursPlaces
        .where((c) => c.classeId == cours.classeId && c.creneau?.jour == creneau.jour)
        .toList();

    if (coursClasse.isNotEmpty) {
      bool aTrou = _verifierTrou(creneau, coursClasse);
      if (aTrou) score -= 20.0;
    }

    // Favoriser le regroupement des cours d'un même prof
    var coursProf = coursPlaces
        .where((c) => c.professeurId == cours.professeurId && c.creneau?.jour == creneau.jour)
        .toList();

    if (coursProf.isNotEmpty) {
      score += 5.0;
    }

    // Alterner théorie et pratique
    if (coursClasse.isNotEmpty) {
      var dernierCours = coursClasse.last;
      var derniereMatiere = matieres.firstWhere(
        (m) => m.id == dernierCours.matiereId,
        orElse: () => matiere,
      );
      
      if (derniereMatiere.type != matiere.type) {
        score += 8.0;
      }
    }

    // Bonus pour début de journée (éviter de commencer trop tard)
    if (creneau.heureDebut == config.heureDebut) {
      score += 3.0;
    }

    return score;
  }

  /// Vérifie s'il y a un trou dans l'emploi du temps
  bool _verifierTrou(Creneau nouveauCreneau, List<Cours> coursExistants) {
    for (var cours in coursExistants) {
      if (cours.creneau == null) continue;
      
      int ecart = (nouveauCreneau.heureDebut - cours.creneau!.heureFin).abs();
      
      // Trou entre 1h et 3h (en excluant la pause déjeuner)
      if (ecart > 60 && ecart < 180) {
        // Vérifier que ce n'est pas la pause déjeuner
        bool pauseEntreDeuxCours = 
            (cours.creneau!.heureFin <= config.pauseDejeunerDebut && 
             nouveauCreneau.heureDebut >= config.pauseDejeunerFin) ||
            (nouveauCreneau.heureFin <= config.pauseDejeunerDebut && 
             cours.creneau!.heureDebut >= config.pauseDejeunerFin);
        
        if (!pauseEntreDeuxCours) {
          return true;
        }
      }
    }
    return false;
  }

  /// Trouve une salle disponible pour un cours
  Salle? _trouverSalleDisponible(Cours cours, Creneau creneau, List<Cours> coursPlaces) {
    Classe classe = classes.firstWhere((c) => c.id == cours.classeId);
    Matiere matiere = matieres.firstWhere((m) => m.id == cours.matiereId);

    // Trier les salles par préférence
    List<Salle> sallesDisponibles = [];

    for (var salle in salles) {
      // Vérifier la capacité
      if (salle.capacite < classe.nombreEleves) continue;

      // Vérifier la disponibilité
      bool salleOccupee = coursPlaces.any((c) =>
          c.salleId == salle.id &&
          c.creneau != null &&
          c.creneau!.chevauche(creneau));

      if (salleOccupee) continue;

      // Vérifier le type de salle pour les matières spéciales
      if (matiere.necessiteSalleSpeciale) {
        if (matiere.type == TypeMatiere.sport && salle.type != TypeSalle.sport) continue;
        if (matiere.type == TypeMatiere.pratique && 
            salle.type != TypeSalle.laboratoire && 
            salle.type != TypeSalle.atelier) continue;
      }

      sallesDisponibles.add(salle);
    }

    if (sallesDisponibles.isEmpty) return null;

    // Retourner la salle la plus appropriée (la plus petite qui convient)
    sallesDisponibles.sort((a, b) => a.capacite.compareTo(b.capacite));
    return sallesDisponibles.first;
  }

  /// Calcule la priorité d'un cours (pour le tri)
  double _calculerPriorite(Cours cours) {
    double priorite = 0.0;
    
    Matiere matiere = matieres.firstWhere((m) => m.id == cours.matiereId);
    Professeur prof = professeurs.firstWhere((p) => p.id == cours.professeurId);

    // Prioriser les matières avec salles spéciales
    if (matiere.necessiteSalleSpeciale) priorite += 50.0;
    
    // Prioriser les profs avec beaucoup de matières
    priorite += prof.matieresIds.length * 10.0;
    
    // Prioriser les matières avec beaucoup d'heures
    priorite += matiere.volumeHoraireHebdo * 2.0;

    // Prioriser les cours longs (plus difficiles à placer)
    if (matiere.dureeSceance > 60) priorite += 15.0;

    return priorite;
  }

  /// Évalue la qualité globale de l'emploi du temps
  double _evaluerEmploiDuTemps(List<Cours> cours) {
    double score = 0.0;

    // Taux de placement (0-1000 points)
    int coursTotal = 0;
    for (var classe in classes) {
      for (var matiere in matieres) {
        coursTotal += matiere.nombreSeances;
      }
    }
    
    int coursPlaces = cours.where((c) => c.creneau != null).length;
    score += (coursPlaces / coursTotal) * 1000;

    // Bonus pour équilibre de charge par jour pour chaque classe
    for (var classe in classes) {
      Map<int, int> heuresParJour = {};
      for (int jour = 0; jour < config.joursParSemaine; jour++) {
        heuresParJour[jour] = 0;
      }

      var coursClasse = cours.where((c) => c.classeId == classe.id);
      for (var c in coursClasse) {
        if (c.creneau != null) {
          heuresParJour[c.creneau!.jour] = 
              (heuresParJour[c.creneau!.jour] ?? 0) + c.creneau!.duree;
        }
      }

      // Calculer l'écart-type (moins il est élevé, mieux c'est)
      var valeurs = heuresParJour.values.toList();
      if (valeurs.isNotEmpty) {
        double moyenne = valeurs.reduce((a, b) => a + b) / valeurs.length;
        double variance = valeurs.map((v) => pow(v - moyenne, 2)).reduce((a, b) => a + b) / valeurs.length;
        double ecartType = sqrt(variance);
        
        score -= ecartType * 0.5;
      }
    }

    // Pénalité pour cours sans salle
    int coursSansSalle = cours.where((c) => c.creneau != null && c.salleId == null).length;
    score -= coursSansSalle * 5;

    return score;
  }
}