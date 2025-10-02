// on est pas sur android ou ios mais sur desktop il s'agit d'une app desktop(import 'dart:io';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:path/path.dart' as path;
// import 'package:ecole_manager/constants/sizes.dart';
// import 'package:ecole_manager/constants/colors.dart';
// import 'package:ecole_manager/constants/strings.dart';
// import 'package:ecole_manager/models/student.dart';
// import 'package:ecole_manager/models/class.dart';
// import 'package:ecole_manager/services/database_service.dart';
// import 'form_field.dart';

// class StudentRegistrationForm extends StatefulWidget {
//   final VoidCallback onSubmit;

//   const StudentRegistrationForm({required this.onSubmit, Key? key}) : super(key: key);

//   @override
//   _StudentRegistrationFormState createState() => _StudentRegistrationFormState();
// }

// class _StudentRegistrationFormState extends State<StudentRegistrationForm> {
//   final _formKey = GlobalKey<FormState>();
//   final ImagePicker _picker = ImagePicker();
//   final DatabaseService _dbService = DatabaseService();

//   final TextEditingController _studentIdController = TextEditingController();
//   final TextEditingController _studentNameController = TextEditingController();
//   final TextEditingController _dateOfBirthController = TextEditingController();
//   final TextEditingController _addressController = TextEditingController();
//   final TextEditingController _contactNumberController = TextEditingController();
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _emergencyContactController = TextEditingController();
//   final TextEditingController _guardianNameController = TextEditingController();
//   final TextEditingController _guardianContactController = TextEditingController();
//   final TextEditingController _medicalInfoController = TextEditingController();
//   final TextEditingController _studentLastNameController = TextEditingController();

//   String? _selectedClass;
//   String? _selectedGender;
//   XFile? _studentPhoto;
//   List<Class> _classes = [];

//   @override
//   void initState() {
//     super.initState();
//     _loadClasses();
//   }

//   Future<void> _loadClasses() async {
//     try {
//       final classes = await _dbService.getClasses();
//       print('Loaded ${classes.length} classes');
//       setState(() {
//         _classes = classes;
//       });
//     } catch (e) {
//       print('Error loading classes: $e');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Erreur lors du chargement des classes: $e')),
//       );
//     }
//   }

//   @override
//   void dispose() {
//     _studentIdController.dispose();
//     _studentNameController.dispose();
//     _dateOfBirthController.dispose();
//     _addressController.dispose();
//     _contactNumberController.dispose();
//     _emailController.dispose();
//     _emergencyContactController.dispose();
//     _guardianNameController.dispose();
//     _guardianContactController.dispose();
//     _medicalInfoController.dispose();
//     _studentLastNameController.dispose();
//     super.dispose();
//   }

//   Future<void> _pickImage() async {
//     try {
//       final XFile? image = await _picker.pickImage(
//         source: ImageSource.gallery,
//         maxWidth: 800,
//         maxHeight: 800,
//         imageQuality: 85,
//       );
//       if (image != null) {
//         setState(() {
//           _studentPhoto = image;
//         });
//       }
//     } catch (e) {
//       print('Error picking image from gallery: $e');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Erreur lors de la sélection depuis la galerie: $e')),
//       );
//     }
//   }

//   Future<void> _selectDate() async {
//     final DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: DateTime.now().subtract(Duration(days: 365 * 10)),
//       firstDate: DateTime(1900),
//       lastDate: DateTime.now(),
//     );
//     if (picked != null) {
//       setState(() {
//         _dateOfBirthController.text = "${picked.day}/${picked.month}/${picked.year}";
//       });
//     }
//   }

//   Future<String?> _savePhoto(XFile photo) async {
//     try {
//       final directory = await getApplicationDocumentsDirectory();
//       final photoPath = path.join(directory.path, 'photos', path.basename(photo.path));
//       final photoFile = File(photoPath);
//       await photoFile.create(recursive: true);
//       await File(photo.path).copy(photoPath);
//       return photoPath;
//     } catch (e) {
//       print('Error saving photo: $e');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Erreur lors de l\'enregistrement de la photo: $e')),
//       );
//       return null;
//     }
//   }

