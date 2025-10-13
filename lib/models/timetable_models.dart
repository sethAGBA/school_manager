// models/classe.dart
class Classe {
  final String id;
  final String nom;
  final String niveau;
  final String section;
  final int nombreEleves;
  final String academicYear;

  Classe({
    required this.id,
    required this.nom,
    required this.niveau,
    required this.section,
    required this.nombreEleves,
    required this.academicYear,
  });
}

// models/professeur.dart
class Professeur {
  final String id;
  final String nom;
  final String prenom;
  final List<String> matieresIds;
  final List<String> classes = [];
  final List<Disponibilite> disponibilites;
  final int maxHeuresParJour;
  final int maxHeuresParSemaine;
  final String academicYear;

  Professeur({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.matieresIds,
    this.disponibilites = const [],
    this.maxHeuresParJour = 6,
    this.maxHeuresParSemaine = 24,
    required this.academicYear,
  });
}

// models/matiere.dart
class Matiere {
  final String id;
  final String nom;
  final int volumeHoraireHebdo; // en heures
  final int dureeSceance; // en minutes (ex: 60, 90, 120)
  final TypeMatiere type;
  final bool necessiteSalleSpeciale;
  final int niveauDifficulte; // 1-5 (pour optimisation matin/après-midi)
  final String academicYear;

  Matiere({
    required this.id,
    required this.nom,
    required this.volumeHoraireHebdo,
    this.dureeSceance = 60,
    this.type = TypeMatiere.theorique,
    this.necessiteSalleSpeciale = false,
    this.niveauDifficulte = 3,
    required this.academicYear,
  });

  int get nombreSeances => (volumeHoraireHebdo * 60) ~/ dureeSceance;
}

enum TypeMatiere { theorique, pratique, sport, artistique }

// models/salle.dart
class Salle {
  final String id;
  final String nom;
  final int capacite;
  final TypeSalle type;
  final List<String> equipements;

  Salle({
    required this.id,
    required this.nom,
    required this.capacite,
    this.type = TypeSalle.standard,
    this.equipements = const [],
  });
}

enum TypeSalle { standard, laboratoire, informatique, sport, atelier }

// models/creneau.dart
class Creneau {
  final int jour; // 0 = Lundi, 4 = Vendredi
  final int heureDebut; // en minutes depuis 00:00 (ex: 480 = 8h00)
  final int duree; // en minutes

  Creneau({
    required this.jour,
    required this.heureDebut,
    required this.duree,
  });

  int get heureFin => heureDebut + duree;

  bool chevauche(Creneau autre) {
    if (jour != autre.jour) return false;
    return heureDebut < autre.heureFin && heureFin > autre.heureDebut;
  }

  String get heureDebutFormat {
    int h = heureDebut ~/ 60;
    int m = heureDebut % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String get heureFinFormat {
    int h = heureFin ~/ 60;
    int m = heureFin % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Creneau &&
          jour == other.jour &&
          heureDebut == other.heureDebut &&
          duree == other.duree;

  @override
  int get hashCode => Object.hash(jour, heureDebut, duree);
}

// models/disponibilite.dart
class Disponibilite {
  final int jour;
  final int heureDebut;
  final int heureFin;

  Disponibilite({
    required this.jour,
    required this.heureDebut,
    required this.heureFin,
  });

  bool contientCreneau(Creneau creneau) {
    if (jour != creneau.jour) return false;
    return heureDebut <= creneau.heureDebut && heureFin >= creneau.heureFin;
  }
}

// models/cours.dart
class Cours {
  final String id;
  final String classeId;
  final String matiereId;
  final String professeurId;
  final String? salleId;
  final Creneau? creneau;

  Cours({
    required this.id,
    required this.classeId,
    required this.matiereId,
    required this.professeurId,
    this.salleId,
    this.creneau,
  });

  Cours copyWith({
    String? salleId,
    Creneau? creneau,
  }) {
    return Cours(
      id: id,
      classeId: classeId,
      matiereId: matiereId,
      professeurId: professeurId,
      salleId: salleId ?? this.salleId,
      creneau: creneau ?? this.creneau,
    );
  }
}

// models/emploi_du_temps.dart
class EmploiDuTemps {
  final String id;
  final String nom;
  final DateTime dateDebut;
  final DateTime dateFin;
  final List<Cours> cours;
  final double score;

  EmploiDuTemps({
    required this.id,
    required this.nom,
    required this.dateDebut,
    required this.dateFin,
    this.cours = const [],
    this.score = 0.0,
  });

  List<Cours> getCoursParClasse(String classeId) {
    return cours.where((c) => c.classeId == classeId).toList();
  }

  List<Cours> getCoursParProfesseur(String profId) {
    return cours.where((c) => c.professeurId == profId).toList();
  }

  List<Cours> getCoursParCreneau(Creneau creneau) {
    return cours.where((c) => c.creneau == creneau).toList();
  }

  EmploiDuTemps copyWith({List<Cours>? cours, double? score}) {
    return EmploiDuTemps(
      id: id,
      nom: nom,
      dateDebut: dateDebut,
      dateFin: dateFin,
      cours: cours ?? this.cours,
      score: score ?? this.score,
    );
  }
}