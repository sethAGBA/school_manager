class Class {
  final String name;
  final String academicYear;
  final String? titulaire;
  final double? fraisEcole;
  final double? fraisCotisationParallele;

  Class({
    required this.name,
    required this.academicYear,
    this.titulaire,
    this.fraisEcole,
    this.fraisCotisationParallele,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'academicYear': academicYear,
      'titulaire': titulaire,
      'fraisEcole': fraisEcole,
      'fraisCotisationParallele': fraisCotisationParallele,
    };
  }

  factory Class.fromMap(Map<String, dynamic> map) {
    return Class(
      name: map['name'],
      academicYear: map['academicYear'],
      titulaire: map['titulaire'],
      fraisEcole: map['fraisEcole'] != null ? (map['fraisEcole'] as num).toDouble() : null,
      fraisCotisationParallele: map['fraisCotisationParallele'] != null ? (map['fraisCotisationParallele'] as num).toDouble() : null,
    );
  }

  factory Class.empty() => Class(
    name: '',
    academicYear: '',
    titulaire: '',
    fraisEcole: 0,
    fraisCotisationParallele: 0,
  );
}