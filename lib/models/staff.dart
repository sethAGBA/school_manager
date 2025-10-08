// import 'package:flutter/foundation.dart';

class Staff {
  final String id;
  final String name;
  final String role;
  final String department;
  final String phone;
  final String email;
  final String qualifications;
  final List<String> courses; // Liste des cours assignés
  final List<String> classes; // Liste des classes assignées
  final String status;
  final DateTime hireDate;
  final String typeRole; // 'Professeur' ou 'Administration'

  // --- Nouveaux champs ajoutés ---
  final String? firstName;
  final String? lastName;
  final String? gender;
  final DateTime? birthDate;
  final String? birthPlace;
  final String? nationality;
  final String? address; // adresse complète (ville, quartier, pays)
  final String? photoPath;

  // Identifiants administratifs
  final String? matricule; // matricule enseignant
  final String? idNumber; // CNI / passeport
  final String? socialSecurityNumber;
  final String? maritalStatus;
  final int? numberOfChildren;

  // Professionnel / infos complémentaires
  final String? region; // région d'affectation
  final List<String>? levels; // niveaux enseignés
  final String? highestDegree; // diplôme le plus élevé
  final String? specialty; // spécialité / domaine
  final int? experienceYears;
  final String? previousInstitution;

  // Contractuel
  final String? contractType; // CDI, CDD, Vacataire
  final double? baseSalary;
  final int? weeklyHours; // heures de cours hebdomadaires prévues
  final String? supervisor; // responsable hiérarchique
  final DateTime? retirementDate;

  // Documents: stocker chemins vers fichiers (CSV en base)
  final List<String>? documents;

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.department,
    required this.phone,
    required this.email,
    required this.qualifications,
    required this.courses,
    required this.classes,
    required this.status,
    required this.hireDate,
    required this.typeRole,
    this.firstName,
    this.lastName,
    this.gender,
    this.birthDate,
    this.birthPlace,
    this.nationality,
    this.address,
    this.photoPath,
    this.matricule,
    this.idNumber,
    this.socialSecurityNumber,
    this.maritalStatus,
    this.numberOfChildren,
    this.region,
    this.levels,
    this.highestDegree,
    this.specialty,
    this.experienceYears,
    this.previousInstitution,
    this.contractType,
    this.baseSalary,
    this.weeklyHours,
    this.supervisor,
    this.retirementDate,
    this.documents,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'department': department,
      'phone': phone,
      'email': email,
      'qualifications': qualifications,
      'courses': courses.join(','),
      'classes': classes.join(','),
      'status': status,
      'hireDate': hireDate.toIso8601String(),
      'typeRole': typeRole,
      'first_name': firstName,
      'last_name': lastName,
      'gender': gender,
      'birth_date': birthDate?.toIso8601String(),
      'birth_place': birthPlace,
      'nationality': nationality,
      'address': address,
      'photo': photoPath,
      'matricule': matricule,
      'id_number': idNumber,
      'social_security': socialSecurityNumber,
      'marital_status': maritalStatus,
      'number_of_children': numberOfChildren,
      'region': region,
      'levels': levels?.join(','),
      'highest_degree': highestDegree,
      'specialty': specialty,
      'experience_years': experienceYears,
      'previous_institution': previousInstitution,
      'contract_type': contractType,
      'base_salary': baseSalary,
      'weekly_hours': weeklyHours,
      'supervisor': supervisor,
      'retirement_date': retirementDate?.toIso8601String(),
      'documents': documents?.join(','),
    };
  }

  factory Staff.fromMap(Map<String, dynamic> map) {
    List<String> _splitList(dynamic v) {
      if (v == null) return [];
      final s = v.toString();
      if (s.trim().isEmpty) return [];
      return s
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return Staff(
      id: map['id'],
      name: map['name'] ?? '',
      role: map['role'] ?? '',
      department: map['department'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      qualifications: map['qualifications'] ?? '',
      courses: _splitList(map['courses']),
      classes: _splitList(map['classes']),
      status: map['status'] ?? 'Actif',
      hireDate: map['hireDate'] != null
          ? DateTime.parse(map['hireDate'])
          : DateTime.now(),
      typeRole: map['typeRole'] ?? 'Administration',
      firstName: map['first_name'],
      lastName: map['last_name'],
      gender: map['gender'],
      birthDate: map['birth_date'] != null
          ? DateTime.tryParse(map['birth_date'])
          : null,
      birthPlace: map['birth_place'],
      nationality: map['nationality'],
      address: map['address'],
      photoPath: map['photo'],
      matricule: map['matricule'],
      idNumber: map['id_number'],
      socialSecurityNumber: map['social_security'],
      maritalStatus: map['marital_status'],
      numberOfChildren: map['number_of_children'] != null
          ? int.tryParse(map['number_of_children'].toString())
          : null,
      region: map['region'],
      levels: _splitList(map['levels']),
      highestDegree: map['highest_degree'],
      specialty: map['specialty'],
      experienceYears: map['experience_years'] != null
          ? int.tryParse(map['experience_years'].toString())
          : null,
      previousInstitution: map['previous_institution'],
      contractType: map['contract_type'],
      baseSalary: map['base_salary'] != null
          ? double.tryParse(map['base_salary'].toString())
          : null,
      weeklyHours: map['weekly_hours'] != null
          ? int.tryParse(map['weekly_hours'].toString())
          : null,
      supervisor: map['supervisor'],
      retirementDate: map['retirement_date'] != null
          ? DateTime.tryParse(map['retirement_date'])
          : null,
      documents: _splitList(map['documents']),
    );
  }

  factory Staff.empty() => Staff(
    id: '',
    name: '',
    role: '',
    department: '',
    phone: '',
    email: '',
    qualifications: '',
    courses: [],
    classes: [],
    status: 'Actif',
    hireDate: DateTime.now(),
    typeRole: 'Administration',
  );
}
