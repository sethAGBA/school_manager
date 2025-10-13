class Class {
  final String name;
  final String academicYear;
  final String? titulaire;
  final double? fraisEcole;
  final double? fraisCotisationParallele;
  // Seuils de passage personnalisés par classe
  final double seuilFelicitations;
  final double seuilEncouragements;
  final double seuilAdmission;
  final double seuilAvertissement;
  final double seuilConditions;
  final double seuilRedoublement;

  Class({
    required this.name,
    required this.academicYear,
    this.titulaire,
    this.fraisEcole,
    this.fraisCotisationParallele,
    this.seuilFelicitations = 16.0,
    this.seuilEncouragements = 14.0,
    this.seuilAdmission = 12.0,
    this.seuilAvertissement = 10.0,
    this.seuilConditions = 8.0,
    this.seuilRedoublement = 8.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'academicYear': academicYear,
      'titulaire': titulaire,
      'fraisEcole': fraisEcole,
      'fraisCotisationParallele': fraisCotisationParallele,
      'seuilFelicitations': seuilFelicitations,
      'seuilEncouragements': seuilEncouragements,
      'seuilAdmission': seuilAdmission,
      'seuilAvertissement': seuilAvertissement,
      'seuilConditions': seuilConditions,
      'seuilRedoublement': seuilRedoublement,
    };
  }

  factory Class.fromMap(Map<String, dynamic> map) {
    return Class(
      name: map['name'],
      academicYear: map['academicYear'],
      titulaire: map['titulaire'],
      fraisEcole: map['fraisEcole'] != null
          ? (map['fraisEcole'] as num).toDouble()
          : null,
      fraisCotisationParallele: map['fraisCotisationParallele'] != null
          ? (map['fraisCotisationParallele'] as num).toDouble()
          : null,
      seuilFelicitations: (map['seuilFelicitations'] as num?)?.toDouble() ?? 16.0,
      seuilEncouragements: (map['seuilEncouragements'] as num?)?.toDouble() ?? 14.0,
      seuilAdmission: (map['seuilAdmission'] as num?)?.toDouble() ?? 12.0,
      seuilAvertissement: (map['seuilAvertissement'] as num?)?.toDouble() ?? 10.0,
      seuilConditions: (map['seuilConditions'] as num?)?.toDouble() ?? 8.0,
      seuilRedoublement: (map['seuilRedoublement'] as num?)?.toDouble() ?? 8.0,
    );
  }

  factory Class.empty() => Class(
    name: '',
    academicYear: '',
    titulaire: '',
    fraisEcole: 0,
    fraisCotisationParallele: 0,
    seuilFelicitations: 16.0,
    seuilEncouragements: 14.0,
    seuilAdmission: 12.0,
    seuilAvertissement: 10.0,
    seuilConditions: 8.0,
    seuilRedoublement: 8.0,
  );
}
