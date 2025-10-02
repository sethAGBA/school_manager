class Student {
  final String id;
  final String name;
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

  Student({
    required this.id,
    required this.name,
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
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'dateOfBirth': dateOfBirth,
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
    return Student(
      id: map['id'],
      name: map['name'],
      dateOfBirth: map['dateOfBirth'],
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
    name: '',
    dateOfBirth: '',
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