//   void submitForm() async {
//     if (_formKey.currentState!.validate()) {
//       if (_classes.isEmpty) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Aucune classe disponible. Ajoutez une classe d\'abord.')),
//         );
//         return;
//       }

//       String? photoPath;
//       if (_studentPhoto != null) {
//         photoPath = await _savePhoto(_studentPhoto!);
//       }

//       final student = Student(
//         id: _studentIdController.text,
//         name: _studentNameController.text,
//         dateOfBirth: _dateOfBirthController.text,
//         address: _addressController.text,
//         gender: _selectedGender!,
//         contactNumber: _contactNumberController.text,
//         email: _emailController.text,
//         emergencyContact: _emergencyContactController.text,
//         guardianName: _guardianNameController.text,
//         guardianContact: _guardianContactController.text,
//         className: _selectedClass!,
//         medicalInfo: _medicalInfoController.text.isEmpty ? null : _medicalInfoController.text,
//         photoPath: photoPath,
//       );

//       try {
//         await _dbService.insertStudent(student);
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Étudiant enregistré avec succès!'),
//             backgroundColor: Colors.green,
//           ),
//         );
//         widget.onSubmit();
//         _formKey.currentState!.reset();
//         setState(() {
//           _selectedClass = null;
//           _selectedGender = null;
//           _studentPhoto = null;
//         });
//       } catch (e) {
//         print('Error saving student: $e');
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Erreur lors de l\'enregistrement: $e')),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     print('Building StudentRegistrationForm');
//     return Form(
//       key: _formKey,
//       child: SingleChildScrollView(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             _buildSectionTitle('Photo de l\'étudiant'),
//             _buildPhotoSection(),
//             SizedBox(height: AppSizes.spacing),
//             _buildSectionTitle('Détails Personnels'),
//             CustomFormField(
//               controller: _studentIdController,
//               labelText: 'ID Étudiant',
//               hintText: 'Entrez l\'ID de l\'étudiant',
//               validator: (value) => value!.isEmpty ? AppStrings.required : null,
//             ),
//             CustomFormField(
//               controller: _studentNameController,
//               labelText: 'Prénom',
//               hintText: 'Entrez le prénom de l\'étudiant',
//               validator: (value) => value!.isEmpty ? AppStrings.required : null,
//             ),
//             CustomFormField(
//               controller: _studentLastNameController,
//               labelText: 'Nom',
//               hintText: 'Entrez le nom de famille de l\'étudiant',
//               validator: (value) => value!.isEmpty ? AppStrings.required : null,
//             ),
//             CustomFormField(
//               controller: _dateOfBirthController,
//               labelText: 'Date de Naissance',
//               hintText: 'Sélectionnez la date',
//               readOnly: true,
//               onTap: _selectDate,
//               suffixIcon: Icons.calendar_today,
//             ),
//             CustomFormField(
//               controller: _addressController,
//               labelText: 'Adresse',
//               hintText: 'Entrez l\'adresse',
//             ),
//             CustomFormField(
//               isDropdown: true,
//               labelText: AppStrings.gender,
//               hintText: 'Sélectionnez le sexe',
//               dropdownItems: ['M', 'F'],
//               dropdownValue: _selectedGender,
//               onDropdownChanged: (value) => setState(() => _selectedGender = value),
//               validator: (value) => value == null ? 'Veuillez sélectionner le sexe' : null,
//             ),
//             SizedBox(height: AppSizes.spacing),
//             _buildSectionTitle('Informations de Contact'),
//             CustomFormField(
//               controller: _contactNumberController,
//               labelText: 'Numéro de Contact',
//               hintText: 'Entrez le numéro de contact',
//             ),
//             CustomFormField(
//               controller: _emailController,
//               labelText: 'Adresse Email',
//               hintText: 'Entrez l\'adresse email',
//             ),
//             CustomFormField(
//               controller: _emergencyContactController,
//               labelText: 'Contact d\'Urgence',
//               hintText: 'Entrez le nom et numéro de contact d\'urgence',
//             ),
//             SizedBox(height: AppSizes.spacing),
//             _buildSectionTitle('Informations du Tuteur'),
//             CustomFormField(
//               controller: _guardianNameController,
//               labelText: 'Nom du Tuteur',
//               hintText: 'Entrez le nom complet du tuteur',
//             ),
//             CustomFormField(
//               controller: _guardianContactController,
//               labelText: 'Numéro de Contact du Tuteur',
//               hintText: 'Entrez le numéro de contact du tuteur',
//             ),
//             SizedBox(height: AppSizes.spacing),
//             _buildSectionTitle('Informations Académiques'),
//             CustomFormField(
//               isDropdown: true,
//               labelText: AppStrings.classLabel,
//               hintText: _classes.isEmpty ? 'Aucune classe disponible' : 'Sélectionnez la classe',
//               dropdownItems: _classes.map((cls) => cls.name).toList(),
//               dropdownValue: _selectedClass,
//               onDropdownChanged: (value) => setState(() => _selectedClass = value),
//               validator: (value) => value == null ? 'Veuillez sélectionner une classe' : null,
//             ),
//             SizedBox(height: AppSizes.spacing),
//             _buildSectionTitle('Informations Médicales'),
//             CustomFormField(
//               controller: _medicalInfoController,
//               labelText: 'Informations Médicales',
//               hintText: 'Entrez les informations médicales pertinentes',
//               isTextArea: true,
//             ),
//             SizedBox(height: AppSizes.spacing),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildSectionTitle(String title) {
//     return Padding(
//       padding: EdgeInsets.symmetric(vertical: AppSizes.spacing / 2),
//       child: Text(
//         title,
//         style: TextStyle(
//           fontSize: AppSizes.titleFontSize,
//           fontWeight: FontWeight.bold,
//           color: Theme.of(context).textTheme.bodyLarge!.color,
//         ),
//       ),
//     );
//   }

