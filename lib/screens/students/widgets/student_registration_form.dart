import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:school_manager/constants/sizes.dart';
import 'package:school_manager/constants/strings.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:uuid/uuid.dart';
// shared_preferences not used in this file
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/utils/date_formatter.dart';

import 'form_field.dart';

class StudentRegistrationForm extends StatefulWidget {
  final VoidCallback onSubmit;
  final Student? student;
  final String? className;
  final bool classFieldReadOnly;

  const StudentRegistrationForm({
    required this.onSubmit,
    this.student,
    this.className,
    this.classFieldReadOnly = false,
    Key? key,
  }) : super(key: key);

  @override
  _StudentRegistrationFormState createState() =>
      _StudentRegistrationFormState();
}

class _StudentRegistrationFormState extends State<StudentRegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();

  String _generateMatricule() {
    const length = 6;
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _studentNameController = TextEditingController();
  final TextEditingController _dateOfBirthController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _emergencyContactController =
      TextEditingController();
  final TextEditingController _guardianNameController = TextEditingController();
  final TextEditingController _guardianContactController =
      TextEditingController();
  final TextEditingController _medicalInfoController = TextEditingController();
    final TextEditingController _studentLastNameController =
        TextEditingController();
    final TextEditingController _placeOfBirthController = TextEditingController();  final TextEditingController _matriculeController = TextEditingController();
  final TextEditingController _academicYearController = TextEditingController();
  final TextEditingController _enrollmentDateController =
      TextEditingController();

  String? _selectedClass;
  String? _selectedGender;
  final TextEditingController _statusController = TextEditingController(
    text: 'Nouveau',
  );
  File? _studentPhoto;
  List<Class> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
    if (widget.student != null) {
      final s = widget.student!;
      _studentIdController.text = s.id;
      _matriculeController.text = s.matricule ?? _generateMatricule();
      _academicYearController.text = s.academicYear;
      // enrollmentDate stored as ISO
      try {
        final ed = DateTime.tryParse(s.enrollmentDate);
        if (ed != null) {
          _enrollmentDateController.text = formatDdMmYyyy(ed);
        }
      } catch (_) {}
      // Charger les prénoms et noms séparément
      _studentNameController.text = s.firstName;
      _studentLastNameController.text = s.lastName;
      _placeOfBirthController.text = s.placeOfBirth ?? '';
      // dateOfBirth est stockée en ISO; afficher en jj/MM/aaaa
      DateTime? dob;
      try {
        dob = DateTime.tryParse(s.dateOfBirth);
      } catch (_) {
        dob = parseDdMmYyyy(s.dateOfBirth);
      }
      _dateOfBirthController.text = formatDdMmYyyy(dob);
      _addressController.text = s.address;
      _selectedGender = s.gender;
      _contactNumberController.text = s.contactNumber;
      _emailController.text = s.email;
      _emergencyContactController.text = s.emergencyContact;
      _guardianNameController.text = s.guardianName;
      _guardianContactController.text = s.guardianContact;
      _selectedClass = s.className;
      _medicalInfoController.text = s.medicalInfo ?? '';
      // statut libre saisi par l'utilisateur
      _statusController.text = (s.status.isNotEmpty) ? s.status : 'Nouveau';
      if (s.photoPath != null && File(s.photoPath!).existsSync()) {
        _studentPhoto = File(s.photoPath!);
      }
    } else if (widget.className != null) {
      _selectedClass = widget.className;
      _studentIdController.text = const Uuid().v4();
      _matriculeController.text = _generateMatricule();
    } else {
      _studentIdController.text = const Uuid().v4();
      _matriculeController.text = _generateMatricule();
    }
    // Pré-remplir les champs année scolaire et date d'inscription pour une nouvelle fiche
    getCurrentAcademicYear().then((year) {
      if (_academicYearController.text.isEmpty) {
        _academicYearController.text = year;
      }
      if (_enrollmentDateController.text.isEmpty) {
        _enrollmentDateController.text = formatDdMmYyyy(DateTime.now());
      }
      if (_selectedClass == null && _studentIdController.text.isEmpty) {
        // Nouvelle inscription
        _dateOfBirthController.text = '';
      }
    });
  }

  Future<void> _loadClasses() async {
    try {
      final classes = await _dbService.getClasses();
      final currentYear = await getCurrentAcademicYear();
      // When adding a new student, restrict to classes from current academic year.
      // When editing, keep all classes to preserve original class if from a past year.
      final filtered = widget.student == null
          ? classes.where((c) => c.academicYear == currentYear).toList()
          : classes;
      print(
        'Loaded ${filtered.length} classes (currentYear=$currentYear, editing=${widget.student != null})',
      );
      setState(() {
        _classes = filtered;
      });
    } catch (e) {
      print('Error loading classes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors du chargement des classes')),
      );
    }
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _studentNameController.dispose();
    _dateOfBirthController.dispose();
    _addressController.dispose();
    _contactNumberController.dispose();
    _emailController.dispose();
    _emergencyContactController.dispose();
    _guardianNameController.dispose();
    _guardianContactController.dispose();
    _medicalInfoController.dispose();
    _statusController.dispose();
    _studentLastNameController.dispose();
    _placeOfBirthController.dispose();
    _matriculeController.dispose();
    _academicYearController.dispose();
    _enrollmentDateController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.single.path;
        if (filePath != null) {
          // Evict any cached image for this path before updating
          try {
            await FileImage(File(filePath)).evict();
          } catch (_) {}
          setState(() {
            _studentPhoto = File(filePath);
          });
        }
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de sélectionner l’image')),
      );
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dateOfBirthController.text = formatDdMmYyyy(picked);
      });
    }
  }

  Future<String?> _savePhoto(File photo) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(photo.path).toLowerCase();
      final photoPath = path.join(
        directory.path,
        'photos',
        'student_${_studentIdController.text}_$timestamp$extension',
      );
      final photoFile = File(photoPath);
      await photoFile.create(recursive: true);
      await photo.copy(photoPath);
      return photoPath;
    } catch (e) {
      print('Error saving photo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’enregistrer l’image')),
      );
      return null;
    }
  }

  void resetForm() {
    _formKey.currentState?.reset();
    _studentIdController.clear();
    _studentNameController.clear();
    _studentLastNameController.clear();
    _placeOfBirthController.clear();
    _matriculeController.clear();
    _academicYearController.clear();
    _enrollmentDateController.clear();
    _dateOfBirthController.clear();
    _addressController.clear();
    _contactNumberController.clear();
    _emailController.clear();
    _emergencyContactController.clear();
    _guardianNameController.clear();
    _guardianContactController.clear();
    _medicalInfoController.clear();
    _statusController.text = 'Nouveau';

    setState(() {
      _selectedClass = widget.className;
      _selectedGender = null;
      _studentPhoto = null;
    });

    // Generate new UUID for new student
    if (widget.student == null) {
      _studentIdController.text = const Uuid().v4();
      _matriculeController.text = _generateMatricule();
      // default academic year and enrollment date for new record
      getCurrentAcademicYear().then((year) {
        setState(() {
          _academicYearController.text = year;
          _enrollmentDateController.text = formatDdMmYyyy(DateTime.now());
        });
      });
    }
  }

  void submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_classes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aucune classe disponible. Ajoutez une classe d’abord.',
            ),
          ),
        );
        return;
      }
      String? photoPath;
      if (_studentPhoto != null) {
        photoPath = await _savePhoto(_studentPhoto!);
      }
      final student = Student(
        id: _studentIdController.text,
        firstName: _studentNameController.text,
        lastName: _studentLastNameController.text,
        placeOfBirth: _placeOfBirthController.text.isEmpty
            ? null
            : _placeOfBirthController.text,
        dateOfBirth: parseDdMmYyyy(
          _dateOfBirthController.text,
        )!.toIso8601String(),
        address: _addressController.text,
        gender: _selectedGender!,
        contactNumber: _contactNumberController.text,
        email: _emailController.text,
        emergencyContact: _emergencyContactController.text,
        guardianName: _guardianNameController.text,
        guardianContact: _guardianContactController.text,
        className: _selectedClass!,
        academicYear: _academicYearController.text.isNotEmpty
            ? _academicYearController.text
            : await getCurrentAcademicYear(),
        enrollmentDate:
            (parseDdMmYyyy(_enrollmentDateController.text) ?? DateTime.now())
                .toIso8601String(),
        status: _statusController.text.trim().isEmpty
            ? 'Nouveau'
            : _statusController.text.trim(),
        medicalInfo: _medicalInfoController.text.isEmpty
            ? null
            : _medicalInfoController.text,
        photoPath: photoPath,
        matricule: _matriculeController.text.isEmpty
            ? null
            : _matriculeController.text,
      );
      try {
        if (widget.student != null) {
          // update
          await _dbService.updateStudent(widget.student!.id, student);
        } else {
          // insert
          await _dbService.insertStudent(student);
        }
        // Fermer le dialog et laisser le parent afficher un Snackbar
        widget.onSubmit();
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
        resetForm();
      } catch (e) {
        print('Error saving student: $e');
        // Afficher une alerte au lieu d'un Snackbar car on est dans un dialog
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Erreur'),
            content: Text('Erreur lors de l\'enregistrement: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('Building StudentRegistrationForm');
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Photo de l’étudiant'),
            _buildPhotoSection(),
            const SizedBox(height: AppSizes.spacing),
            _buildSectionTitle('Détails Personnels'),
            CustomFormField(
              controller: _studentIdController,
              labelText: 'ID Étudiant',
              hintText: 'Généré automatiquement',
              readOnly: true,
              validator: (value) => value!.isEmpty ? AppStrings.required : null,
            ),
            CustomFormField(
              controller: _matriculeController,
              labelText: 'Numéro matricule',
              hintText: 'Entrez le numéro matricule (optionnel)',
            ),
            CustomFormField(
              controller: _studentNameController,
              labelText: 'Prénom(s)',
              hintText: 'Entrez le prénom de l’étudiant',
              validator: (value) => value!.isEmpty ? AppStrings.required : null,
            ),
            CustomFormField(
              controller: _studentLastNameController,
              labelText: 'Nom de famille',
              hintText: 'Entrez le nom de famille de l’étudiant',
              validator: (value) => value!.isEmpty ? AppStrings.required : null,
            ),
            CustomFormField(
              controller: _dateOfBirthController,
              labelText: 'Date de Naissance',
              hintText: 'Sélectionnez la date',
              readOnly: true,
              onTap: _selectDate,
              suffixIcon: Icons.calendar_today,
              validator: (value) => value!.isEmpty ? AppStrings.required : null,
            ),
            CustomFormField(
              controller: _placeOfBirthController,
              labelText: 'Lieu de naissance',
              hintText: 'Entrez le lieu de naissance',
            ),
            CustomFormField(
              controller: _addressController,
              labelText: 'Adresse',
              hintText: 'Entrez l’adresse',
            ),
            CustomFormField(
              isDropdown: true,
              labelText: AppStrings.gender,
              hintText: 'Sélectionnez le sexe',
              dropdownItems: const ['M', 'F'],
              dropdownValue: _selectedGender,
              onDropdownChanged: (value) =>
                  setState(() => _selectedGender = value),
              validator: (value) =>
                  value == null ? 'Veuillez sélectionner le sexe' : null,
            ),
            const SizedBox(height: AppSizes.spacing),
            _buildSectionTitle('Informations de Contact'),
            CustomFormField(
              controller: _contactNumberController,
              labelText: 'Numéro de Contact',
              hintText: 'Entrez le numéro de contact',
            ),
            CustomFormField(
              controller: _emailController,
              labelText: 'Adresse Email',
              hintText: 'Entrez l’adresse email',
            ),
            CustomFormField(
              controller: _emergencyContactController,
              labelText: 'Contact d’Urgence',
              hintText: 'Entrez le nom et numéro de contact d’urgence',
            ),
            const SizedBox(height: AppSizes.spacing),
            _buildSectionTitle('Informations du Tuteur'),
            CustomFormField(
              controller: _guardianNameController,
              labelText: 'Nom du Tuteur',
              hintText: 'Entrez le nom complet du tuteur',
            ),
            CustomFormField(
              controller: _guardianContactController,
              labelText: 'Numéro de Contact du Tuteur',
              hintText: 'Entrez le numéro de contact du tuteur',
            ),
            const SizedBox(height: AppSizes.spacing),
            _buildSectionTitle('Informations Académiques'),
            CustomFormField(
              isDropdown: true,
              labelText: AppStrings.classLabel,
              hintText: _classes.isEmpty
                  ? 'Aucune classe disponible'
                  : 'Sélectionnez la classe',
              dropdownItems: _classes.map((cls) => cls.name).toList(),
              dropdownValue: _selectedClass,
              onDropdownChanged: widget.classFieldReadOnly
                  ? null
                  : (value) => setState(() => _selectedClass = value),
              validator: (value) =>
                  value == null ? 'Veuillez sélectionner une classe' : null,
              readOnly: widget.classFieldReadOnly,
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: _academicYearController,
              labelText: 'Année scolaire',
              hintText: 'Ex: 2024-2025',
              readOnly: true,
            ),
            CustomFormField(
              controller: _enrollmentDateController,
              labelText: 'Date d’inscription',
              hintText: 'Sélectionnez la date d\'inscription',
              readOnly: true,
              onTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() {
                    _enrollmentDateController.text = formatDdMmYyyy(picked);
                  });
                }
              },
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            // Statut de l'élève (saisi libre)
            CustomFormField(
              controller: _statusController,
              labelText: 'Statut',
              hintText: 'Ex: Nouveau, Redoublant, Transfert…',
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Veuillez saisir le statut de l\'élève'
                  : null,
            ),
            const SizedBox(height: AppSizes.spacing),
            _buildSectionTitle('Informations Médicales'),
            CustomFormField(
              controller: _medicalInfoController,
              labelText: 'Informations Médicales',
              hintText: 'Entrez les informations médicales pertinentes',
              isTextArea: true,
            ),
            const SizedBox(height: AppSizes.spacing),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.spacing / 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppSizes.titleFontSize,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).textTheme.bodyLarge!.color,
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSizes.smallSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Photo de l’étudiant',
            style: TextStyle(
              fontSize: AppSizes.textFontSize,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
          const SizedBox(height: AppSizes.smallSpacing / 2),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: double.infinity,
              height: 150,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: _studentPhoto != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _studentPhoto!,
                            key: ValueKey(_studentPhoto!.path),
                            width: double.infinity,
                            height: 150,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(Icons.error, color: Colors.red),
                                ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _studentPhoto = null),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                        SizedBox(height: 4),
                        Text(
                          'Sélectionner une image',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: AppSizes.textFontSize - 2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef StudentRegistrationFormState = _StudentRegistrationFormState;
