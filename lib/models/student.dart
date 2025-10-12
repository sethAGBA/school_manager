class Student {
  final String id;
  final String firstName;
  final String lastName;
  final String dateOfBirth;
  final String address;
  final String gender;
  final String contactNumber;
  final String email;
  final String emergencyContact;
  final String guardianName;
  final String guardianContact;
  final String className;
  final String academicYear;
  final String enrollmentDate;
  final String status; // Nouveau, Redoublant, etc.
  final String? medicalInfo;
  final String? photoPath;
  final String? matricule; // Numéro de matricule
  final String? placeOfBirth; // Lieu de naissance

  // Getter pour le nom complet (compatibilité)
  String get name => '$firstName $lastName'.trim();

  Student({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.address,
    required this.gender,
    required this.contactNumber,
    required this.email,
    required this.emergencyContact,
    required this.guardianName,
    required this.guardianContact,
    required this.className,
    required this.academicYear,
    required this.enrollmentDate,
    this.status = 'Nouveau',
    this.medicalInfo,
    this.photoPath,
    this.matricule,
    this.placeOfBirth,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'name': name, // Pour compatibilité
      'dateOfBirth': dateOfBirth,
      'placeOfBirth': placeOfBirth,
      'address': address,
      'gender': gender,
      'contactNumber': contactNumber,
      'email': email,
      'emergencyContact': emergencyContact,
      'guardianName': guardianName,
      'guardianContact': guardianContact,
      'className': className,
      'academicYear': academicYear,
      'enrollmentDate': enrollmentDate,
      'status': status,
      'medicalInfo': medicalInfo,
      'photoPath': photoPath,
      'matricule': matricule,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    // Gestion de la migration : si firstName/lastName n'existent pas, utiliser name
    String firstName = map['firstName'] ?? '';
    String lastName = map['lastName'] ?? '';
    
    // Si les nouveaux champs sont vides mais que name existe, essayer de les extraire
    if (firstName.isEmpty && lastName.isEmpty && map['name'] != null) {
      final nameParts = (map['name'] as String).split(' ');
      if (nameParts.length == 1) {
        firstName = nameParts.first;
        lastName = '';
      } else if (nameParts.length == 2) {
        firstName = nameParts.first;
        lastName = nameParts.last;
      } else {
        // Plus de 2 mots : tous sauf le dernier sont des prénoms
        firstName = nameParts.sublist(0, nameParts.length - 1).join(' ');
        lastName = nameParts.last;
      }
    }
    
    return Student(
      id: map['id'],
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: map['dateOfBirth'],
      placeOfBirth: map['placeOfBirth'],
      address: map['address'],
      gender: map['gender'],
      contactNumber: map['contactNumber'],
      email: map['email'],
      emergencyContact: map['emergencyContact'],
      guardianName: map['guardianName'],
      guardianContact: map['guardianContact'],
      className: map['className'],
      academicYear: map['academicYear'] ?? '',
      enrollmentDate: map['enrollmentDate'],
      status: map['status'] ?? 'Nouveau',
      medicalInfo: map['medicalInfo'],
      photoPath: map['photoPath'],
      matricule: map['matricule'],
    );
  }

  factory Student.empty() => Student(
    id: '',
    firstName: '',
    lastName: '',
    dateOfBirth: '',
    placeOfBirth: '',
    address: '',
    gender: '',
    contactNumber: '',
    email: '',
    emergencyContact: '',
    guardianName: '',
    guardianContact: '',
    className: '',
    academicYear: '',
    enrollmentDate: '',
    status: 'Nouveau',
    medicalInfo: '',
    photoPath: '',
    matricule: '',
  );
}