//   Widget _buildPhotoSection() {
//     return Container(
//       margin: EdgeInsets.symmetric(vertical: AppSizes.smallSpacing),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             'Photo de l\'étudiant',
//             style: TextStyle(
//               fontSize: AppSizes.textFontSize,
//               fontWeight: FontWeight.w500,
//               color: Theme.of(context).textTheme.bodyMedium!.color,
//             ),
//           ),
//           SizedBox(height: AppSizes.smallSpacing / 2),
//           GestureDetector(
//             onTap: _pickImage,
//             child: Container(
//               width: double.infinity,
//               height: 120,
//               decoration: BoxDecoration(
//                 color: Theme.of(context).cardColor,
//                 borderRadius: BorderRadius.circular(8),
//                 border: Border.all(color: Theme.of(context).dividerColor!),
//               ),
//               child: _studentPhoto != null
//                   ? Stack(
//                       children: [
//                         ClipRRect(
//                           borderRadius: BorderRadius.circular(8),
//                           child: Image.file(
//                             File(_studentPhoto!.path),
//                             width: double.infinity,
//                             height: 120,
//                             fit: BoxFit.cover,
//                             errorBuilder: (context, error, stackTrace) => Center(
//                               child: Icon(Icons.error, color: Colors.red),
//                             ),
//                           ),
//                         ),
//                         Positioned(
//                           top: 8,
//                           right: 8,
//                           child: GestureDetector(
//                             onTap: () => setState(() => _studentPhoto = null),
//                             child: Container(
//                               padding: EdgeInsets.all(4),
//                               decoration: BoxDecoration(
//                                 color: Colors.red,
//                                 borderRadius: BorderRadius.circular(4),
//                               ),
//                               child: Icon(Icons.close, color: Colors.white, size: 16),
//                             ),
//                           ),
//                         ),
//                       ],
//                     )
//                   : Column(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         Icon(Icons.add_a_photo, size: 24, color: Theme.of(context).textTheme.bodyMedium!.color),
//                         SizedBox(height: 4),
//                         Text(
//                           'Ajouter une photo',
//                           style: TextStyle(
//                             color: Theme.of(context).textTheme.bodyMedium!.color,
//                             fontSize: AppSizes.textFontSize - 2,
//                           ),
//                         ),
//                       ],
//                     ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// typedef StudentRegistrationFormState = _StudentRegistrationFormState;)