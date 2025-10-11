import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:school_manager/models/course.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
// ignore: depend_on_referenced_packages
import 'package:printing/printing.dart';
import 'package:school_manager/constants/strings.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:school_manager/screens/students/widgets/student_registration_form.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:docx_template/docx_template.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:open_file/open_file.dart';
import 'package:school_manager/services/auth_service.dart';

class ClassDetailsPage extends StatefulWidget {
  final Class classe;
  final List<Student> students;

  const ClassDetailsPage({
    required this.classe,
    required this.students,
    Key? key,
  }) : super(key: key);

  @override
  State<ClassDetailsPage> createState() => _ClassDetailsPageState();
}

class _ClassDetailsPageState extends State<ClassDetailsPage>
    with TickerProviderStateMixin {
  late TextEditingController _nameController;
  late TextEditingController _yearController;
  late TextEditingController _titulaireController;
  late TextEditingController _fraisEcoleController;
  late TextEditingController _fraisCotisationParalleleController;
  late TextEditingController _searchController;
  late List<Student> _students;
  final DatabaseService _dbService = DatabaseService();
  final _formKey = GlobalKey<FormState>();
  String _studentSearchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = false;
  late FocusNode _nameFocusNode;
  late FocusNode _yearFocusNode;
  late FocusNode _titulaireFocusNode;
  late FocusNode _fraisEcoleFocusNode;
  late FocusNode _fraisCotisationFocusNode;
  late FocusNode _searchFocusNode;
  String _sortBy = 'name'; // Sort by name or ID
  bool _sortAscending = true;
  String _studentStatusFilter = 'Tous'; // 'Tous', 'Payé', 'En attente'
  List<Course> _classSubjects = const [];
  final Map<String, TextEditingController> _coeffCtrls = {};
  double _sumCoeffs = 0.0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.classe.name);
    _yearController = TextEditingController(text: widget.classe.academicYear);
    _titulaireController = TextEditingController(text: widget.classe.titulaire);
    _fraisEcoleController = TextEditingController(
      text: widget.classe.fraisEcole?.toString() ?? '',
    );
    _fraisCotisationParalleleController = TextEditingController(
      text: widget.classe.fraisCotisationParallele?.toString() ?? '',
    );
    _searchController = TextEditingController();
    _students = List<Student>.from(widget.students);

    _nameFocusNode = FocusNode();
    _yearFocusNode = FocusNode();
    _titulaireFocusNode = FocusNode();
    _fraisEcoleFocusNode = FocusNode();
    _fraisCotisationFocusNode = FocusNode();
    _searchFocusNode = FocusNode();

    _animationController = AnimationController(
      duration: const Duration(
        milliseconds: 600,
      ), // Slightly faster for performance
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();

    _fraisEcoleController.addListener(_updateTotalClasse);
    _fraisCotisationParalleleController.addListener(_updateTotalClasse);

    _loadClassSubjectsAndCoeffs();

    getCurrentAcademicYear().then((year) {
      if (widget.classe.academicYear.isEmpty) {
        _yearController.text = year;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    _titulaireController.dispose();
    _fraisEcoleController.dispose();
    _fraisCotisationParalleleController.dispose();
    _searchController.dispose();
    _animationController.dispose();
    _nameFocusNode.dispose();
    _yearFocusNode.dispose();
    _titulaireFocusNode.dispose();
    _fraisEcoleFocusNode.dispose();
    _fraisCotisationFocusNode.dispose();
    _searchFocusNode.dispose();
    _fraisEcoleController.removeListener(_updateTotalClasse);
    _fraisCotisationParalleleController.removeListener(_updateTotalClasse);
    super.dispose();
    for (final c in _coeffCtrls.values) c.dispose();
  }

  void _updateTotalClasse() {
    setState(() {}); // Force le rebuild pour mettre à jour le total
  }

  Future<void> _loadClassSubjectsAndCoeffs() async {
    final subs = await _dbService.getCoursesForClass(
      _nameController.text,
      _yearController.text,
    );
    final coeffs = await _dbService.getClassSubjectCoefficients(
      _nameController.text,
      _yearController.text,
    );
    setState(() {
      _classSubjects = subs;
      _coeffCtrls.clear();
      _sumCoeffs = 0.0;
      for (final s in subs) {
        final v = coeffs[s.name]?.toString() ?? '';
        final ctrl = TextEditingController(text: v);
        ctrl.addListener(() {
          _recomputeSum();
        });
        _coeffCtrls[s.id] = ctrl;
        final n = double.tryParse((v).replaceAll(',', '.'));
        if (n != null) _sumCoeffs += n;
      }
    });
  }

  void _recomputeSum() {
    double sum = 0.0;
    for (final ctrl in _coeffCtrls.values) {
      final n = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (n != null) sum += n;
    }
    setState(() {
      _sumCoeffs = sum;
    });
  }

  Future<void> _saveCoefficients() async {
    for (final course in _classSubjects) {
      final ctrl = _coeffCtrls[course.id];
      if (ctrl == null) continue;
      final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (val == null) continue;
      await _dbService.updateClassCourseCoefficient(
        className: _nameController.text,
        academicYear: _yearController.text,
        courseId: course.id,
        coefficient: val,
      );
    }
    _showModernSnackBar(
      'Coefficients mis à jour pour ${_nameController.text}.',
    );
  }

  Future<void> _saveClass() async {
    if (!_formKey.currentState!.validate()) {
      _showModernSnackBar(
        'Veuillez remplir tous les champs obligatoires',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedClass = Class(
        name: _nameController.text,
        academicYear: _yearController.text,
        titulaire: _titulaireController.text,
        fraisEcole: _fraisEcoleController.text.isNotEmpty
            ? double.tryParse(_fraisEcoleController.text)
            : null,
        fraisCotisationParallele:
            _fraisCotisationParalleleController.text.isNotEmpty
            ? double.tryParse(_fraisCotisationParalleleController.text)
            : null,
      );
      await _dbService.updateClass(
        widget.classe.name,
        widget.classe.academicYear,
        updatedClass,
      );
      await _loadClassSubjectsAndCoeffs();
      final refreshedClass = await _dbService.getClassByName(
        updatedClass.name,
        academicYear: updatedClass.academicYear,
      );
      final refreshedStudents = await _dbService.getStudentsByClassAndClassYear(
        updatedClass.name,
        updatedClass.academicYear,
      );

      if (!mounted) return;
      setState(() {
        final cls = refreshedClass ?? updatedClass;
        _nameController.text = cls.name;
        _yearController.text = cls.academicYear;
        _titulaireController.text = cls.titulaire ?? '';
        _fraisEcoleController.text = cls.fraisEcole?.toString() ?? '';
        _fraisCotisationParalleleController.text =
            cls.fraisCotisationParallele?.toString() ?? '';
        _students = refreshedStudents;
        _isLoading = false;
      });
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Succès'),
          content: const Text('Classe mise à jour avec succès !'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erreur'),
          content: Text(
            'Erreur lors de la mise à jour : ${e.toString().contains('unique') ? 'Nom de classe déjà existant' : e}',
          ),
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

  Future<void> _copyClass() async {
    // Demander l'année cible à l'utilisateur
    final classes = await _dbService.getClasses();
    final years =
        classes
            .map((c) => c.academicYear)
            .where((y) => y.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final current = _yearController.text.trim();
    String suggestNext() {
      try {
        final parts = current.split('-');
        final s = int.parse(parts.first);
        final e = int.parse(parts.last);
        return '${s + 1}-${e + 1}';
      } catch (_) {
        final now = DateTime.now().year;
        return '$now-${now + 1}';
      }
    }

    final TextEditingController yearCtrl = TextEditingController(
      text: suggestNext(),
    );
    String? targetYear = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Copier la classe vers…'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (years.isNotEmpty) ...[
                    const Text('Années existantes'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: years
                          .map(
                            (y) => ChoiceChip(
                              label: Text(y),
                              selected: yearCtrl.text == y,
                              onSelected: (_) =>
                                  setStateDialog(() => yearCtrl.text = y),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: yearCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Année cible',
                      hintText: 'ex: 2025-2026',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, yearCtrl.text.trim()),
                  child: const Text('Copier'),
                ),
              ],
            );
          },
        );
      },
    );
    if (targetYear == null || targetYear.isEmpty) return;
    final valid = RegExp(r'^\d{4}-\d{4}$').hasMatch(targetYear);
    if (!valid) {
      _showModernSnackBar(
        'Format d\'année invalide. Utilisez 2025-2026.',
        isError: true,
      );
      return;
    }

    // Interdire une double copie de la même classe pour la même année cible
    final existingInTarget = (await _dbService.getClasses())
        .where((c) => c.academicYear == targetYear)
        .toList();
    final originalName = _nameController.text.trim();
    final alreadyCopied = existingInTarget.any(
      (c) => c.name == originalName || c.name == '$originalName ($targetYear)',
    );
    if (alreadyCopied) {
      _showModernSnackBar(
        'Cette classe a déjà été copiée pour l\'année $targetYear.',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Préférer le même nom si disponible, sinon suffixer avec l'année cible
      String desired = originalName;
      if (await _dbService.getClassByName(desired, academicYear: targetYear) !=
          null) {
        desired = '$originalName ($targetYear)';
      }
      // Assurer l'unicité en dernier recours (rare)
      String uniqueName = desired;
      int k = 2;
      while (await _dbService.getClassByName(
            uniqueName,
            academicYear: targetYear,
          ) !=
          null) {
        uniqueName = '$desired-$k';
        k++;
      }

      final newClass = Class(
        name: uniqueName,
        academicYear: targetYear,
        titulaire: _titulaireController.text,
        fraisEcole: _fraisEcoleController.text.isNotEmpty
            ? double.tryParse(_fraisEcoleController.text)
            : null,
        fraisCotisationParallele:
            _fraisCotisationParalleleController.text.isNotEmpty
            ? double.tryParse(_fraisCotisationParalleleController.text)
            : null,
      );
      await _dbService.insertClass(newClass);
      setState(() => _isLoading = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Succès'),
          content: Text(
            'Classe copiée vers $targetYear sous le nom "$uniqueName".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isLoading = false);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erreur'),
          content: Text('Erreur lors de la copie : $e'),
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

  void _showModernSnackBar(String message, {bool isError = false}) {
    // Dans un dialog sans Scaffold, basculer en AlertDialog
    final hasMessenger = ScaffoldMessenger.maybeOf(context) != null;
    final hasScaffold = Scaffold.maybeOf(context) != null;
    if (hasMessenger && hasScaffold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? const Color(0xFFE53E3E)
              : const Color(0xFF38A169),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isError ? 'Erreur' : 'Information'),
          content: Text(message),
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

  Future<void> _editStudent(Student student) async {
    final GlobalKey<StudentRegistrationFormState> studentFormKey =
        GlobalKey<StudentRegistrationFormState>();
    await showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: AppStrings.editStudent,
        content: StudentRegistrationForm(
          key: studentFormKey,
          className: student.className,
          classFieldReadOnly: true,
          onSubmit: () async {
            final refreshedStudents = await _dbService
                .getStudentsByClassAndClassYear(
                  _nameController.text,
                  _yearController.text,
                );
            setState(() {
              _students = refreshedStudents;
            });
            Navigator.of(context).pop();
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Succès'),
                content: const Text('Élève mis à jour avec succès !'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          },
          student: student,
        ),
        fields: const [],
        onSubmit: () {
          studentFormKey.currentState?.submitForm();
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
          ElevatedButton(
            onPressed: () => studentFormKey.currentState?.submitForm(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3182CE),
              foregroundColor: Colors.white,
            ),
            child: const Text('Modifier'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStudent(Student student) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _buildModernDeleteDialog(student),
    );
    if (confirm == true) {
      try {
        // Supprime l'élève et toutes les données liées (paiements, notes, appréciations, bulletins, archives)
        await _dbService.deleteStudentDeep(student.id);
        if (student.photoPath != null &&
            File(student.photoPath!).existsSync()) {
          await File(student.photoPath!).delete();
        }
        final refreshedStudents = await _dbService
            .getStudentsByClassAndClassYear(
              _nameController.text,
              _yearController.text,
            );
        setState(() {
          _students = refreshedStudents;
        });
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Succès'),
            content: const Text('Élève supprimé avec succès !'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } catch (e) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Erreur'),
            content: Text('Erreur lors de la suppression : $e'),
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

  Widget _buildModernDeleteDialog(Student student) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFE11D48)),
          SizedBox(width: 8),
          Text(
            'Confirmer la suppression',
            style: TextStyle(
              color: Color(0xFFE11D48),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              size: 40,
              color: Color(0xFFE11D48),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Voulez-vous vraiment supprimer l'élève ${student.firstName} ${student.lastName} ?\nCette action est irréversible.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color,
              height: 1.5,
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE11D48),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Supprimer'),
        ),
      ],
    );
  }

  Widget _buildModernSectionTitle(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Colors.white,
              semanticLabel: title,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge!.color,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernFormCard(List<Widget> children) {
    final int nbEleves = _students.length;
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double totalClasse = nbEleves * (fraisEcole + fraisCotisation);
    // color for totals will be derived from the theme where needed; remove unused local variable
    children.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: CustomFormField(
          controller: TextEditingController(
            text: '${totalClasse.toStringAsFixed(2)} FCFA',
          ),
          labelText: 'Total à payer pour la classe',
          hintText: '',
          readOnly: true,
          suffixIcon: Icons.summarize,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.98),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          // Nom de la classe
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _nameController,
                              labelText: AppStrings.classNameDialog,
                              hintText: 'Entrez le nom de la classe',
                              validator: (value) =>
                                  value!.isEmpty ? AppStrings.required : null,
                              suffixIcon: Icons.class_,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _yearController,
                              labelText: AppStrings.academicYearDialog,
                              hintText: "Entrez l'année scolaire",
                              validator: (value) =>
                                  value!.isEmpty ? AppStrings.required : null,
                              suffixIcon: Icons.calendar_today,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _titulaireController,
                              labelText: 'Titulaire',
                              hintText: 'Nom du titulaire de la classe',
                              suffixIcon: Icons.person_outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _fraisEcoleController,
                              labelText: "Frais d'école",
                              hintText: "Montant des frais d'école",
                              validator: (value) {
                                if (value != null &&
                                    value.isNotEmpty &&
                                    double.tryParse(value) == null) {
                                  return 'Veuillez entrer un montant valide';
                                }
                                return null;
                              },
                              suffixIcon: Icons.attach_money,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: _fraisCotisationParalleleController,
                              labelText: 'Frais de cotisation parallèle',
                              hintText:
                                  'Montant des frais de cotisation parallèle',
                              validator: (value) {
                                if (value != null &&
                                    value.isNotEmpty &&
                                    double.tryParse(value) == null) {
                                  return 'Veuillez entrer un montant valide';
                                }
                                return null;
                              },
                              suffixIcon: Icons.account_balance_wallet_outlined,
                            ),
                          ),
                          // Champ du montant total à payer pour la classe
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: CustomFormField(
                              controller: TextEditingController(
                                text: '${totalClasse.toStringAsFixed(2)} FCFA',
                              ),
                              labelText: 'Total à payer pour la classe',
                              hintText: '',
                              readOnly: true,
                              suffixIcon: Icons.summarize,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _nameController,
                        labelText: AppStrings.classNameDialog,
                        hintText: 'Entrez le nom de la classe',
                        validator: (value) =>
                            value!.isEmpty ? AppStrings.required : null,
                        suffixIcon: Icons.class_,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _yearController,
                        labelText: AppStrings.academicYearDialog,
                        hintText: "Entrez l'année scolaire",
                        validator: (value) =>
                            value!.isEmpty ? AppStrings.required : null,
                        suffixIcon: Icons.calendar_today,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _titulaireController,
                        labelText: 'Titulaire',
                        hintText: 'Nom du titulaire de la classe',
                        suffixIcon: Icons.person_outline,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _fraisEcoleController,
                        labelText: "Frais d'école",
                        hintText: "Montant des frais d'école",
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              double.tryParse(value) == null) {
                            return 'Veuillez entrer un montant valide';
                          }
                          return null;
                        },
                        suffixIcon: Icons.attach_money,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: _fraisCotisationParalleleController,
                        labelText: 'Frais de cotisation parallèle',
                        hintText: 'Montant des frais de cotisation parallèle',
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              double.tryParse(value) == null) {
                            return 'Veuillez entrer un montant valide';
                          }
                          return null;
                        },
                        suffixIcon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    // Champ du montant total à payer pour la classe (mobile)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: CustomFormField(
                        controller: TextEditingController(
                          text: '${totalClasse.toStringAsFixed(2)} FCFA',
                        ),
                        labelText: 'Total à payer pour la classe',
                        hintText: '',
                        readOnly: true,
                        suffixIcon: Icons.summarize,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildModernSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'Rechercher par nom, ID ou genre...',
          hintStyle: TextStyle(
            color: Theme.of(
              context,
            ).textTheme.bodyMedium!.color?.withOpacity(0.6),
            fontSize: 16,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: Colors.white,
              size: 20,
              semanticLabel: 'Rechercher',
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
        ),
        style: const TextStyle(fontSize: 16),
        onChanged: (value) =>
            setState(() => _studentSearchQuery = value.trim()),
      ),
    );
  }

  Widget _buildModernStudentCard(Student student) {
    return FutureBuilder<double>(
      future: _dbService.getTotalPaidForStudent(student.id),
      builder: (context, snapshot) {
        final double fraisEcole =
            double.tryParse(_fraisEcoleController.text) ?? 0;
        final double fraisCotisation =
            double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
        final double montantMax = fraisEcole + fraisCotisation;
        final double totalPaid = snapshot.data ?? 0;
        final bool isPaid = montantMax > 0 && totalPaid >= montantMax;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFF667EEA).withOpacity(0.1),
              child: Text(
                student.firstName.isNotEmpty ? student.firstName[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667EEA),
                ),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${student.firstName} ${student.lastName}'.trim(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isPaid ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPaid ? 'Payé' : 'En attente',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ID: ${student.id} • ${student.gender == 'M' ? 'Garçon' : 'Fille'}',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModernActionButton(
                  icon: Icons.person_rounded,
                  color: const Color(0xFF3182CE),
                  tooltip: 'Détails',
                  onPressed: () => _showStudentDetailsDialog(student),
                  semanticLabel: 'Voir détails',
                ),
                const SizedBox(width: 8),
                _buildModernActionButton(
                  icon: Icons.account_balance_wallet_rounded,
                  color: const Color(0xFF38A169),
                  tooltip: 'Paiement',
                  onPressed: () => _showPaymentDialog(student),
                  semanticLabel: 'Ajouter paiement',
                ),
                const SizedBox(width: 8),
                _buildModernActionButton(
                  icon: Icons.edit_rounded,
                  color: const Color(0xFF667EEA),
                  tooltip: 'Modifier',
                  onPressed: () => _editStudent(student),
                  semanticLabel: 'Modifier élève',
                ),
                const SizedBox(width: 8),
                _buildModernActionButton(
                  icon: Icons.delete_rounded,
                  color: const Color(0xFFE53E3E),
                  tooltip: 'Supprimer',
                  onPressed: () => _deleteStudent(student),
                  semanticLabel: 'Supprimer élève',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    VoidCallback? onPressed,
    required String semanticLabel,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(onPressed != null ? 0.1 : 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color.withOpacity(onPressed != null ? 1.0 : 0.5),
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.school_rounded,
              size: 40,
              color: Color(0xFF667EEA),
              semanticLabel: 'Aucun élève',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun élève dans cette classe',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.titleMedium!.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Commencez par ajouter des élèves à cette classe',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium!.color?.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Student>> _getFilteredAndSortedStudentsAsync() async {
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    List<Student> filtered = [];
    for (final student in _students) {
      final totalPaid = await _dbService.getTotalPaidForStudent(student.id);
      final isPaid = montantMax > 0 && totalPaid >= montantMax;
      final status = isPaid ? 'Payé' : 'En attente';
      final query = _studentSearchQuery.toLowerCase();
      final matchSearch =
          _studentSearchQuery.isEmpty ||
          '${student.firstName} ${student.lastName}'.toLowerCase().contains(query) ||
          student.id.toLowerCase().contains(query) ||
          (student.gender == 'M' && 'garçon'.contains(query)) ||
          (student.gender == 'F' && 'fille'.contains(query));
      if (_studentStatusFilter == 'Tous' && matchSearch) {
        filtered.add(student);
      } else if (_studentStatusFilter == status && matchSearch) {
        filtered.add(student);
      }
    }
    filtered.sort((a, b) {
      int compare;
      if (_sortBy == 'name') {
        compare = a.name.compareTo(b.name);
      } else {
        compare = a.id.compareTo(b.id);
      }
      return _sortAscending ? compare : -compare;
    });
    return filtered;
  }

  Widget _buildSortControls() {
    return Row(
      children: [
        Text(
          'Trier par : ',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).textTheme.bodyMedium!.color,
          ),
        ),
        DropdownButton<String>(
          value: _sortBy,
          items: const [
            DropdownMenuItem(value: 'name', child: Text('Nom')),
            DropdownMenuItem(value: 'id', child: Text('ID')),
          ],
          onChanged: (value) => setState(() => _sortBy = value!),
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).textTheme.bodyLarge!.color,
          ),
          underline: const SizedBox(),
        ),
        IconButton(
          icon: Icon(
            _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 20,
            color: Theme.of(context).textTheme.bodyMedium!.color,
          ),
          onPressed: () => setState(() => _sortAscending = !_sortAscending),
          tooltip: _sortAscending ? 'Tri ascendant' : 'Tri descendant',
        ),
      ],
    );
  }

  void _showStudentDetailsDialog(Student student) async {
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    final totalPaid = await _dbService.getTotalPaidForStudent(student.id);
    final reste = montantMax - totalPaid;
    final status = (montantMax > 0 && totalPaid >= montantMax)
        ? 'Payé'
        : 'En attente';
    final db = await _dbService.database;
    final List<Map<String, dynamic>> allMaps = await db.query(
      'payments',
      where: 'studentId = ?',
      whereArgs: [student.id],
      orderBy: 'date DESC',
    );
    final payments = allMaps.map((m) => Payment.fromMap(m)).toList();
    showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: 'Détails de l\'élève',
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (student.photoPath != null && student.photoPath!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(student.photoPath!),
                      key: ValueKey(student.photoPath!),
                      width: double.infinity,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Center(child: Icon(Icons.error, color: Colors.red)),
                    ),
                  ),
                ),
              _buildDetailRow('Nom complet', '${student.firstName} ${student.lastName}'.trim()),
              _buildDetailRow('ID', student.id),
              if (student.matricule != null && student.matricule!.isNotEmpty)
                _buildDetailRow('Matricule', student.matricule!),
              _buildDetailRow('Année scolaire', student.academicYear),
              _buildDetailRow(
                'Date d\'inscription',
                _formatIsoToDisplay(student.enrollmentDate),
              ),
              _buildDetailRow(
                'Date de naissance',
                '${_formatIsoToDisplay(student.dateOfBirth)} • ${_calculateAgeFromIso(student.dateOfBirth)}',
              ),
              _buildDetailRow('Statut', student.status),
              _buildDetailRow(
                'Sexe',
                student.gender == 'M' ? 'Garçon' : 'Fille',
              ),
              _buildDetailRow('Classe', student.className),
              _buildDetailRow('Adresse', student.address),
              _buildDetailRow('Contact', student.contactNumber),
              _buildDetailRow('Email', student.email),
              _buildDetailRow('Contact d\'urgence', student.emergencyContact),
              _buildDetailRow('Tuteur', student.guardianName),
              _buildDetailRow('Contact tuteur', student.guardianContact),
              if (student.medicalInfo != null &&
                  student.medicalInfo!.isNotEmpty)
                _buildDetailRow('Infos médicales', student.medicalInfo!),
              const SizedBox(height: 16),
              Divider(),
              Text(
                'Paiement',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Montant dû',
                '${montantMax.toStringAsFixed(2)} FCFA',
              ),
              _buildDetailRow(
                'Déjà payé',
                '${totalPaid.toStringAsFixed(2)} FCFA',
              ),
              _buildDetailRow(
                'Reste à payer',
                reste <= 0 ? 'Payé' : '${reste.toStringAsFixed(2)} FCFA',
              ),
              _buildDetailRow('Statut', status),
              const SizedBox(height: 8),
              if (payments.isNotEmpty) ...[
                Text(
                  'Historique des paiements',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...payments.map(
                  (p) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: p.isCancelled ? Colors.grey.shade200 : null,
                    child: ListTile(
                      leading: Icon(
                        Icons.attach_money,
                        color: p.isCancelled ? Colors.grey : Colors.green,
                      ),
                      title: Row(
                        children: [
                          Text(
                            '${p.amount.toStringAsFixed(2)} FCFA',
                            style: TextStyle(
                              color: p.isCancelled ? Colors.grey : null,
                              decoration: p.isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (p.isCancelled)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '(Annulé)',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p.date.replaceFirst('T', ' ').substring(0, 16)}',
                            style: TextStyle(
                              color: p.isCancelled ? Colors.grey : null,
                            ),
                          ),
                          if ((p.recordedBy ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Enregistré par : ${p.recordedBy}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (p.comment != null && p.comment!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Commentaire : ${p.comment!}',
                                style: TextStyle(
                                  color: Colors.deepPurple,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          if (p.isCancelled && (p.cancelBy ?? '').isNotEmpty)
                            const SizedBox(height: 2),
                          if (p.isCancelled && (p.cancelBy ?? '').isNotEmpty)
                            Text(
                              'Annulé par ${p.cancelBy}',
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          if (p.isCancelled && p.cancelledAt != null)
                            Text(
                              'Annulé le ${p.cancelledAt!.replaceFirst('T', ' ').substring(0, 16)}',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                        ],
                      ),
                      trailing: p.isCancelled
                          ? Icon(Icons.block, color: Colors.grey)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.print, color: Colors.blue),
                                  tooltip: 'Imprimer le reçu',
                                  onPressed: () => _printReceipt(p, student),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Annuler ce paiement',
                                  onPressed: () async {
                                    final motifCtrl = TextEditingController();
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => CustomDialog(
                                        title: 'Motif d\'annulation',
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Veuillez saisir un motif pour annuler ce paiement. Cette action est irréversible.',
                                            ),
                                            const SizedBox(height: 12),
                                            CustomFormField(
                                              controller: motifCtrl,
                                              labelText: 'Motif',
                                              hintText: 'Ex: erreur de saisie, remboursement, etc.',
                                              isTextArea: true,
                                              validator: (v) =>
                                                  (v == null || v.trim().isEmpty)
                                                      ? 'Motif requis'
                                                      : null,
                                            ),
                                          ],
                                        ),
                                        fields: const [],
                                        onSubmit: () => Navigator.of(context).pop(true),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(false),
                                            child: const Text('Annuler'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.of(context).pop(true),
                                            child: const Text('Confirmer'),
                                          ),
                                        ],
                                      ),
                                    );
                                    final reason = motifCtrl.text.trim();
                                    if (ok == true && reason.isNotEmpty) {
                                      // Fetch current user display name if available
                                      String? by;
                                      try {
                                        final user = await AuthService.instance.getCurrentUser();
                                        by = user?.displayName ?? user?.username;
                                      } catch (_) {}
                                      await _dbService.cancelPaymentWithReason(p.id!, reason, by: by);
                                      Navigator.of(context).pop();
                                      _showModernSnackBar('Paiement annulé');
                                      setState(() {});
                                    } else if (ok == true && reason.isEmpty) {
                                      _showModernSnackBar('Motif obligatoire pour annuler.');
                                    }
                                  },
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ] else ...[
                Text('Aucun paiement enregistré.'),
              ],
            ],
          ),
        ),
        fields: const [],
        onSubmit: () => Navigator.of(context).pop(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(Student student) async {
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    if (montantMax == 0) {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Alerte',
          content: const Text(
            'Veuillez renseigner un montant de frais d\'école ou de cotisation dans la fiche classe avant d\'enregistrer un paiement.',
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final montantController = TextEditingController(text: '0');
    final commentController = TextEditingController();
    final totalPaid = await _dbService.getTotalPaidForStudent(student.id);
    final reste = montantMax - totalPaid;
    if (reste <= 0) {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Alerte',
          content: const Text('L\'élève a déjà tout payé pour cette classe.'),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    void showMontantDepasseAlerte() {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Montant trop élevé',
          content: Text(
            'Le montant saisi dépasse le solde dû (${reste.toStringAsFixed(2)} FCFA).',
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: 'Paiement pour ${student.firstName} ${student.lastName}'.trim(),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Montant maximum autorisé : ${reste.toStringAsFixed(2)} FCFA',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Déjà payé : ${totalPaid.toStringAsFixed(2)} FCFA'),
            const SizedBox(height: 12),
            CustomFormField(
              controller: montantController,
              labelText: 'Montant à payer',
              hintText: 'Saisir le montant',
              suffixIcon: Icons.attach_money,
              validator: (value) {
                final val = double.tryParse(value ?? '');
                if (val == null || val < 0) return 'Montant invalide';
                if (val > reste) return 'Ne peut excéder $reste';
                return null;
              },
            ),
            const SizedBox(height: 12),
            CustomFormField(
              controller: commentController,
              labelText: 'Commentaire (optionnel)',
              hintText: 'Ex: acompte, solde, etc.',
              suffixIcon: Icons.comment,
            ),
          ],
        ),
        fields: const [],
        onSubmit: () async {
          final val = double.tryParse(montantController.text);
          if (val == null || val < 0) return;
          if (val > reste) {
            showMontantDepasseAlerte();
            return;
          }
          final user = await AuthService.instance.getCurrentUser();
          final payment = Payment(
            studentId: student.id,
            className: student.className,
            classAcademicYear: student.academicYear,
            amount: val,
            date: DateTime.now().toIso8601String(),
            comment: commentController.text.isNotEmpty
                ? commentController.text
                : null,
            recordedBy: user?.displayName ?? user?.username,
          );
          await _dbService.insertPayment(payment);
          Navigator.of(context).pop();
          _showModernSnackBar('Paiement enregistré !');
          setState(() {});
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(montantController.text);
              if (val == null || val < 0) return;
              if (val > reste) {
                showMontantDepasseAlerte();
                return;
              }
              final user = await AuthService.instance.getCurrentUser();
              final payment = Payment(
                studentId: student.id,
                className: student.className,
                classAcademicYear: student.academicYear,
                amount: val,
                date: DateTime.now().toIso8601String(),
                comment: commentController.text.isNotEmpty
                    ? commentController.text
                    : null,
                recordedBy: user?.displayName ?? user?.username,
              );
              await _dbService.insertPayment(payment);
              Navigator.of(context).pop();
              _showModernSnackBar('Paiement enregistré !');
              setState(() {});
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _printReceipt(Payment p, Student student) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'REÇU DE PAIEMENT',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Élève : ${student.firstName} ${student.lastName}'.trim(),
                style: pw.TextStyle(fontSize: 16),
              ),
              pw.Text(
                'Classe : ${student.className}',
                style: pw.TextStyle(fontSize: 16),
              ),
              pw.Text('ID : ${student.id}', style: pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 12),
              pw.Text(
                'Montant payé : ${p.amount.toStringAsFixed(2)} FCFA',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Date : ${p.date.replaceFirst('T', ' ').substring(0, 16)}',
                style: pw.TextStyle(fontSize: 14),
              ),
              if (p.comment != null && p.comment!.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    'Commentaire : ${p.comment!}',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
              if (p.isCancelled)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    'ANNULÉ le ${p.cancelledAt?.replaceFirst('T', ' ').substring(0, 16) ?? ''}',
                    style: pw.TextStyle(
                      color: PdfColor.fromInt(0xFFFF0000),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(height: 24),
              pw.Text(
                'Signature : ___________________________',
                style: pw.TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label : ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomDialog(
      title: AppStrings.classDetailsTitle,
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Boutons d'export PDF/Excel
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: ElevatedButton.icon(
                            onPressed: _exportGradesTemplateExcel,
                            icon: const Icon(
                              Icons.table_view,
                              color: Colors.white,
                            ),
                            label: const Text('Générer modèle Excel'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0EA5E9),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: ElevatedButton.icon(
                            onPressed: _showSubjectTemplateDialog,
                            icon: const Icon(
                              Icons.view_list,
                              color: Colors.white,
                            ),
                            label: const Text('Modèle par matière'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: ElevatedButton.icon(
                            onPressed: _exportStudentsPdf,
                            icon: const Icon(
                              Icons.picture_as_pdf,
                              color: Colors.white,
                            ),
                            label: const Text('Exporter PDF'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: ElevatedButton.icon(
                            onPressed: _exportStudentsExcel,
                            icon: const Icon(
                              Icons.grid_on,
                              color: Colors.white,
                            ),
                            label: const Text('Exporter Excel'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: ElevatedButton.icon(
                            onPressed: _exportStudentsWord,
                            icon: const Icon(
                              Icons.description,
                              color: Colors.white,
                            ),
                            label: const Text('Exporter Word'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildModernSectionTitle(
                      'Informations sur la classe',
                      Icons.class_rounded,
                    ),
                    _buildModernFormCard([
                      CustomFormField(
                        controller: _nameController,
                        labelText: AppStrings.classNameDialog,
                        hintText: 'Entrez le nom de la classe',
                        validator: (value) =>
                            value!.isEmpty ? AppStrings.required : null,
                      ),
                      CustomFormField(
                        controller: _yearController,
                        labelText: AppStrings.academicYearDialog,
                        hintText: "Entrez l'année scolaire",
                        validator: (value) =>
                            value!.isEmpty ? AppStrings.required : null,
                      ),
                      CustomFormField(
                        controller: _titulaireController,
                        labelText: 'Titulaire',
                        hintText: 'Nom du titulaire de la classe',
                      ),
                      CustomFormField(
                        controller: _fraisEcoleController,
                        labelText: "Frais d'école",
                        hintText: "Montant des frais d'école",
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              double.tryParse(value) == null) {
                            return 'Veuillez entrer un montant valide';
                          }
                          return null;
                        },
                      ),
                      CustomFormField(
                        controller: _fraisCotisationParalleleController,
                        labelText: 'Frais de cotisation parallèle',
                        hintText: 'Montant des frais de cotisation parallèle',
                        validator: (value) {
                          if (value != null &&
                              value.isNotEmpty &&
                              double.tryParse(value) == null) {
                            return 'Veuillez entrer un montant valide';
                          }
                          return null;
                        },
                      ),
                    ]),
                    const SizedBox(height: 32),
                    _buildModernSectionTitle(
                      'Élèves de la classe',
                      Icons.people_rounded,
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Ajouter un élève'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3182CE),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            final GlobalKey<StudentRegistrationFormState>
                            studentFormKey =
                                GlobalKey<StudentRegistrationFormState>();
                            await showDialog(
                              context: context,
                              builder: (context) => CustomDialog(
                                title: 'Ajouter un élève',
                                content: StudentRegistrationForm(
                                  key: studentFormKey,
                                  className: _nameController.text, // pré-rempli
                                  classFieldReadOnly:
                                      true, // à gérer dans le form
                                  onSubmit: () async {
                                    final refreshedStudents = await _dbService
                                        .getStudentsByClassAndClassYear(
                                          _nameController.text,
                                          _yearController.text,
                                        );
                                    setState(() {
                                      _students = refreshedStudents;
                                    });
                                    // Ne pas fermer le dialog, juste vider le formulaire
                                    studentFormKey.currentState?.resetForm();
                                    _showModernSnackBar(
                                      'Élève ajouté avec succès !',
                                    );
                                  },
                                ),
                                fields: const [],
                                onSubmit: () {
                                  studentFormKey.currentState?.submitForm();
                                },
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('Fermer'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => studentFormKey.currentState
                                        ?.submitForm(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Ajouter'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: _buildModernSearchField()),
                        const SizedBox(width: 16),
                        _buildSortControls(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Bouton d'export des fiches élèves
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _exportStudentProfilesPdf,
                          icon: const Icon(Icons.person, color: Colors.white),
                          label: const Text('Exporter fiches élèves'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FutureBuilder<List<Student>>(
                      future: _getFilteredAndSortedStudentsAsync(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final filteredStudents = snapshot.data!;
                        if (filteredStudents.isEmpty) {
                          return _buildEmptyState();
                        }
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredStudents.length,
                            itemBuilder: (context, index) {
                              final student = filteredStudents[index];
                              return _buildModernStudentCard(student);
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildModernSectionTitle(
                      'Matières de la classe',
                      Icons.book,
                    ),
                    FutureBuilder<List<Course>>(
                      future: _dbService.getCoursesForClass(
                        _nameController.text,
                        _yearController.text,
                      ),
                      builder: (context, snapshot) {
                        final List<Course> classCourses = snapshot.data ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (classCourses.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  'Aucune matière associée à cette classe.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ...classCourses.map(
                              (course) => ListTile(
                                title: Text(course.name),
                                subtitle:
                                    course.description != null &&
                                        course.description!.isNotEmpty
                                    ? Text(course.description!)
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        color: Colors.blue,
                                      ),
                                      tooltip: 'Modifier cette matière',
                                      onPressed: () async {
                                        final nameController =
                                            TextEditingController(
                                              text: course.name,
                                            );
                                        final descController =
                                            TextEditingController(
                                              text: course.description ?? '',
                                            );
                                        await showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Modifier la matière'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                TextField(
                                                  controller: nameController,
                                                  decoration: InputDecoration(
                                                    labelText: 'Nom',
                                                  ),
                                                ),
                                                TextField(
                                                  controller: descController,
                                                  decoration: InputDecoration(
                                                    labelText: 'Description',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                                child: Text('Annuler'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  final newName = nameController
                                                      .text
                                                      .trim();
                                                  final newDesc = descController
                                                      .text
                                                      .trim();
                                                  if (newName.isEmpty) return;
                                                  final updated = Course(
                                                    id: course.id,
                                                    name: newName,
                                                    description:
                                                        newDesc.isNotEmpty
                                                        ? newDesc
                                                        : null,
                                                  );
                                                  await _dbService.updateCourse(
                                                    course.id,
                                                    updated,
                                                  );
                                                  Navigator.of(context).pop();
                                                  setState(() {});
                                                },
                                                child: Text('Enregistrer'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      tooltip: 'Retirer cette matière',
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).cardColor,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            title: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: const [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Color(0xFFE11D48),
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Retirer la matière ?',
                                                  style: TextStyle(
                                                    color: Color(0xFFE11D48),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            content: Text(
                                              'Voulez-vous retirer "${course.name}" de cette classe ?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Annuler'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFE11D48,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Retirer'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await _dbService
                                              .removeCourseFromClass(
                                                _nameController.text,
                                                _yearController.text,
                                                course.id,
                                              );
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              icon: Icon(Icons.add_outlined),
                              label: Text('Ajouter des matières'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () async {
                                final allCourses = await _dbService
                                    .getCourses();
                                final classCourseIds = classCourses
                                    .map((c) => c.id)
                                    .toSet();
                                final availableCourses = allCourses
                                    .where(
                                      (c) => !classCourseIds.contains(c.id),
                                    )
                                    .toList();
                                if (availableCourses.isEmpty) {
                                  // Utiliser un simple AlertDialog car on est dans un CustomDialog sans Scaffold
                                  await showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Information'),
                                      content: const Text(
                                        'Aucune matière disponible à ajouter.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }
                                final Map<String, bool> selected = {
                                  for (final course in availableCourses)
                                    course.id: false,
                                };
                                await showDialog(
                                  context: context,
                                  builder: (context) => StatefulBuilder(
                                    builder: (context, setStateDialog) =>
                                        AlertDialog(
                                          title: Text(
                                            'Ajouter des matières à la classe',
                                          ),
                                          content: SizedBox(
                                            width: 350,
                                            child: ListView(
                                              shrinkWrap: true,
                                              children: availableCourses
                                                  .map(
                                                    (
                                                      course,
                                                    ) => CheckboxListTile(
                                                      value:
                                                          selected[course.id],
                                                      title: Text(course.name),
                                                      subtitle:
                                                          course.description !=
                                                                  null &&
                                                              course
                                                                  .description!
                                                                  .isNotEmpty
                                                          ? Text(
                                                              course
                                                                  .description!,
                                                            )
                                                          : null,
                                                      onChanged: (val) {
                                                        setStateDialog(
                                                          () =>
                                                              selected[course
                                                                      .id] =
                                                                  val ?? false,
                                                        );
                                                      },
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: Text('Annuler'),
                                            ),
                                            ElevatedButton(
                                              onPressed:
                                                  selected.values.any((v) => v)
                                                  ? () async {
                                                      for (final entry
                                                          in selected.entries) {
                                                        if (entry.value) {
                                                          await _dbService
                                                              .addCourseToClass(
                                                                _nameController
                                                                    .text,
                                                                _yearController
                                                                    .text,
                                                                entry.key,
                                                              );
                                                        }
                                                      }
                                                      Navigator.of(
                                                        context,
                                                      ).pop();
                                                      setState(() {});
                                                    }
                                                  : null,
                                              child: Text('Ajouter'),
                                            ),
                                          ],
                                        ),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildModernSectionTitle(
                      'Pondération des matières (cette classe uniquement)',
                      Icons.tune,
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tune,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Définissez le coefficient de chaque matière. Aucune somme imposée (pondération libre).',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Text(
                                  'Somme: ${_sumCoeffs.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FutureBuilder<List<Course>>(
                            future: _dbService.getCoursesForClass(
                              _nameController.text,
                              _yearController.text,
                            ),
                            builder: (context, snapshot) {
                              final subs = snapshot.data ?? _classSubjects;
                              if (subs.isEmpty) {
                                return Text(
                                  'Aucune matière pour ${_nameController.text}.',
                                );
                              }
                              return Column(
                                children: [
                                  Table(
                                    border: TableBorder.all(
                                      color: Colors.blue.shade100,
                                    ),
                                    columnWidths: const {
                                      0: FlexColumnWidth(3),
                                      1: FlexColumnWidth(1),
                                    },
                                    children: [
                                      TableRow(
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                        ),
                                        children: const [
                                          Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Text(
                                              'Matière',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Text(
                                              'Coeff.',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      ...subs.map((c) {
                                        final ctrl =
                                            _coeffCtrls[c.id] ??
                                            TextEditingController();
                                        if (!_coeffCtrls.containsKey(c.id)) {
                                          _coeffCtrls[c.id] = ctrl;
                                        }
                                        return TableRow(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(c.name),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: TextField(
                                                controller: ctrl,
                                                decoration:
                                                    const InputDecoration(
                                                      isDense: true,
                                                      border:
                                                          OutlineInputBorder(),
                                                      hintText: 'ex: 2',
                                                    ),
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                onChanged: (_) =>
                                                    _recomputeSum(),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: _saveCoefficients,
                                        icon: const Icon(Icons.save),
                                        label: const Text('Enregistrer'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: _loadClassSubjectsAndCoeffs,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Recharger'),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      fields: const [],
      onSubmit: () {
        if (!_isLoading) _saveClass();
      },
      actions: [
        // Delete class
        OutlinedButton(
          onPressed: _isLoading
              ? null
              : () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Supprimer la classe ?'),
                      content: Text(
                        'Voulez-vous vraiment supprimer la classe "${_nameController.text}" ?\nCette action est irréversible.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE53E3E),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Supprimer'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      setState(() => _isLoading = true);
                      // Préserver les données pour permettre l'annulation
                      final deleted = Class(
                        name: _nameController.text,
                        academicYear: _yearController.text,
                        titulaire: _titulaireController.text.isNotEmpty
                            ? _titulaireController.text
                            : null,
                        fraisEcole: _fraisEcoleController.text.isNotEmpty
                            ? double.tryParse(_fraisEcoleController.text)
                            : null,
                        fraisCotisationParallele:
                            _fraisCotisationParalleleController.text.isNotEmpty
                            ? double.tryParse(
                                _fraisCotisationParalleleController.text,
                              )
                            : null,
                      );
                      await _dbService.deleteClassByName(
                        _nameController.text,
                        _yearController.text,
                      );
                      setState(() => _isLoading = false);
                      showRootSnackBar(
                        SnackBar(
                          content: const Text('Classe supprimée'),
                          action: SnackBarAction(
                            label: 'Annuler',
                            onPressed: () async {
                              try {
                                await _dbService.insertClass(deleted);
                                showRootSnackBar(
                                  const SnackBar(
                                    content: Text('Suppression annulée'),
                                  ),
                                );
                              } catch (e) {
                                showRootSnackBar(
                                  SnackBar(
                                    content: Text('Annulation impossible: $e'),
                                  ),
                                );
                              }
                            },
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      if (mounted) Navigator.of(context).pop();
                    } catch (e) {
                      setState(() => _isLoading = false);
                      await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Impossible de supprimer'),
                          content: Text(e.toString()),
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
                },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: const BorderSide(color: Color(0xFFE53E3E)),
            foregroundColor: const Color(0xFFE53E3E),
          ),
          child: const Text(
            'Supprimer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        OutlinedButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: const Text(
            'Fermer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveClass,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3182CE),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Enregistrer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Future<void> _exportSubjectGradesTemplateExcel(
    String subjectName,
    String selectedTerm,
    int devCount,
    int compCount,
  ) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Génération du modèle Excel [$subjectName]...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final workbook = xls.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Matiere_${subjectName.replaceAll(' ', '_')}';

      final headerStyle = workbook.styles.add('headerSubjectStyle');
      headerStyle.bold = true;
      headerStyle.backColor = '#E5F2FF';
      headerStyle.hAlign = xls.HAlignType.center;
      headerStyle.vAlign = xls.VAlignType.center;

      int col = 1;
      void setHeader(int c, String text) {
        final range = sheet.getRangeByIndex(1, c);
        range.setText(text);
        range.cellStyle = headerStyle;
        sheet.autoFitColumn(c);
      }

      setHeader(col++, 'ID_Eleve');
      setHeader(col++, 'Nom');
      setHeader(col++, 'Classe');
      setHeader(col++, 'Annee');
      setHeader(col++, 'Periode');
      // Colonnes dynamiques Devoir(s) (valeurs uniquement)
      final List<int> devoirCols = [];
      for (int i = 0; i < devCount; i++) {
        final String label = devCount == 1 ? 'Devoir' : 'Devoir ${i + 1}';
        final dCol = col++;
        setHeader(dCol, '$label [$subjectName]');
        devoirCols.add(dCol);
      }
      // Colonnes dynamiques Composition(s) (valeurs uniquement)
      final List<int> compCols = [];
      for (int i = 0; i < compCount; i++) {
        final String label = compCount == 1 ? 'Composition' : 'Composition ${i + 1}';
        final cCol = col++;
        setHeader(cCol, '$label [$subjectName]');
        compCols.add(cCol);
      }

      final Map<String, double> subjectCoeffs = await _dbService
          .getClassSubjectCoefficients(_nameController.text, _yearController.text);
      final double coeffMatiere = subjectCoeffs[subjectName] ?? 1;

      for (int i = 0; i < _students.length; i++) {
        final row = i + 2;
        final s = _students[i];
        sheet.getRangeByIndex(row, 1).setText(s.id);
        sheet.getRangeByIndex(row, 2).setText(s.name);
        sheet.getRangeByIndex(row, 3).setText(_nameController.text);
        sheet.getRangeByIndex(row, 4).setText(_yearController.text);
        sheet.getRangeByIndex(row, 5).setText(selectedTerm);

        // aucune préremplissage pour devoir/comp: l'utilisateur saisit uniquement les notes
        // Pas de colonnes prof/app/moyClasse dans ce modèle simplifié
      }

      final lastRow = (_students.isNotEmpty ? _students.length : 1) + 1;
      // Validation 0-20 sur toutes colonnes de notes (devoirs + compositions)
      for (final colIndex in [...devoirCols, ...compCols]) {
        try {
          final dv = sheet.getRangeByIndex(2, colIndex, lastRow, colIndex).dataValidation;
          (dv as dynamic).allowType = 2; // decimal
          try { (dv as dynamic).operator = 6; } catch (_) { try { (dv as dynamic).compareOperator = 6; } catch (_) {} }
          (dv as dynamic).firstFormula = '0';
          (dv as dynamic).secondFormula = '20';
          (dv as dynamic).promptBoxTitle = 'Validation';
          (dv as dynamic).promptBoxText = 'Entrez une note entre 0 et 20';
          (dv as dynamic).showPromptBox = true;
        } catch (_) {}
      }

      try { (sheet as dynamic).freezePanes(2, 1); } catch (_) {}
      for (int c = 1; c <= col; c++) { sheet.autoFitColumn(c); }

      // Masquer les colonnes de métadonnées (ID, Classe, Annee, Periode)
      try { (sheet as dynamic).hideColumn(1); } catch (_) { try { sheet.getRangeByIndex(1,1,1,1).columnWidth = 0; } catch (_) {} }
      try { (sheet as dynamic).hideColumn(3); } catch (_) { try { sheet.getRangeByIndex(1,3,1,3).columnWidth = 0; } catch (_) {} }
      try { (sheet as dynamic).hideColumn(4); } catch (_) { try { sheet.getRangeByIndex(1,4,1,4).columnWidth = 0; } catch (_) {} }
      try { (sheet as dynamic).hideColumn(5); } catch (_) { try { sheet.getRangeByIndex(1,5,1,5).columnWidth = 0; } catch (_) {} }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;

      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final safeSubject = subjectName.replaceAll(' ', '_');
      final fileName =
          'modele_notes_${_nameController.text}_${safeSubject}_${_yearController.text}_${selectedTerm.replaceAll(' ', '_')}_$formattedDate.xlsx';
      final file = File('$dirPath/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modèle Excel [$subjectName] généré : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur génération modèle Excel [$subjectName] : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _exportSubjectGradesTemplatePdf(
    String subjectName,
    String selectedTerm,
    int devCount,
    int compCount,
  ) async {
    try {
      final pdf = pw.Document();
      final title = 'Modèle de saisie des notes';
      final className = _nameController.text;
      final year = _yearController.text;

      // Charger coefficient matière et enseignant assigné
      final subjectCoeffs = await _dbService.getClassSubjectCoefficients(
        className,
        year,
      );
      final double coeffMatiere = subjectCoeffs[subjectName] ?? 1;
      String teacherName = (_titulaireController.text).trim();
      try {
        final courses = await _dbService.getCoursesForClass(className, year);
        final subj = courses.firstWhere(
          (c) => c.name == subjectName,
          orElse: () => Course.empty(),
        );
        final staff = await _dbService.getStaff();
        bool teachesSubject(Staff s) {
          final crs = s.courses;
          final cls = s.classes;
          final matchCourse =
              crs.contains(subj.id) ||
              crs.any((x) => x.toLowerCase() == subjectName.toLowerCase());
          final matchClass = cls.contains(className);
          return matchCourse && matchClass;
        }
        final t = staff.firstWhere(teachesSubject, orElse: () => Staff.empty());
        if (t.id.isNotEmpty) {
          teacherName = t.name;
        }
      } catch (_) {}

      // Charger infos établissement et préparer thème (filigrane)
      final SchoolInfo? schoolInfo = await _dbService.getSchoolInfo();
      final PdfPageFormat _pageFormat = PdfPageFormat.a4;
      final pw.PageTheme _pageTheme = pw.PageTheme(
        pageFormat: _pageFormat,
        margin: const pw.EdgeInsets.all(24),
        buildBackground: (schoolInfo != null &&
                schoolInfo.logoPath != null &&
                File(schoolInfo.logoPath!).existsSync())
            ? (context) => pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Opacity(
                    opacity: 0.06,
                    child: pw.Image(
                      pw.MemoryImage(
                        File(schoolInfo.logoPath!).readAsBytesSync(),
                      ),
                      fit: pw.BoxFit.cover,
                    ),
                  ),
                )
            : null,
      );

      pdf.addPage(
        pw.MultiPage(
          pageTheme: _pageTheme,
          build: (context) {
            final headers = <String>['N°', 'Nom'];
            for (int i = 0; i < devCount; i++) {
              final String label = devCount == 1 ? 'Devoir' : 'Devoir ${i + 1}';
              headers.add(label);
            }
            for (int i = 0; i < compCount; i++) {
              final String label = compCount == 1 ? 'Composition' : 'Composition ${i + 1}';
              headers.add(label);
            }
            final rows = <List<String>>[];
            for (int i = 0; i < _students.length; i++) {
              final s = _students[i];
              final row = <String>[
                (i + 1).toString(),
                s.name,
              ];
              for (int j = 0; j < devCount; j++) {
                row.add('');
              }
              for (int j = 0; j < compCount; j++) {
                row.add('');
              }
              rows.add(row);
            }
            // En-tête harmonisé (ministère / république)
            pw.Widget buildHeader() {
              final left = (schoolInfo?.ministry ?? '').trim();
              final rightTop = (schoolInfo?.republic ?? '').trim();
              final rightBottom = (schoolInfo?.republicMotto ?? '').trim();
              final schoolName = (schoolInfo?.name ?? '').trim().toUpperCase();
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (left.isNotEmpty)
                              pw.Text(left.toUpperCase(),
                                  style: pw.TextStyle(fontSize: 8)),
                            if ((schoolInfo?.educationDirection ?? '').isNotEmpty)
                              pw.Text(
                                (schoolInfo?.educationDirection ?? '').toUpperCase(),
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            if ((schoolInfo?.inspection ?? '').isNotEmpty)
                              pw.Text(
                                (schoolInfo?.inspection ?? '').toUpperCase(),
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            if (rightTop.isNotEmpty)
                              pw.Text(rightTop.toUpperCase(),
                                  style: const pw.TextStyle(fontSize: 8)),
                            if (rightBottom.isNotEmpty)
                              pw.Text(
                                rightBottom.toUpperCase(),
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontStyle: pw.FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  if (schoolInfo != null &&
                      (schoolInfo.logoPath ?? '').isNotEmpty &&
                      File(schoolInfo.logoPath!).existsSync())
                    pw.Center(
                      child: pw.Container(
                        height: 40,
                        width: 40,
                        child: pw.Image(
                          pw.MemoryImage(
                            File(schoolInfo.logoPath!).readAsBytesSync(),
                          ),
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    ),
                  pw.SizedBox(height: 4),
                  pw.Center(
                    child: pw.Text(
                      schoolName.isNotEmpty ? schoolName : 'FEUILLE DE NOTES',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.blueGrey300),
                ],
              );
            }

            return [
              buildHeader(),
              pw.SizedBox(height: 6),
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text('Classe: $className\nAnnée: $year'),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      'Matière: $subjectName\nProfesseur: $teacherName',
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Coefficient matière: ${coeffMatiere.toStringAsFixed(2)}',
                  ),
                  pw.Text('Sur: 20    Période: $selectedTerm'),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                headers: headers,
                data: rows,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blue50,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                border: pw.TableBorder.all(color: PdfColors.blue100),
                headerAlignment: pw.Alignment.center,
              ),
              pw.SizedBox(height: 14),
              pw.Text('Remarques:'),
              pw.SizedBox(height: 6),
              pw.Container(height: 0.8, color: PdfColors.blueGrey300),
              pw.SizedBox(height: 6),
              pw.Container(height: 0.8, color: PdfColors.blueGrey300),
              pw.SizedBox(height: 18),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Fait à: ______________________'),
                  pw.Text('Le: ____ / ____ / ______'),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(children: [
                    pw.Text("Signature de l'enseignant"),
                    pw.SizedBox(height: 28),
                    pw.Container(width: 160, height: 0.8, color: PdfColors.blueGrey300),
                  ]),
                  pw.Column(children: [
                    pw.Text("Cachet et signature de l'établissement"),
                    pw.SizedBox(height: 28),
                    pw.Container(width: 200, height: 0.8, color: PdfColors.blueGrey300),
                  ]),
                ],
              ),
            ];
          },
        ),
      );

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final safeSubject = subjectName.replaceAll(' ', '_');
      final fileName =
          'modele_notes_${_nameController.text}_${safeSubject}_${_yearController.text}_$formattedDate.pdf';
      final file = File('$dirPath/$fileName');
      await file.writeAsBytes(await pdf.save());
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modèle PDF [$subjectName] généré : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur génération modèle PDF [$subjectName] : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showSubjectTemplateDialog() async {
    final subjects = await _dbService.getCoursesForClass(
      _nameController.text,
      _yearController.text,
    );
    if (subjects.isEmpty) {
      _showModernSnackBar("Aucune matière n'est associée à cette classe", isError: true);
      return;
    }
    String selected = subjects.first.name;
    String mode = 'Trimestre';
    List<String> terms = ['Trimestre 1', 'Trimestre 2', 'Trimestre 3'];
    String term = terms.first;
    int devCount = 1;
    int compCount = 1;
    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Modèle par matière'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choisissez une matière :'),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: selected,
                    isExpanded: true,
                    items: subjects
                        .map((c) => DropdownMenuItem<String>(
                              value: c.name,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => selected = v ?? selected),
                  ),
                  const SizedBox(height: 12),
                  const Text('Période :'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: mode,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'Trimestre', child: Text('Trimestre')),
                            DropdownMenuItem(value: 'Semestre', child: Text('Semestre')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              mode = v;
                              terms = v == 'Trimestre'
                                  ? ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']
                                  : ['Semestre 1', 'Semestre 2'];
                              term = terms.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: term,
                          isExpanded: true,
                          items: terms
                              .map((t) => DropdownMenuItem<String>(
                                    value: t,
                                    child: Text(t),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => term = v ?? term),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Nombre de colonnes par type :'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Text('Devoirs: '),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: devCount,
                              items: [1,2,3,4,5]
                                  .map((n) => DropdownMenuItem<int>(value: n, child: Text(n.toString())))
                                  .toList(),
                              onChanged: (v) => setState(() => devCount = v ?? devCount),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            const Text('Compositions: '),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: compCount,
                              items: [1,2,3,4,5]
                                  .map((n) => DropdownMenuItem<int>(value: n, child: Text(n.toString())))
                                  .toList(),
                              onChanged: (v) => setState(() => compCount = v ?? compCount),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _exportSubjectGradesTemplatePdf(selected, term, devCount, compCount);
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _exportSubjectGradesTemplateExcel(selected, term, devCount, compCount);
                  },
                  icon: const Icon(Icons.table_view),
                  label: const Text('Excel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildStatsAndFilter() {
    return FutureBuilder<List<double>>(
      future: _getStatsForStudents(),
      builder: (context, snapshot) {
        final int nbPayes = snapshot.hasData ? snapshot.data![0].toInt() : 0;
        final int nbAttente = snapshot.hasData ? snapshot.data![1].toInt() : 0;
        final int total = nbPayes + nbAttente;
        final double percent = total > 0 ? (nbPayes / total * 100) : 0;
        return Row(
          children: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Payé : $nbPayes',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'En attente : $nbAttente',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              'Paiement global : ${percent.toStringAsFixed(1)}%',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            DropdownButton<String>(
              value: _studentStatusFilter,
              items: const [
                DropdownMenuItem(value: 'Tous', child: Text('Tous')),
                DropdownMenuItem(value: 'Payé', child: Text('Payé')),
                DropdownMenuItem(
                  value: 'En attente',
                  child: Text('En attente'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _studentStatusFilter = value!),
            ),
          ],
        );
      },
    );
  }

  Future<List<double>> _getStatsForStudents() async {
    int nbPayes = 0;
    int nbAttente = 0;
    final double fraisEcole = double.tryParse(_fraisEcoleController.text) ?? 0;
    final double fraisCotisation =
        double.tryParse(_fraisCotisationParalleleController.text) ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    for (final s in _students) {
      final totalPaid = await _dbService.getTotalPaidForStudent(s.id);
      if (montantMax > 0 && totalPaid >= montantMax) {
        nbPayes++;
      } else {
        nbAttente++;
      }
    }
    return [nbPayes.toDouble(), nbAttente.toDouble()];
  }

  void _exportStudentsPdf() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final studentsList = _students.map((student) {
        final classe = widget.classe;
        return {'student': student, 'classe': classe};
      }).toList();

      final pdfBytes = await PdfService.exportStudentsListPdf(
        students: studentsList,
      );
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé

      // Nom de fichier plus descriptif avec date formatée
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final fileName =
          'liste_eleves_${widget.classe.name}_${formattedDate}.pdf';
      final file = File('$dirPath/$fileName');

      await file.writeAsBytes(pdfBytes);

      // Ouvrir automatiquement le fichier
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF réussi : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur export PDF élèves : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export PDF : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _exportStudentsExcel() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final studentsList = _students.map((student) {
        final classe = widget.classe;
        return {'student': student, 'classe': classe};
      }).toList();

      // Trie par nom
      studentsList.sort(
        (a, b) => ((a['student'] as Student).name).compareTo(
          (b['student'] as Student).name,
        ),
      );

      final excel = Excel.createExcel();
      final sheet = excel['Élèves'];

      // En-têtes avec formatage
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.blue50,
        fontColorHex: ExcelColor.blue900,
      );

      final headerRow = [
        TextCellValue('N°'),
        TextCellValue('ID'),
        TextCellValue('Matricule'),
        TextCellValue('Prénom'),
        TextCellValue('Nom'),
        TextCellValue('Sexe'),
        TextCellValue('Statut'),
        TextCellValue('Classe'),
        TextCellValue('Année'),
        TextCellValue('Date de naissance'),
        TextCellValue('Adresse'),
        TextCellValue('Contact'),
        TextCellValue('Email'),
        TextCellValue('Contact urgence'),
        TextCellValue('Tuteur'),
        TextCellValue('Contact tuteur'),
        TextCellValue('Date d\'inscription'),
        TextCellValue('Infos médicales'),
        TextCellValue('Photo'),
      ];
      sheet.appendRow(headerRow);

      // Appliquer le style aux en-têtes
      for (int i = 0; i < headerRow.length; i++) {
        sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
                .cellStyle =
            headerStyle;
      }

      // Données des élèves
      for (int i = 0; i < studentsList.length; i++) {
        final student = studentsList[i]['student'] as Student;
        final classe = studentsList[i]['classe'];
        final prenom = student.firstName;
        final nom = student.lastName;

        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(student.id),
          TextCellValue(student.matricule ?? ''),
          TextCellValue(prenom),
          TextCellValue(nom),
          TextCellValue(student.gender == 'M' ? 'Garçon' : 'Fille'),
          TextCellValue(student.status),
          TextCellValue(student.className),
          TextCellValue(student.academicYear),
          TextCellValue(student.dateOfBirth),
          TextCellValue(student.address),
          TextCellValue(student.contactNumber),
          TextCellValue(student.email),
          TextCellValue(student.emergencyContact),
          TextCellValue(student.guardianName),
          TextCellValue(student.guardianContact),
          TextCellValue(student.enrollmentDate),
          TextCellValue(student.medicalInfo ?? ''),
          TextCellValue(student.photoPath ?? ''),
        ]);
      }

      // Ajuster la largeur des colonnes
      for (int i = 0; i < headerRow.length; i++) {
        sheet.setColumnWidth(i, 15);
      }

      final bytes = excel.encode()!;
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé

      // Nom de fichier plus descriptif avec date formatée
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final fileName =
          'liste_eleves_${widget.classe.name}_${formattedDate}.xlsx';
      final file = File('$dirPath/$fileName');

      await file.writeAsBytes(bytes);

      // Ouvrir automatiquement le fichier
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel réussi : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur export Excel élèves : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Excel : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _exportStudentsWord() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Word en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé

      final docx = await _generateStudentsDocx();

      // Nom de fichier plus descriptif avec date formatée
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final fileName = 'liste_eleves_${widget.classe.name}_$formattedDate.docx';
      final file = File('$dirPath/$fileName');

      await file.writeAsBytes(docx);

      // Ouvrir automatiquement le fichier
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Word réussi : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur export Word élèves : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Word : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _exportStudentProfilesPdf() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Génération des fiches profil en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return; // Annulé

      // Générer une fiche profil pour chaque élève
      for (int i = 0; i < _students.length; i++) {
        final student = _students[i];
        final pdfBytes = await PdfService.exportStudentProfilePdf(
          student: student,
          classe: widget.classe,
        );

        // Nom de fichier avec le nom de l'élève
        final fileName =
            'fiche_profil_${'${student.firstName}_${student.lastName}'.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('$dirPath/$fileName');

        await file.writeAsBytes(pdfBytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_students.length} fiches profil générées avec succès dans : $dirPath',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print('Erreur export fiches profil : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur génération des fiches profil : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<List<int>> _generateStudentsDocx() async {
    try {
      final bytes = await DefaultAssetBundle.of(
        context,
      ).load('assets/empty.docx');
      final docx = await DocxTemplate.fromBytes(bytes.buffer.asUint8List());
      final studentsList = List<Map<String, dynamic>>.from(
        _students.map((student) {
          final classe = widget.classe;
          return {'student': student, 'classe': classe};
        }),
      );
      studentsList.sort(
        (a, b) => ((a['student'] as Student).name).compareTo(
          (b['student'] as Student).name,
        ),
      );
      final rows = List<RowContent>.generate(studentsList.length, (i) {
        final student = studentsList[i]['student'] as Student;
        final classe = studentsList[i]['classe'] as Class;
        final prenom = student.firstName;
        final nom = student.lastName;
        return RowContent()
          ..add(TextContent("numero", (i + 1).toString()))
          ..add(TextContent("nom", nom))
          ..add(TextContent("prenom", prenom))
          ..add(TextContent("sexe", student.gender == 'M' ? 'Garçon' : 'Fille'))
          ..add(TextContent("classe", student.className))
          ..add(TextContent("annee", classe.academicYear))
          ..add(TextContent("date_naissance", student.dateOfBirth))
          ..add(TextContent("adresse", student.address))
          ..add(TextContent("contact", student.contactNumber))
          ..add(TextContent("email", student.email))
          ..add(TextContent("tuteur", student.guardianName))
          ..add(TextContent("contact_tuteur", student.guardianContact));
      });
      final table = TableContent("eleves", List<RowContent>.from(rows));
      final content = Content()..add(table);
      final d = await docx.generate(content);
      return d!;
    } catch (e) {
      print('Erreur asset Word élèves : $e');
      rethrow;
    }
  }

  Future<void> _exportGradesTemplateExcel() async {
    try {
      // Afficher l'indicateur de progression
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Génération du modèle Excel en cours...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      // Récupération des matières pour la classe
      final List<Course> classSubjects = await _dbService.getCoursesForClass(
        _nameController.text,
        _yearController.text,
      );
      if (classSubjects.isEmpty) {
        _showModernSnackBar(
          "Aucune matière n'est associée à cette classe",
          isError: true,
        );
        return;
      }

      final workbook = xls.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Modèle';

      // Styles de base
      final headerStyle = workbook.styles.add('headerStyle');
      headerStyle.bold = true;
      headerStyle.backColor = '#E5F2FF';
      headerStyle.hAlign = xls.HAlignType.center;
      headerStyle.vAlign = xls.VAlignType.center;

      // En-têtes fixes
      int col = 1;
      void setHeader(int c, String text) {
        final range = sheet.getRangeByIndex(1, c);
        range.setText(text);
        range.cellStyle = headerStyle;
        sheet.autoFitColumn(c);
      }

      setHeader(col++, 'ID_Eleve');
      setHeader(col++, 'Nom');
      setHeader(col++, 'Classe');
      setHeader(col++, 'Annee');
      setHeader(col++, 'Periode');
      // Champs assiduité & conduite (généraux)
      final absJustCol = col++;
      setHeader(absJustCol, 'Abs Justifiees');
      final absInjCol = col++;
      setHeader(absInjCol, 'Abs Injustifiees');
      final retardsCol = col++;
      setHeader(retardsCol, 'Retards');
      final presenceCol = col++;
      setHeader(presenceCol, 'Presence (%)');
      final conduiteCol = col++;
      setHeader(conduiteCol, 'Conduite');
      // Champs de synthèse bulletin
      final apprGenCol = col++;
      setHeader(apprGenCol, 'Appreciation Generale');
      final decisionCol = col++;
      setHeader(decisionCol, 'Decision');
      final recommandCol = col++;
      setHeader(recommandCol, 'Recommandations');
      final forcesCol = col++;
      setHeader(forcesCol, 'Forces');
      final pointsDevCol = col++;
      setHeader(pointsDevCol, 'Points a Developper');
      final sanctionsCol = col++;
      setHeader(sanctionsCol, 'Sanctions');

      // Pour chaque matière, on ajoute des colonnes
      // Devoir/Composition + Coeff + Sur + Prof + App + MoyClasse
      final List<_SubjectColumnMeta> subjectColumns = [];
      for (final subject in classSubjects) {
        final subjectName = subject.name;
        final devoirCol = col++;
        setHeader(devoirCol, 'Devoir [$subjectName]');
        final coeffDevCol = col++;
        setHeader(coeffDevCol, 'Coeff Devoir [$subjectName]');
        final surDevCol = col++;
        setHeader(surDevCol, 'Sur Devoir [$subjectName]');

        final compoCol = col++;
        setHeader(compoCol, 'Composition [$subjectName]');
        final coeffCompCol = col++;
        setHeader(coeffCompCol, 'Coeff Composition [$subjectName]');
        final surCompCol = col++;
        setHeader(surCompCol, 'Sur Composition [$subjectName]');

        final profCol = col++;
        setHeader(profCol, 'Prof [$subjectName]');
        final appCol = col++;
        setHeader(appCol, 'App [$subjectName]');
        final moyClasseCol = col++;
        setHeader(moyClasseCol, 'MoyClasse [$subjectName]');

        subjectColumns.add(
          _SubjectColumnMeta(
            name: subjectName,
            devoirCol: devoirCol,
            coeffDevoirCol: coeffDevCol,
            surDevoirCol: surDevCol,
            compoCol: compoCol,
            coeffCompoCol: coeffCompCol,
            surCompoCol: surCompCol,
            profCol: profCol,
            appCol: appCol,
            moyClasseCol: moyClasseCol,
          ),
        );
      }

      // Charger les coefficients de matières définis au niveau de la classe
      final Map<String, double> subjectCoeffs = await _dbService
          .getClassSubjectCoefficients(
            _nameController.text,
            _yearController.text,
          );

      // Remplir les lignes élèves
      for (int i = 0; i < _students.length; i++) {
        final row = i + 2; // 1 = header
        final s = _students[i];
        sheet.getRangeByIndex(row, 1).setText(s.id);
        sheet.getRangeByIndex(row, 2).setText(s.name);
        sheet.getRangeByIndex(row, 3).setText(_nameController.text);
        sheet.getRangeByIndex(row, 4).setText(_yearController.text);
        sheet.getRangeByIndex(row, 5).setText('Trimestre 1');

        // Valeurs par défaut pour assiduité
        sheet.getRangeByIndex(row, absJustCol).setNumber(0);
        sheet.getRangeByIndex(row, absInjCol).setNumber(0);
        sheet.getRangeByIndex(row, retardsCol).setNumber(0);
        sheet.getRangeByIndex(row, presenceCol).setNumber(0);
        sheet.getRangeByIndex(row, conduiteCol).setText('');
        sheet.getRangeByIndex(row, apprGenCol).setText('');
        sheet.getRangeByIndex(row, decisionCol).setText('');
        sheet.getRangeByIndex(row, recommandCol).setText('');
        sheet.getRangeByIndex(row, forcesCol).setText('');
        sheet.getRangeByIndex(row, pointsDevCol).setText('');
        sheet.getRangeByIndex(row, sanctionsCol).setText('');

        // Valeurs par défaut pour coeff (matière) et "sur"
        for (final meta in subjectColumns) {
          final double coeffMatiere = subjectCoeffs[meta.name] ?? 1;
          sheet
              .getRangeByIndex(row, meta.coeffDevoirCol)
              .setNumber(coeffMatiere);
          sheet.getRangeByIndex(row, meta.surDevoirCol).setNumber(20);
          sheet
              .getRangeByIndex(row, meta.coeffCompoCol)
              .setNumber(coeffMatiere);
          sheet.getRangeByIndex(row, meta.surCompoCol).setNumber(20);
        }
      }

      // Validation des données (0-20) sur colonnes de notes
      int lastRow = _students.length + 1;
      // Validations assiduité
      try {
        final absJRange = sheet.getRangeByIndex(
          2,
          absJustCol,
          lastRow,
          absJustCol,
        );
        final absIRange = sheet.getRangeByIndex(
          2,
          absInjCol,
          lastRow,
          absInjCol,
        );
        final retRange = sheet.getRangeByIndex(
          2,
          retardsCol,
          lastRow,
          retardsCol,
        );
        final presRange = sheet.getRangeByIndex(
          2,
          presenceCol,
          lastRow,
          presenceCol,
        );
        for (final r in [absJRange, absIRange, retRange]) {
          final dv = r.dataValidation;
          try {
            (dv as dynamic).allowType = 2;
          } catch (_) {}
          try {
            (dv as dynamic).operator = 6;
          } catch (_) {
            try {
              (dv as dynamic).compareOperator = 6;
            } catch (_) {}
          }
          try {
            (dv as dynamic).firstFormula = '0';
            (dv as dynamic).secondFormula = '999';
          } catch (_) {}
          try {
            (dv as dynamic).promptBoxTitle = 'Validation';
            (dv as dynamic).promptBoxText = 'Entrez un entier >= 0';
            (dv as dynamic).showPromptBox = true;
          } catch (_) {}
        }
        final dvp = presRange.dataValidation;
        try {
          (dvp as dynamic).allowType = 2;
        } catch (_) {}
        try {
          (dvp as dynamic).operator = 6;
        } catch (_) {
          try {
            (dvp as dynamic).compareOperator = 6;
          } catch (_) {}
        }
        try {
          (dvp as dynamic).firstFormula = '0';
          (dvp as dynamic).secondFormula = '100';
        } catch (_) {}
        try {
          (dvp as dynamic).promptBoxTitle = 'Validation';
          (dvp as dynamic).promptBoxText = '0 à 100';
          (dvp as dynamic).showPromptBox = true;
        } catch (_) {}
      } catch (_) {}

      for (final meta in subjectColumns) {
        final dvRange = sheet.getRangeByIndex(
          2,
          meta.devoirCol,
          lastRow,
          meta.devoirCol,
        );
        final compRange = sheet.getRangeByIndex(
          2,
          meta.compoCol,
          lastRow,
          meta.compoCol,
        );

        try {
          final dv = dvRange.dataValidation;
          // use dynamic to avoid enum references
          (dv as dynamic).allowType = 2; // decimal
          try {
            (dv as dynamic).operator = 6; // between
          } catch (_) {
            try {
              (dv as dynamic).compareOperator = 6; // between
            } catch (_) {}
          }
          (dv as dynamic).firstFormula = '0';
          (dv as dynamic).secondFormula = '20';
          (dv as dynamic).promptBoxTitle = 'Validation';
          (dv as dynamic).promptBoxText = 'Entrez une note entre 0 et 20';
          (dv as dynamic).showPromptBox = true;
        } catch (_) {}

        try {
          final cv = compRange.dataValidation;
          (cv as dynamic).allowType = 2; // decimal
          try {
            (cv as dynamic).operator = 6; // between
          } catch (_) {
            try {
              (cv as dynamic).compareOperator = 6; // between
            } catch (_) {}
          }
          (cv as dynamic).firstFormula = '0';
          (cv as dynamic).secondFormula = '20';
          (cv as dynamic).promptBoxTitle = 'Validation';
          (cv as dynamic).promptBoxText = 'Entrez une note entre 0 et 20';
          (cv as dynamic).showPromptBox = true;
        } catch (_) {}
      }

      // Figer la première ligne et auto-fit (protect against API differences)
      try {
        (sheet as dynamic).freezePanes(2, 1);
      } catch (_) {}
      for (int c = 1; c <= col; c++) {
        sheet.autoFitColumn(c);
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;

      // Nom de fichier plus descriptif avec date formatée
      final now = DateTime.now();
      final formattedDate =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final fileName =
          'modele_notes_${_nameController.text}_${_yearController.text}_$formattedDate.xlsx';
      final file = File('$dirPath/$fileName');

      await file.writeAsBytes(bytes, flush: true);

      // Ouvrir automatiquement le fichier
      await OpenFile.open(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modèle Excel généré : ${file.path}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      print('Erreur génération modèle Excel : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur génération du modèle : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

String _formatIsoToDisplay(String iso) {
  if (iso.isEmpty) return 'Non renseigné';
  try {
    final d = DateTime.parse(iso);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  } catch (_) {
    return iso;
  }
}

String _calculateAgeFromIso(String iso) {
  if (iso.isEmpty) return 'Non renseigné';
  try {
    final birth = DateTime.parse(iso);
    final now = DateTime.now();
    int age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return '$age ans';
  } catch (_) {
    return 'Non renseigné';
  }
}

class _SubjectColumnMeta {
  final String name;
  final int devoirCol;
  final int coeffDevoirCol;
  final int surDevoirCol;
  final int compoCol;
  final int coeffCompoCol;
  final int surCompoCol;
  final int profCol;
  final int appCol;
  final int moyClasseCol;

  _SubjectColumnMeta({
    required this.name,
    required this.devoirCol,
    required this.coeffDevoirCol,
    required this.surDevoirCol,
    required this.compoCol,
    required this.coeffCompoCol,
    required this.surCompoCol,
    required this.profCol,
    required this.appCol,
    required this.moyClasseCol,
  });
}
