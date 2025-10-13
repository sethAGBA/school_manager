import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/screens/dashboard_home.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/category.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:excel/excel.dart' as ex show Excel;
import 'package:sqflite/sqflite.dart';
// import 'package:pdf/pdf.dart' as pw; // removed unused import
import 'package:school_manager/screens/students/student_profile_page.dart';
import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:school_manager/screens/statistics_modal.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'dart:ui' as ui;

// Import/Export helpers (top-level)
class _ImportPreview {
  final List<String> headers;
  final List<List<dynamic>> rows;
  final List<String> issues;
  _ImportPreview({
    required this.headers,
    required this.rows,
    required this.issues,
  });
}

class _ImportResult {
  final List<Map<String, dynamic>> rowResults;
  _ImportResult(this.rowResults);
}

class AppColors {
  static const primaryBlue = Color(0xFF3B82F6);
  static const bluePrimary = Color(0xFF3B82F6);
  static const successGreen = Color(0xFF10B981);
  static const shadowDark = Color(0xFF000000);
}

// SchoolInfo et loadSchoolInfo déplacés dans `models/school_info.dart`

// Ajout du notifier global pour le niveau scolaire
final schoolLevelNotifier = ValueNotifier<String>('');

class GradesPage extends StatefulWidget {
  const GradesPage({Key? key}) : super(key: key);

  @override
  _GradesPageState createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> with TickerProviderStateMixin {
  late TabController _tabController;
  String? selectedSubject;
  String? selectedTerm;
  String? selectedStudent;
  String? selectedAcademicYear;
  String? selectedClass;
  bool _isDarkMode = true;
  String _studentSearchQuery = '';
  String _reportSearchQuery = '';
  String _archiveSearchQuery = '';
  String _periodMode = 'Trimestre'; // ou 'Semestre'
  int _archiveCurrentPage = 0;
  final int _archiveItemsPerPage = 10;
  bool _searchAllYears = false;
  // Ensure we only auto-save default subject appreciations once per subject per build context
  final Set<String> _initialSubjectAppSave = {};
  // Empêche les rechargements multiples des synthèses déjà chargées
  final Set<String> _loadedReportCardKeys = {};

  List<Student> students = [];
  List<Class> classes = [];
  List<Course> subjects = [];
  List<Category> categories = [];

  Future<Map<String, Map<String, num>>> _computeRankPerTermForStudentUI(
    Student student,
    List<String> terms,
  ) async {
    final Map<String, Map<String, num>> rankPerTerm = {};
    String effectiveYear;
    if (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty) {
      effectiveYear = selectedAcademicYear!;
    } else {
      effectiveYear = classes
          .firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          )
          .academicYear;
    }
    const double eps = 0.001;
    for (final term in terms) {
      final gradesForTerm = await _dbService.getAllGradesForPeriod(
        className: selectedClass!,
        academicYear: effectiveYear,
        term: term,
      );
      final Map<String, double> nByStudent = {};
      final Map<String, double> cByStudent = {};
      for (final g in gradesForTerm.where(
        (g) =>
            (g.type == 'Devoir' || g.type == 'Composition') &&
            g.value != null &&
            g.value != 0,
      )) {
        if (g.maxValue > 0 && g.coefficient > 0) {
          nByStudent[g.studentId] =
              (nByStudent[g.studentId] ?? 0) +
              ((g.value / g.maxValue) * 20) * g.coefficient;
          cByStudent[g.studentId] =
              (cByStudent[g.studentId] ?? 0) + g.coefficient;
        }
      }
      final List<double> avgs = [];
      double myAvg = 0.0;
      nByStudent.forEach((sid, n) {
        final c = cByStudent[sid] ?? 0.0;
        final avg = c > 0 ? (n / c) : 0.0;
        avgs.add(avg);
        if (sid == student.id) myAvg = avg;
      });
      avgs.sort((a, b) => b.compareTo(a));
      final int nb = avgs.length;
      final int rank = 1 + avgs.where((v) => (v - myAvg) > eps).length;
      rankPerTerm[term] = {'rank': rank, 'nb': nb, 'avg': myAvg};
    }
    return rankPerTerm;
  }

  List<String> years = [];
  List<Grade> grades = [];
  List<Staff> staff = [];
  bool isLoading = true;

  // Saisie instantanée: brouillons et debounce pour sauvegarde auto
  final Map<String, String> _gradeDrafts = {}; // key: studentId -> typed text
  final Map<String, Timer> _gradeDebouncers =
      {}; // key: studentId -> debounce timer

  final List<String> terms = ['Trimestre 1', 'Trimestre 2', 'Trimestre 3'];

  final DatabaseService _dbService = DatabaseService();

  final TextEditingController studentSearchController = TextEditingController();
  final TextEditingController reportSearchController = TextEditingController();
  final TextEditingController archiveSearchController = TextEditingController();

  List<String> get _periods => _periodMode == 'Trimestre'
      ? ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']
      : ['Semestre 1', 'Semestre 2'];

  // ===== Import dialog persistent state =====
  _ImportPreview? _importPreview;
  PlatformFile? _importPickedFile;
  bool _importValidating = false;
  String? _importError;
  int _importSuccessCount = 0;
  int _importErrorCount = 0;
  double _importProgress = 0.0;
  List<Map<String, dynamic>> _importRowResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    selectedTerm = _periods.first;
    academicYearNotifier.addListener(_onAcademicYearChanged);
    getCurrentAcademicYear().then((year) {
      setState(() {
        selectedAcademicYear = year;
      });
      _loadAllData();
    });
    // Initialiser le niveau scolaire depuis les préférences
    SharedPreferences.getInstance().then((prefs) {
      schoolLevelNotifier.value = prefs.getString('school_level') ?? '';
    });
  }

  void _onFilterChanged() async {
    setState(() {
      isLoading = true;
      _gradeDrafts.clear();
    });
    if (selectedClass != null) {
      String? classYear = selectedAcademicYear;
      if (classYear == null || classYear.isEmpty) {
        try {
          classYear = classes
              .firstWhere((c) => c.name == selectedClass)
              .academicYear;
        } catch (_) {
          classYear = null;
        }
      }
      if (classYear != null && classYear.isNotEmpty) {
        subjects = await _dbService.getCoursesForClass(
          selectedClass!,
          classYear,
        );
        // Charger les catégories pour permettre un affichage groupé
        categories = await _dbService.getCategories();
        if (subjects.isNotEmpty &&
            (selectedSubject == null ||
                !subjects.any((c) => c.name == selectedSubject))) {
          selectedSubject = subjects.first.name;
        }
      } else {
        subjects = [];
        selectedSubject = null;
      }
    } else {
      subjects = [];
      selectedSubject = null;
    }
    await _loadAllGradesForPeriod();
    setState(() => isLoading = false);
  }

  void _onAcademicYearChanged() {
    setState(() {
      selectedAcademicYear = academicYearNotifier.value;
      // Si la classe sélectionnée n'appartient pas à la nouvelle année, choisir une classe de cette année
      if (selectedClass != null) {
        final currentClass = classes.firstWhere(
          (c) => c.name == selectedClass,
          orElse: () => Class.empty(),
        );
        if (currentClass.academicYear != selectedAcademicYear) {
          final Class newYearClass = classes.firstWhere(
            (c) => c.academicYear == selectedAcademicYear,
            orElse: () => Class.empty(),
          );
          selectedClass = newYearClass.name.isNotEmpty
              ? newYearClass.name
              : null;
        }
      }
    });
    _onFilterChanged();
  }

  Future<void> _loadAllData() async {
    setState(() => isLoading = true);
    students = await _dbService.getStudents();
    classes = await _dbService.getClasses();
    staff = await _dbService.getStaff();
    years = classes.map((c) => c.academicYear).toSet().toList()..sort();
    // Sélections par défaut
    // Conserver l'année académique déjà définie (courante). Choisir une classe de cette année si possible
    if (classes.isNotEmpty) {
      if (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty) {
        final Class defaultClassForYear = classes.firstWhere(
          (c) => c.academicYear == selectedAcademicYear,
          orElse: () => classes.first,
        );
        selectedClass = defaultClassForYear.name;
      } else {
        selectedClass = classes.first.name;
        selectedAcademicYear = classes.first.academicYear;
      }
    } else {
      selectedClass = null;
    }
    selectedStudent = 'all';
    // Charger les matières de la classe sélectionnée
    if (selectedClass != null) {
      String? classYear = selectedAcademicYear;
      if (classYear == null || classYear.isEmpty) {
        try {
          classYear = classes
              .firstWhere((c) => c.name == selectedClass)
              .academicYear;
        } catch (_) {
          classYear = null;
        }
      }
      if (classYear != null && classYear.isNotEmpty) {
        subjects = await _dbService.getCoursesForClass(
          selectedClass!,
          classYear,
        );
      } else {
        subjects = [];
      }
    } else {
      subjects = [];
    }
    selectedSubject = subjects.isNotEmpty ? subjects.first.name : null;
    await _loadAllGradesForPeriod();
    setState(() => isLoading = false);
  }

  Future<void> _loadAllGradesForPeriod() async {
    if (selectedClass != null && selectedTerm != null) {
      String? targetYear =
          (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
          ? selectedAcademicYear
          : classes
                .firstWhere(
                  (c) => c.name == selectedClass,
                  orElse: () => Class.empty(),
                )
                .academicYear;
      if (targetYear != null && targetYear.isNotEmpty) {
        grades = await _dbService.getAllGradesForPeriod(
          className: selectedClass!,
          academicYear: targetYear,
          term: selectedTerm!,
        );
      } else {
        grades = [];
      }
    } else {
      grades = [];
    }
  }

  @override
  void dispose() {
    // Annuler les debounces actifs
    for (final t in _gradeDebouncers.values) {
      t.cancel();
    }
    academicYearNotifier.removeListener(_onAcademicYearChanged);
    _tabController.dispose();
    studentSearchController.dispose();
    reportSearchController.dispose();
    archiveSearchController.dispose();
    super.dispose();
  }

  Future<void> _saveOrUpdateGrade({
    required Student student,
    required double note,
    Grade? existing,
  }) async {
    if (selectedClass == null ||
        selectedAcademicYear == null ||
        selectedSubject == null ||
        selectedTerm == null)
      return;
    final course = subjects.firstWhere(
      (c) => c.name == selectedSubject,
      orElse: () => Course.empty(),
    );
    final newGrade = Grade(
      id: existing?.id,
      studentId: student.id,
      className: selectedClass!,
      academicYear: selectedAcademicYear!,
      subjectId: course.id,
      subject: selectedSubject!,
      term: selectedTerm!,
      value: note,
      label: existing?.label,
    );
    if (existing == null) {
      await _dbService.insertGrade(newGrade);
    } else {
      await _dbService.updateGrade(newGrade);
    }
    await _loadAllGradesForPeriod();
    // Nettoie le brouillon pour refléter la valeur réellement sauvegardée
    _gradeDrafts.remove(student.id);
    if (mounted) setState(() {});
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Color(0xFFF9FAFB),
      cardColor: Colors.white,
      dividerColor: Color(0xFFE5E7EB),
      shadowColor: Colors.black.withOpacity(0.1),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Color(0xFF111827),
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
        labelMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFF374151),
        ),
      ),
      iconTheme: IconThemeData(color: Color(0xFF4F46E5)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF4F46E5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      colorScheme: ColorScheme.light(
        primary: Color(0xFF4F46E5),
        secondary: Color(0xFF10B981),
        surface: Colors.white,
        onSurface: Color(0xFF1F2937),
        background: Color(0xFFF9FAFB),
        error: Color(0xFFEF4444),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Color(0xFF111827),
      cardColor: Color(0xFF1F2937),
      dividerColor: Color(0xFF374151),
      shadowColor: Colors.black.withOpacity(0.4),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFFF9FAFB),
        ),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        labelMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFFD1D5DB),
        ),
      ),
      iconTheme: IconThemeData(color: Color(0xFF818CF8)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF4F46E5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      colorScheme: ColorScheme.dark(
        primary: Color(0xFF6366F1),
        secondary: Color(0xFF34D399),
        surface: Color(0xFF1F2937),
        onSurface: Color(0xFFF9FAFB),
        background: Color(0xFF111827),
        error: Color(0xFFF87171),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDarkMode, bool isDesktop) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.grade,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des Notes',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Système intégré de notation et bulletins',
                        style: TextStyle(
                          fontSize: isDesktop ? 16 : 14,
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.7,
                          ),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  _buildQuickActions(),
                  SizedBox(width: 16),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      color: theme.iconTheme.color,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final theme = Theme.of(context);
    return Row(
      children: [
        _buildActionButton(
          Icons.upload_file,
          'Importer depuis Excel/CSV',
          theme.colorScheme.primary,
          () => _showImportDialog(),
        ),
        const SizedBox(width: 8),
        _buildActionButton(
          Icons.analytics,
          'Statistiques',
          theme.colorScheme.secondary,
          () => _showStatsDialog(),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  void _showStatsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatisticsModal(
          className: selectedClass,
          academicYear: selectedAcademicYear,
          term: selectedTerm,
          students: students,
          grades: grades,
          subjects: subjects,
          dbService: _dbService,
        );
      },
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Theme.of(context).colorScheme.onSurface,
        unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: 'Saisie Notes'),
          Tab(text: 'Bulletins'),
          Tab(text: 'Archives'),
        ],
      ),
    );
  }

  Widget _buildGradeInputTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(
            controller: studentSearchController,
            hintText: 'Rechercher un élève...',
            onChanged: (val) => setState(() => _studentSearchQuery = val),
          ),
          const SizedBox(height: 16),
          _buildSelectionSection(),
          const SizedBox(height: 24),
          _buildStudentGradesSection(),
          const SizedBox(height: 24),
          _buildGradeDistributionSection(),
        ],
      ),
    );
  }

  Widget _buildSelectionSection() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(color: theme.shadowColor, blurRadius: 10, spreadRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Mode : ', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _periodMode,
                items: ['Trimestre', 'Semestre']
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m, style: theme.textTheme.bodyMedium),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _periodMode = val!;
                    selectedTerm = _periods.first;
                    _onFilterChanged();
                  });
                },
                dropdownColor: theme.cardColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.tune, color: theme.iconTheme.color, size: 24),
              const SizedBox(width: 12),
              Text(
                'Sélection Matière et Période',
                style: theme.textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  'Matière',
                  selectedSubject ?? '',
                  subjects.map((c) => c.name).toList(),
                  (value) async {
                    setState(() {
                      selectedSubject = value!;
                      _gradeDrafts.clear();
                    });
                    await _loadAllGradesForPeriod();
                  },
                  Icons.book,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdown(
                  _periodMode == 'Trimestre' ? 'Trimestre' : 'Semestre',
                  selectedTerm ?? '',
                  _periods,
                  (value) async {
                    setState(() {
                      selectedTerm = value!;
                      _gradeDrafts.clear();
                    });
                    await _loadAllGradesForPeriod();
                  },
                  Icons.calendar_today,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedClass != null &&
              (selectedClass?.isNotEmpty ?? false) &&
              (selectedSubject?.isNotEmpty ?? false))
            FutureBuilder<Map<String, double>>(
              future: _dbService.getClassSubjectCoefficients(
                selectedClass!,
                (selectedAcademicYear != null &&
                        selectedAcademicYear!.isNotEmpty)
                    ? selectedAcademicYear!
                    : (classes
                              .firstWhere(
                                (c) => c.name == selectedClass,
                                orElse: () => Class.empty(),
                              )
                              .academicYear
                              .isNotEmpty
                          ? classes
                                .firstWhere(
                                  (c) => c.name == selectedClass,
                                  orElse: () => Class.empty(),
                                )
                                .academicYear
                          : academicYearNotifier.value),
              ),
              builder: (context, snap) {
                final coeff =
                    (snap.data ?? const <String, double>{})[selectedSubject!];
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.06),
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Coeff. matière (classe): ' +
                          (coeff != null ? coeff.toStringAsFixed(2) : '-'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: academicYearNotifier,
                  builder: (context, currentYear, _) {
                    final yearList = years.toSet().toList();
                    return DropdownButton<String?>(
                      value: selectedAcademicYear,
                      hint: Text(
                        'Année Académique',
                        style: theme.textTheme.bodyLarge,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Toutes les années'),
                        ),
                        DropdownMenuItem<String?>(
                          value: currentYear,
                          child: Text(
                            'Année courante ($currentYear)',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        ...yearList
                            .where((y) => y != currentYear)
                            .map(
                              (y) => DropdownMenuItem<String?>(
                                value: y,
                                child: Text(
                                  y,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ),
                      ],
                      onChanged: (String? value) {
                        setState(() {
                          selectedAcademicYear = value;
                        });
                        _onFilterChanged();
                      },
                      isExpanded: true,
                      dropdownColor: theme.cardColor,
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdown(
                  'Classe',
                  selectedClass ?? '',
                  classes
                      .where(
                        (c) =>
                            selectedAcademicYear == null ||
                            c.academicYear == selectedAcademicYear,
                      )
                      .map((c) => c.name)
                      .toList(),
                  (value) => setState(() => selectedClass = value!),
                  Icons.class_,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String? value,
    List<String> items,
    Function(String?) onChanged,
    IconData icon,
  ) {
    String? currentValue = (value != null && items.contains(value))
        ? value
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              isExpanded: true,
              icon: Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              dropdownColor: Theme.of(context).cardColor,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              items: items
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            color: Theme.of(context).iconTheme.color,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                onChanged(val);
                _onFilterChanged();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentGradesSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.people,
                    color: Theme.of(context).iconTheme.color,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Notes des Élèves',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showBulkGradeDialog(),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Saisie Rapide'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildClassAverage(),
          _buildStudentGradesList(),
        ],
      ),
    );
  }

  Widget _buildClassAverage() {
    if (isLoading || grades.isEmpty || selectedSubject == null)
      return const SizedBox.shrink();
    final theme = Theme.of(context);
    final classAvg = _calculateClassAverageForSubject(selectedSubject!);
    if (classAvg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.leaderboard, color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          Text(
            'Moyenne de la classe : ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            classAvg.toStringAsFixed(2),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentGradesList() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Filtrage dynamique des élèves
    List<Student> filteredStudents = students.where((s) {
      final classMatch = selectedClass == null || s.className == selectedClass;
      // Pour la saisie, si aucune année n'est sélectionnée, on retient l'année de l'élève
      final String effectiveYear =
          (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
          ? selectedAcademicYear!
          : s.academicYear;
      final yearMatch = s.academicYear == effectiveYear;
      final searchMatch =
          _studentSearchQuery.isEmpty ||
          s.name.toLowerCase().contains(_studentSearchQuery.toLowerCase());
      return classMatch && yearMatch && searchMatch;
    }).toList();
    if (filteredStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.group_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Aucun élève trouvé.',
              style: TextStyle(color: Colors.grey, fontSize: 18),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        ...filteredStudents
            .map((student) => _buildStudentGradeCard(student))
            .toList(),
      ],
    );
  }

  Widget _buildStudentGradeCard(Student student) {
    // Cherche la note existante pour cet élève et la sélection courante
    Grade? grade;
    final targetYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : student.academicYear;
    try {
      grade = grades.firstWhere(
        (g) =>
            g.studentId == student.id &&
            g.className == selectedClass &&
            g.academicYear == targetYear &&
            g.term == selectedTerm &&
            (selectedSubject == null || g.subject == selectedSubject),
      );
    } catch (_) {
      grade = null;
    }
    final initialText =
        _gradeDrafts[student.id] ??
        (grade != null ? grade.value.toString() : '');
    final controller = TextEditingController(text: initialText);

    // Moyenne de l'élève pour la matière sélectionnée (ici, une seule note possible par élève/matière/trimestre)
    final double? studentAvg = (_gradeDrafts.containsKey(student.id))
        ? double.tryParse(_gradeDrafts[student.id]!)
        : grade?.value;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.1),
            child: Text(
              student.firstName.isNotEmpty
                  ? student.firstName[0]
                  : '?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${student.firstName} ${student.lastName}'.trim(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Classe: ${student.className}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Container(
            width: 80,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                labelText: 'Note',
                labelStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surface.withOpacity(0.5),
              ),
              onChanged: (val) {
                // Met à jour l'affichage immédiat et lance une sauvegarde avec debounce
                setState(() => _gradeDrafts[student.id] = val);
                _gradeDebouncers[student.id]?.cancel();
                _gradeDebouncers[student
                    .id] = Timer(const Duration(milliseconds: 700), () async {
                  final note = double.tryParse(val);
                  if (note != null) {
                    if (selectedClass != null &&
                        selectedAcademicYear != null &&
                        selectedSubject != null &&
                        selectedTerm != null) {
                      await _saveOrUpdateGrade(
                        student: student,
                        note: note,
                        existing: grade,
                      );
                      if (mounted) {
                        showRootSnackBar(
                          SnackBar(
                            content: Text(
                              'Note enregistrée pour ${student.firstName} ${student.lastName}'.trim(),
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } else if (mounted) {
                      showRootSnackBar(
                        const SnackBar(
                          content: Text(
                            'Sélectionnez classe, matière, période et année avant de saisir.',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                });
              },
              onSubmitted: (val) async {
                final note = double.tryParse(val);
                if (note != null) {
                  if (selectedClass != null &&
                      selectedAcademicYear != null &&
                      selectedSubject != null &&
                      selectedTerm != null) {
                    await _saveOrUpdateGrade(
                      student: student,
                      note: note,
                      existing: grade,
                    );
                    if (mounted) {
                      showRootSnackBar(
                        SnackBar(
                          content: Text(
                            'Note enregistrée pour ${student.firstName} ${student.lastName}'.trim(),
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else if (mounted) {
                    showRootSnackBar(
                      const SnackBar(
                        content: Text(
                          'Sélectionnez classe, matière, période et année avant de saisir.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Icon(
                Icons.bar_chart,
                size: 18,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              Text(
                studentAvg != null ? studentAvg.toStringAsFixed(2) : '-',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.edit, color: Colors.orange),
            tooltip: 'Modifier toutes les notes',
            onPressed: () => _showEditStudentGradesDialog(student),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeDistributionSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart,
                color: Theme.of(context).iconTheme.color,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Répartition des Notes - ${selectedSubject ?? ""}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildGradeChart(),
        ],
      ),
    );
  }

  Widget _buildGradeChart() {
    final theme = Theme.of(context);
    // Construire une distribution en tenant compte des saisies en cours
    List<Grade> relevant;
    if (selectedSubject != null) {
      relevant = _effectiveGradesForSubject(selectedSubject!);
    } else {
      relevant = grades
          .where(
            (g) =>
                g.className == selectedClass &&
                g.academicYear == selectedAcademicYear &&
                g.term == selectedTerm &&
                (g.type == 'Devoir' || g.type == 'Composition') &&
                g.value != null &&
                g.value != 0 &&
                g.maxValue > 0,
          )
          .toList();
    }

    double to20(Grade g) => (g.value / g.maxValue) * 20.0;
    final scores = relevant.map(to20).toList();
    int count(bool Function(double) p) => scores.where(p).length;

    final labels = [
      '[0-5[',
      '[5-10[',
      '[10-12[',
      '[12-14[',
      '[14-16[',
      '[16-20]',
    ];
    final counts = [
      count((s) => s >= 0 && s < 5),
      count((s) => s >= 5 && s < 10),
      count((s) => s >= 10 && s < 12),
      count((s) => s >= 12 && s < 14),
      count((s) => s >= 14 && s < 16),
      count((s) => s >= 16 && s <= 20),
    ];
    final int total = scores.length;
    final colors = [
      Colors.red.shade400,
      Colors.orange.shade400,
      Colors.amber.shade600,
      Colors.lightGreen.shade500,
      Colors.green.shade600,
      Colors.teal.shade600,
    ];

    if (total == 0) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'Aucune note disponible pour afficher la répartition.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return Container(
      height: 220,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(labels.length, (index) {
          final ratio = counts[index] / total;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: colors[index],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 36,
                height: (ratio * 160).clamp(2, 160),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [colors[index], colors[index].withOpacity(0.6)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: colors[index].withOpacity(0.25),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(labels[index], style: theme.textTheme.bodyMedium),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildReportCardsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(
            controller: reportSearchController,
            hintText: 'Rechercher un élève (bulletin)...',
            onChanged: (val) => setState(() => _reportSearchQuery = val),
          ),
          const SizedBox(height: 16),
          _buildSelectionSection(),
          const SizedBox(height: 24),
          _buildReportCardSelection(),
          const SizedBox(height: 24),
          _buildReportCardPreview(),
        ],
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
        ),
        prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
        filled: true,
        fillColor: theme.cardColor,
        contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
      style: theme.textTheme.bodyLarge,
    );
  }

  Widget _buildReportCardSelection() {
    final filteredStudents = students.where((s) {
      final classMatch =
          selectedClass == null ||
          (s.className == selectedClass &&
              (selectedAcademicYear == null ||
                  selectedAcademicYear!.isEmpty ||
                  s.academicYear == selectedAcademicYear));
      // Logique Paiements: si une année est choisie => filtrer par année classe ET élève; sinon toutes les années
      final bool yearMatch =
          (selectedAcademicYear == null || selectedAcademicYear!.isEmpty)
          ? true
          : s.academicYear == selectedAcademicYear;
      final searchMatch =
          _reportSearchQuery.isEmpty ||
          s.name.toLowerCase().contains(_reportSearchQuery.toLowerCase());
      return classMatch && yearMatch && searchMatch;
    }).toList();

    final dropdownItems = [
      {'id': 'all', 'name': 'Sélectionner un élève'},
      ...filteredStudents.map((s) => {'id': s.id, 'name': s.name}),
    ];

    if (selectedStudent == null ||
        !dropdownItems.any((item) => item['id'] == selectedStudent)) {
      selectedStudent = dropdownItems.first['id'];
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment,
                color: Theme.of(context).iconTheme.color,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Génération & Exportation',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 20),
          DropdownButton<String>(
            value: selectedStudent,
            items: dropdownItems
                .map(
                  (item) => DropdownMenuItem(
                    value: item['id'],
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          color: Theme.of(context).iconTheme.color,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item['name']!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) async {
              setState(() => selectedStudent = val!);
              // Ajuster automatiquement classe/année/période pour l'aperçu si non définis
              final Student sel = students.firstWhere(
                (s) => s.id == val,
                orElse: () => Student.empty(),
              );
              String? effectiveClass = selectedClass;
              String? effectiveYear = selectedAcademicYear;
              if (effectiveClass == null || effectiveClass.isEmpty)
                effectiveClass = sel.className;
              if (effectiveYear == null || effectiveYear.isEmpty)
                effectiveYear = sel.academicYear;
              String? effTerm = selectedTerm;
              if (effTerm == null || effTerm.isEmpty) {
                effTerm = _periodMode == 'Trimestre'
                    ? 'Trimestre 1'
                    : 'Semestre 1';
              }
              setState(() {
                selectedClass = effectiveClass;
                selectedAcademicYear = effectiveYear;
                selectedTerm = effTerm;
              });
              await _loadAllGradesForPeriod();
            },
            isExpanded: true,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: (selectedClass == null || selectedClass!.isEmpty)
                    ? null
                    : () => _exportClassReportCards(),
                icon: const Icon(Icons.archive, size: 18),
                label: const Text('Exporter les bulletins de la classe (ZIP)'),
                style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                  backgroundColor: MaterialStateProperty.all(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReportCardPreview() {
    if (selectedStudent == null || selectedStudent == 'all') {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade100, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade100.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Sélectionnez un élève pour voir son bulletin.',
            style: TextStyle(color: Colors.blueGrey.shade700),
          ),
        ),
      );
    }
    final student = students.firstWhere(
      (s) => s.id == selectedStudent,
      orElse: () => Student.empty(),
    );
    if (student.id.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade100, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade100.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            'Aucun élève trouvé.',
            style: TextStyle(color: Colors.blueGrey.shade700),
          ),
        ),
      );
    }
    return FutureBuilder<SchoolInfo>(
      future: loadSchoolInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final info = snapshot.data!;
        // Ajout ValueListenableBuilder pour le niveau scolaire
        return ValueListenableBuilder<String>(
          valueListenable: schoolLevelNotifier,
          builder: (context, niveau, _) {
            final String effectiveYear =
                (selectedAcademicYear != null &&
                    selectedAcademicYear!.isNotEmpty)
                ? selectedAcademicYear!
                : student.academicYear;
            final schoolYear = effectiveYear;
            final periodLabel = _periodMode == 'Trimestre'
                ? 'Trimestre'
                : 'Semestre';
            final String effClass =
                (selectedClass == null || selectedClass!.isEmpty)
                ? student.className
                : selectedClass!;
            final String effTerm =
                (selectedTerm == null || selectedTerm!.isEmpty)
                ? (_periodMode == 'Trimestre' ? 'Trimestre 1' : 'Semestre 1')
                : selectedTerm!;
            final studentGrades = grades
                .where(
                  (g) =>
                      g.studentId == student.id &&
                      g.className == effClass &&
                      g.academicYear == effectiveYear &&
                      g.term == effTerm,
                )
                .toList();
            final subjectNames = subjects.map((c) => c.name).toList();
            final types = ['Devoir', 'Composition'];
            final Color mainColor = Colors.blue.shade800;
            final Color secondaryColor = Colors.blueGrey.shade700;
            final Color tableHeaderBg = Colors.blue.shade200;
            final Color tableHeaderText = Colors.white;
            final Color tableRowAlt = Colors.blue.shade50;
            final DateTime now = DateTime.now();
            final int nbEleves = students
                .where(
                  (s) =>
                      s.className == effClass &&
                      s.academicYear == effectiveYear,
                )
                .length;
            // Bloc élève : nom, prénom, sexe
            final String prenom = student.firstName;
            final String nom = student.lastName;
            final String sexe = student.gender;

            // Helpers pour l'en-tête administratif (aperçu)
            String fmtDate(String s) {
              if (s.isEmpty) return s;
              try {
                DateTime? d;
                if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
                  d = DateTime.tryParse(s);
                } else if (RegExp(r'^\d{2}/\d{2}/\d{4}').hasMatch(s)) {
                  final parts = s.split('/');
                  d = DateTime(
                    int.parse(parts[2]),
                    int.parse(parts[1]),
                    int.parse(parts[0]),
                  );
                }
                if (d != null) return DateFormat('dd/MM/yyyy').format(d);
              } catch (_) {}
              return s;
            }

            List<String> splitTwoLines(String input) {
              final s = input.trim().toUpperCase();
              if (s.isEmpty) return [];
              final words = s.split(RegExp(r'\s+'));
              if (words.length <= 1) return [s];
              final totalLen = s.length;
              final target = totalLen ~/ 2;
              int bestIdx = 1;
              int bestDist = totalLen;
              int running = 0;
              for (int i = 0; i < words.length - 1; i++) {
                running += words[i].length + 1;
                final dist = (running - target).abs();
                if (dist < bestDist) {
                  bestDist = dist;
                  bestIdx = i + 1;
                }
              }
              final first = words.sublist(0, bestIdx).join(' ');
              final second = words.sublist(bestIdx).join(' ');
              return [first, second];
            }

            double measureText(String text, TextStyle style) {
              final tp = TextPainter(
                text: TextSpan(text: text, style: style),
                maxLines: 1,
                textDirection: ui.TextDirection.ltr,
              );
              tp.layout();
              return tp.width;
            }

            final adminBold = TextStyle(
              fontWeight: FontWeight.bold,
              color: secondaryColor,
            );
            final parts = splitTwoLines(info.ministry ?? '');
            final double w1 = parts.isNotEmpty
                ? measureText(parts[0], adminBold)
                : 0;
            final double w2 = parts.length > 1
                ? measureText(parts[1], adminBold)
                : 0;
            final double maxW = (w1 > w2 ? w1 : w2);
            final double padFirst = (w2 > w1) ? ((w2 - w1) / 2) : 0;
            final double padSecond = (w1 > w2) ? ((w1 - w2) / 2) : 0;
            // --- Champs éditables pour appréciations et décision ---
            final Map<String, TextEditingController> appreciationControllers = {
              for (final subject in subjectNames)
                subject: TextEditingController(),
            };
            final Map<String, TextEditingController> moyClasseControllers = {
              for (final subject in subjectNames)
                subject: TextEditingController(),
            };
            final Map<String, TextEditingController> coeffControllers = {
              for (final subject in subjectNames)
                subject: TextEditingController(),
            };
            final Map<String, TextEditingController> profControllers = {
              for (final subject in subjectNames)
                subject: TextEditingController(),
            };
            final TextEditingController appreciationGeneraleController =
                TextEditingController();
            final TextEditingController decisionController =
                TextEditingController();
            final TextEditingController recommandationsController =
                TextEditingController();
            final TextEditingController forcesController =
                TextEditingController();
            final TextEditingController pointsDevelopperController =
                TextEditingController();
            final TextEditingController conduiteController =
                TextEditingController();
            final TextEditingController absJustifieesController =
                TextEditingController();
            final TextEditingController absInjustifieesController =
                TextEditingController();
            final TextEditingController retardsController =
                TextEditingController();
            final TextEditingController presencePercentController =
                TextEditingController();
            // Champs éditables pour l'établissement (téléphone, mail, site web)
            final TextEditingController telEtabController =
                TextEditingController();
            final TextEditingController mailEtabController =
                TextEditingController();
            final TextEditingController webEtabController =
                TextEditingController();
            final TextEditingController faitAController =
                TextEditingController();
            final TextEditingController leDateController =
                TextEditingController();
            final TextEditingController sanctionsController =
                TextEditingController();

            // Charger les valeurs sauvegardées pour les champs établissement
            SharedPreferences.getInstance().then((prefs) {
              telEtabController.text = prefs.getString('school_phone') ?? '';
              mailEtabController.text = prefs.getString('school_email') ?? '';
              webEtabController.text = prefs.getString('school_website') ?? '';
            });
            // Préremplir Fait à (adresse de l'établissement) et date (aujourd'hui) si vides
            loadSchoolInfo().then((info) {
              if (faitAController.text.trim().isEmpty) {
                faitAController.text = info.address;
              }
              if (leDateController.text.trim().isEmpty) {
                leDateController.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
              }
            });
            // Fonction de sauvegarde automatique
            void saveEtabField(String key, String value) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(key, value);
            }

            // --- Persistance appréciations/professeurs/moyenne_classe ---
            Future<void> loadSubjectAppreciations() async {
              for (final subject in subjectNames) {
                final data = await _dbService.getSubjectAppreciation(
                  studentId: student.id,
                  className: selectedClass ?? '',
                  academicYear: effectiveYear,
                  subject: subject,
                  term: selectedTerm ?? '',
                );
                if (data != null) {
                  profControllers[subject]?.text = data['professeur'] ?? '';
                  appreciationControllers[subject]?.text =
                      data['appreciation'] ?? '';
                  moyClasseControllers[subject]?.text =
                      data['moyenne_classe'] ?? '';
                  final coeffVal = (data['coefficient'] as num?)?.toDouble();
                  coeffControllers[subject]?.text = coeffVal != null
                      ? coeffVal.toString()
                      : '';
                }
              }
            }

            // Charger à l'ouverture
            loadSubjectAppreciations();
            // Fonction de sauvegarde automatique
            void saveSubjectAppreciation(String subject) async {
              await _dbService.insertOrUpdateSubjectAppreciation(
                studentId: student.id,
                className: selectedClass ?? '',
                academicYear: effectiveYear,
                subject: subject,
                term: selectedTerm ?? '',
                professeur: profControllers[subject]?.text,
                appreciation: appreciationControllers[subject]?.text,
                moyenneClasse: moyClasseControllers[subject]?.text,
                coefficient: double.tryParse(
                  (coeffControllers[subject]?.text ?? '').replaceAll(',', '.'),
                ),
              );
            }

            // Sauvegarde automatique en temps réel sur changement
            for (final subject in subjectNames) {
              profControllers[subject]?.addListener(
                () => saveSubjectAppreciation(subject),
              );
              appreciationControllers[subject]?.addListener(
                () => saveSubjectAppreciation(subject),
              );
              moyClasseControllers[subject]?.addListener(
                () => saveSubjectAppreciation(subject),
              );
              coeffControllers[subject]?.addListener(
                () => saveSubjectAppreciation(subject),
              );
            }
            // --- Moyennes par période ---
            final List<String> allTerms = _periodMode == 'Trimestre'
                ? ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']
                : ['Semestre 1', 'Semestre 2'];
            final List<double?> moyennesParPeriode = allTerms.map((term) {
              final termGrades = grades
                  .where(
                    (g) =>
                        g.studentId == student.id &&
                        g.className == selectedClass &&
                        g.academicYear == effectiveYear &&
                        g.term == term &&
                        (g.type == 'Devoir' || g.type == 'Composition') &&
                        g.value != null &&
                        g.value != 0,
                  )
                  .toList();
              double sNotes = 0.0;
              double sCoeffs = 0.0;
              for (final g in termGrades) {
                if (g.maxValue > 0 && g.coefficient > 0) {
                  sNotes += ((g.value / g.maxValue) * 20) * g.coefficient;
                  sCoeffs += g.coefficient;
                }
              }
              return (sCoeffs > 0) ? (sNotes / sCoeffs) : null;
            }).toList();
            // Calcul de la moyenne générale pondérée (devoirs + compos)
            double sommeNotes = 0.0;
            double sommeCoefficients = 0.0;
            for (final g in studentGrades.where(
              (g) =>
                  (g.type == 'Devoir' || g.type == 'Composition') &&
                  g.value != null &&
                  g.value != 0,
            )) {
              if (g.maxValue > 0 && g.coefficient > 0) {
                sommeNotes += ((g.value / g.maxValue) * 20) * g.coefficient;
                sommeCoefficients += g.coefficient;
              }
            }
            final moyenneGenerale = (sommeCoefficients > 0)
                ? (sommeNotes / sommeCoefficients)
                : 0.0;
            // Calcul du rang
            final classStudentIds = students
                .where((s) {
                  if (s.className != effClass) return false;
                  final classObj = classes.firstWhere(
                    (c) => c.name == s.className,
                    orElse: () => Class.empty(),
                  );
                  // Align with effectiveYear so single exports mirror ZIP exports
                  return classObj.academicYear == effectiveYear &&
                      s.academicYear == effectiveYear;
                })
                .map((s) => s.id)
                .toList();
            final List<double> allMoyennes = classStudentIds.map((sid) {
              final sg = grades
                  .where(
                    (g) =>
                        g.studentId == sid &&
                        g.className == effClass &&
                        g.academicYear == effectiveYear &&
                        g.term == effTerm &&
                        (g.type == 'Devoir' || g.type == 'Composition') &&
                        g.value != null &&
                        g.value != 0,
                  )
                  .toList();
              double sNotes = 0.0;
              double sCoeffs = 0.0;
              for (final g in sg) {
                if (g.maxValue > 0 && g.coefficient > 0) {
                  sNotes += ((g.value / g.maxValue) * 20) * g.coefficient;
                  sCoeffs += g.coefficient;
                }
              }
              return (sCoeffs > 0) ? (sNotes / sCoeffs) : 0.0;
            }).toList();
            allMoyennes.sort((a, b) => b.compareTo(a));
            final rang =
                allMoyennes.indexWhere(
                  (m) => (m - moyenneGenerale).abs() < 0.001,
                ) +
                1;

            final double? moyenneGeneraleDeLaClasse = allMoyennes.isNotEmpty
                ? allMoyennes.reduce((a, b) => a + b) / allMoyennes.length
                : null;
            final double? moyenneLaPlusForte = allMoyennes.isNotEmpty
                ? allMoyennes.reduce((a, b) => a > b ? a : b)
                : null;
            final double? moyenneLaPlusFaible = allMoyennes.isNotEmpty
                ? allMoyennes.reduce((a, b) => a < b ? a : b)
                : null;

            // Calcul de la moyenne annuelle
            double? moyenneAnnuelle;
            final allGradesForYear = grades
                .where(
                  (g) =>
                      g.studentId == student.id &&
                      g.className == selectedClass &&
                      g.academicYear == selectedAcademicYear &&
                      (g.type == 'Devoir' || g.type == 'Composition') &&
                      g.value != null &&
                      g.value != 0,
                )
                .toList();

            if (allGradesForYear.isNotEmpty) {
              double totalAnnualNotes = 0.0;
              double totalAnnualCoeffs = 0.0;
              for (final g in allGradesForYear) {
                if (g.maxValue > 0 && g.coefficient > 0) {
                  totalAnnualNotes +=
                      ((g.value / g.maxValue) * 20) * g.coefficient;
                  totalAnnualCoeffs += g.coefficient;
                }
              }
              moyenneAnnuelle = totalAnnualCoeffs > 0
                  ? totalAnnualNotes / totalAnnualCoeffs
                  : null;
            }

            // Mention
            String mention;
            if (moyenneGenerale >= 18) {
              mention = 'EXCELLENT';
            } else if (moyenneGenerale >= 16) {
              mention = 'TRÈS BIEN';
            } else if (moyenneGenerale >= 14) {
              mention = 'BIEN';
            } else if (moyenneGenerale >= 12) {
              mention = 'ASSEZ BIEN';
            } else if (moyenneGenerale >= 10) {
              mention = 'PASSABLE';
            } else {
              mention = 'INSUFFISANT';
            }

            // Décision automatique du conseil de classe basée sur la moyenne annuelle
            // Ne s'affiche qu'en fin d'année (Trimestre 3 ou Semestre 2)
            String? decisionAutomatique;
            final bool isEndOfYear =
                selectedTerm == 'Trimestre 3' || selectedTerm == 'Semestre 2';

            if (isEndOfYear) {
              if (moyenneAnnuelle != null) {
                if (moyenneAnnuelle >= 16) {
                  decisionAutomatique =
                      'Admis en classe supérieure avec félicitations';
                } else if (moyenneAnnuelle >= 14) {
                  decisionAutomatique =
                      'Admis en classe supérieure avec encouragements';
                } else if (moyenneAnnuelle >= 12) {
                  decisionAutomatique = 'Admis en classe supérieure';
                } else if (moyenneAnnuelle >= 10) {
                  decisionAutomatique =
                      'Admis en classe supérieure avec avertissement';
                } else if (moyenneAnnuelle >= 8) {
                  decisionAutomatique =
                      'Admis en classe supérieure sous conditions';
                } else {
                  decisionAutomatique = 'Redouble la classe';
                }
              } else {
                // Fallback sur la moyenne générale si pas de moyenne annuelle
                if (moyenneGenerale >= 16) {
                  decisionAutomatique =
                      'Admis en classe supérieure avec félicitations';
                } else if (moyenneGenerale >= 14) {
                  decisionAutomatique =
                      'Admis en classe supérieure avec encouragements';
                } else if (moyenneGenerale >= 12) {
                  decisionAutomatique = 'Admis en classe supérieure';
                } else if (moyenneGenerale >= 10) {
                  decisionAutomatique =
                      'Admis en classe supérieure avec avertissement';
                } else if (moyenneGenerale >= 8) {
                  decisionAutomatique =
                      'Admis en classe supérieure sous conditions';
                } else {
                  decisionAutomatique = 'Redouble la classe';
                }
              }
            }
            // --- Chargement initial et sauvegarde automatique de la synthèse ---
            final String effectiveYearForKey =
                (selectedAcademicYear != null &&
                    selectedAcademicYear!.isNotEmpty)
                ? selectedAcademicYear!
                : academicYearNotifier.value;
            Future<void> loadReportCardSynthese() async {
              final row = await _dbService.getReportCard(
                studentId: student.id,
                className: selectedClass ?? '',
                academicYear: effectiveYearForKey,
                term: selectedTerm ?? '',
              );
              if (row != null) {
                appreciationGeneraleController.text =
                    row['appreciation_generale'] ?? '';
                // Pré-remplir la décision automatique si elle est vide ET qu'on est en fin d'année
                final decisionExistante = row['decision'] ?? '';
                if (decisionExistante.trim().isEmpty &&
                    isEndOfYear &&
                    decisionAutomatique != null) {
                  decisionController.text = decisionAutomatique;
                } else {
                  decisionController.text = decisionExistante;
                }
                recommandationsController.text = row['recommandations'] ?? '';
                forcesController.text = row['forces'] ?? '';
                pointsDevelopperController.text =
                    row['points_a_developper'] ?? '';
                sanctionsController.text = row['sanctions'] ?? '';
                absJustifieesController.text =
                    (row['attendance_justifiee'] ?? 0).toString();
                absInjustifieesController.text =
                    (row['attendance_injustifiee'] ?? 0).toString();
                retardsController.text = (row['retards'] ?? 0).toString();
                presencePercentController.text =
                    (row['presence_percent'] ?? 0.0).toString();
                conduiteController.text = row['conduite'] ?? '';
                faitAController.text = row['fait_a'] ?? '';
                leDateController.text = row['le_date'] ?? '';
              } else {
                // Si aucune donnée existante, pré-remplir avec la décision automatique seulement en fin d'année
                if (isEndOfYear && decisionAutomatique != null) {
                  decisionController.text = decisionAutomatique;
                }
              }
            }

            // Charger la synthèse depuis la base
            loadReportCardSynthese();

            Future<void> saveSynthese() async {
              final String effectiveYear =
                  (selectedAcademicYear != null &&
                      selectedAcademicYear!.isNotEmpty)
                  ? selectedAcademicYear!
                  : academicYearNotifier.value;
              debugPrint(
                '[GradesPage] saveSynthese -> student=${student.id} class=${selectedClass ?? ''} year=$effectiveYear term=${selectedTerm ?? ''}',
              );
              debugPrint(
                '[GradesPage] saveSynthese fields: apprGen="' +
                    appreciationGeneraleController.text +
                    '" decision="' +
                    decisionController.text +
                    '" recos="' +
                    recommandationsController.text +
                    '" forces="' +
                    forcesController.text +
                    '" points="' +
                    pointsDevelopperController.text +
                    '" sanctions="' +
                    sanctionsController.text +
                    '" absJ=' +
                    absJustifieesController.text +
                    ' absIJ=' +
                    absInjustifieesController.text +
                    ' retards=' +
                    retardsController.text +
                    ' presence=' +
                    presencePercentController.text +
                    ' conduite="' +
                    conduiteController.text +
                    '" faitA="' +
                    faitAController.text +
                    '" leDate="' +
                    leDateController.text +
                    '"',
              );
              await _dbService.insertOrUpdateReportCard(
                studentId: student.id,
                className: selectedClass ?? '',
                academicYear: effectiveYear,
                term: selectedTerm ?? '',
                appreciationGenerale: appreciationGeneraleController.text,
                decision: decisionController.text,
                recommandations: recommandationsController.text,
                forces: forcesController.text,
                pointsADevelopper: pointsDevelopperController.text,
                faitA: faitAController.text,
                leDate: leDateController.text,
                moyenneGenerale: moyenneGenerale,
                rang: rang,
                nbEleves: nbEleves,
                mention: mention,
                moyennesParPeriode: moyennesParPeriode.toString(),
                allTerms: allTerms.toString(),
                moyenneGeneraleDeLaClasse: moyenneGeneraleDeLaClasse,
                moyenneLaPlusForte: moyenneLaPlusForte,
                moyenneLaPlusFaible: moyenneLaPlusFaible,
                moyenneAnnuelle: moyenneAnnuelle,
                sanctions: sanctionsController.text,
                attendanceJustifiee: int.tryParse(absJustifieesController.text),
                attendanceInjustifiee: int.tryParse(
                  absInjustifieesController.text,
                ),
                retards: int.tryParse(retardsController.text),
                presencePercent: double.tryParse(
                  presencePercentController.text,
                ),
                conduite: conduiteController.text,
              );
            }

            // Sauvegarde automatique sur changement de chaque champ texte
            for (final ctrl in [
              appreciationGeneraleController,
              decisionController,
              recommandationsController,
              forcesController,
              pointsDevelopperController,
              sanctionsController,
              absJustifieesController,
              absInjustifieesController,
              retardsController,
              presencePercentController,
              conduiteController,
              faitAController,
              leDateController,
            ]) {
              ctrl.addListener(() {
                // Sauvegarder immédiatement chaque champ saisi manuellement
                saveSynthese();
              });
            }

            // Auto-archivage non sollicité au rendu
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final String effectiveYear =
                  (selectedAcademicYear != null &&
                      selectedAcademicYear!.isNotEmpty)
                  ? selectedAcademicYear!
                  : academicYearNotifier.value;
              final synthese = {
                'appreciation_generale': appreciationGeneraleController.text,
                'decision': decisionController.text,
                'recommandations': recommandationsController.text,
                'forces': forcesController.text,
                'points_a_developper': pointsDevelopperController.text,
                'fait_a': faitAController.text,
                'le_date': leDateController.text,
                'moyenne_generale': moyenneGenerale,
                'rang': rang,
                'nb_eleves': nbEleves,
                'mention': mention,
                'moyennes_par_periode': moyennesParPeriode.toString(),
                'all_terms': allTerms.toString(),
                'moyenne_annuelle': moyenneAnnuelle,
                'sanctions': sanctionsController.text,
                'attendance_justifiee':
                    int.tryParse(absJustifieesController.text) ?? 0,
                'attendance_injustifiee':
                    int.tryParse(absInjustifieesController.text) ?? 0,
                'retards': int.tryParse(retardsController.text) ?? 0,
                'presence_percent':
                    double.tryParse(presencePercentController.text) ?? 0.0,
                'conduite': conduiteController.text,
                'moyenne_generale_classe': moyenneGeneraleDeLaClasse,
                'moyenne_la_plus_forte': moyenneLaPlusForte,
                'moyenne_la_plus_faible': moyenneLaPlusFaible,
              };

              await _dbService.insertOrUpdateReportCard(
                studentId: student.id,
                className: selectedClass ?? '',
                academicYear: effectiveYear,
                term: selectedTerm ?? '',
                appreciationGenerale: appreciationGeneraleController.text,
                decision: decisionController.text,
                recommandations: recommandationsController.text,
                forces: forcesController.text,
                pointsADevelopper: pointsDevelopperController.text,
                faitA: faitAController.text,
                leDate: leDateController.text,
                moyenneGenerale: moyenneGenerale,
                rang: rang,
                nbEleves: nbEleves,
                mention: mention,
                moyennesParPeriode: moyennesParPeriode.toString(),
                allTerms: allTerms.toString(),
                moyenneGeneraleDeLaClasse: moyenneGeneraleDeLaClasse,
                moyenneLaPlusForte: moyenneLaPlusForte,
                moyenneLaPlusFaible: moyenneLaPlusFaible,
                moyenneAnnuelle: moyenneAnnuelle,
                sanctions: sanctionsController.text,
                attendanceJustifiee: int.tryParse(absJustifieesController.text),
                attendanceInjustifiee: int.tryParse(
                  absInjustifieesController.text,
                ),
                retards: int.tryParse(retardsController.text),
                presencePercent: double.tryParse(
                  presencePercentController.text,
                ),
                conduite: conduiteController.text,
              );

              final professeurs = <String, String>{
                for (final s in subjectNames)
                  s: (profControllers[s]?.text ?? '-').trim().isNotEmpty
                      ? profControllers[s]!.text
                      : '-',
              };
              final appreciations = <String, String>{
                for (final s in subjectNames)
                  s: (appreciationControllers[s]?.text ?? '-').trim().isNotEmpty
                      ? appreciationControllers[s]!.text
                      : '-',
              };
              final moyennesClasse = <String, String>{
                for (final s in subjectNames)
                  s: (moyClasseControllers[s]?.text ?? '-').trim().isNotEmpty
                      ? moyClasseControllers[s]!.text
                      : '-',
              };

              await _dbService.archiveSingleReportCard(
                studentId: student.id,
                className: selectedClass ?? '',
                academicYear: selectedAcademicYear ?? '',
                term: selectedTerm ?? '',
                grades: studentGrades,
                professeurs: professeurs,
                appreciations: appreciations,
                moyennesClasse: moyennesClasse,
                synthese: synthese,
              );
            });
            return Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.blue.shade200, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade100.withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // En-tête administratif (aperçu) : Ministère / République / Devise / Inspection / Direction
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child:
                                (info.ministry != null &&
                                    info.ministry!.trim().isNotEmpty)
                                ? (maxW > 0
                                      ? SizedBox(
                                          width: maxW,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (parts.isNotEmpty)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                    left: padFirst,
                                                  ),
                                                  child: Text(
                                                    parts[0],
                                                    style: adminBold,
                                                  ),
                                                ),
                                              if (parts.length > 1)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                    left: padSecond,
                                                  ),
                                                  child: Text(
                                                    parts[1],
                                                    style: adminBold,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        )
                                      : Text(
                                          info.ministry!.toUpperCase(),
                                          style: adminBold,
                                        ))
                                : const SizedBox.shrink(),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  (info.republic ?? 'RÉPUBLIQUE').toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: secondaryColor,
                                  ),
                                ),
                                if ((info.republicMotto ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      info.republicMotto!,
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: secondaryColor,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: (info.inspection ?? '').trim().isNotEmpty
                                ? Text(
                                    'Inspection: ${info.inspection}',
                                    style: TextStyle(color: secondaryColor),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child:
                                  (info.educationDirection ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? Text(
                                      "Direction de l'enseignement: ${info.educationDirection}",
                                      style: TextStyle(color: secondaryColor),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                      if ((student.photoPath ?? '').trim().isNotEmpty &&
                          File(student.photoPath!).existsSync())
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.file(
                                File(student.photoPath!),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // En-tête établissement amélioré
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (info.logoPath != null &&
                          File(info.logoPath!).existsSync())
                        Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: Image.file(File(info.logoPath!), height: 80),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 30,
                                color: mainColor,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Adresse + année (sous le nom)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    info.address,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: secondaryColor,
                                    ),
                                  ),
                                ),
                                Transform.translate(
                                  offset: const Offset(-8, 0),
                                  child: Text(
                                    'Année académique : $schoolYear',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: secondaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // if (info.director.isNotEmpty) Text('Directeur : ${info.director}', style: TextStyle(fontSize: 15, color: secondaryColor)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: telEtabController,
                                    enabled: false,
                                    decoration: InputDecoration(
                                      hintText: 'Téléphone',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: secondaryColor,
                                    ),
                                    onChanged: (val) {},
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: mailEtabController,
                                    enabled: false,
                                    decoration: InputDecoration(
                                      hintText: 'Email',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: secondaryColor,
                                    ),
                                    onChanged: (val) {},
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: webEtabController,
                                    enabled: false,
                                    decoration: InputDecoration(
                                      hintText: 'Site web',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: secondaryColor,
                                    ),
                                    onChanged: (val) {},
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'BULLETIN SCOLAIRE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: mainColor,
                            letterSpacing: 2,
                          ),
                        ),
                        if ((info.motto ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            info.motto!,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: mainColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Bloc élève (nom, prénom, sexe, date de naissance, statut)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Nom : $nom',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: mainColor,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Prénom : $prenom',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: mainColor,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Sexe : $sexe',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: mainColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Date de naissance : ${fmtDate(student.dateOfBirth)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: mainColor,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Statut : ${student.status}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: mainColor,
                                ),
                              ),
                            ),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.class_, color: mainColor),
                        const SizedBox(width: 8),
                        Text(
                          'Classe : ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: mainColor,
                          ),
                        ),
                        Text(
                          student.className,
                          style: TextStyle(color: secondaryColor),
                        ),
                        const Spacer(),
                        Text(
                          'Effectif : ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: mainColor,
                          ),
                        ),
                        Text(
                          '$nbEleves',
                          style: TextStyle(color: secondaryColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Tableau matières (groupé par catégories si disponibles)
                  ...() {
                    // Regrouper les matières par catégorie
                    final Map<String?, List<String>> grouped = {};
                    for (final c in subjects) {
                      grouped.putIfAbsent(c.categoryId, () => []).add(c.name);
                    }
                    final bool hasCategories = grouped.keys.any(
                      (k) => k != null,
                    );

                    Widget buildTableForSubjects(
                      List<String> names, {
                      bool showTotals = true,
                    }) {
                      // Compact styles for preview to reduce height
                      const cellTextStyle = TextStyle(fontSize: 12);
                      const headerTextStyle = TextStyle(
                        fontWeight: FontWeight.bold,
                      );

                      // Charger coefficients de matière définis au niveau de la classe
                      final Map<String, double> classWeights = {};
                      String _splitHeaderWords(String s) =>
                          s.trim().split(RegExp(r'\s+')).join('\n');
                      // Ce FutureBuilder garantit que les coefficients sont récupérés
                      return FutureBuilder<Map<String, double>>(
                        future: _dbService.getClassSubjectCoefficients(
                          selectedClass ?? student.className,
                          selectedAcademicYear ?? effectiveYear,
                        ),
                        builder: (context, wSnapshot) {
                          final weights = wSnapshot.data ?? {};
                          return Table(
                            border: TableBorder.all(
                              color: Colors.blue.shade100,
                            ),
                            columnWidths: const {
                              0: FlexColumnWidth(2),
                              1: FlexColumnWidth(2),
                              2: FlexColumnWidth(),
                              3: FlexColumnWidth(),
                              4: FlexColumnWidth(),
                              5: FlexColumnWidth(), // Coeff.
                              6: FlexColumnWidth(1.2), // Moyenne Generale
                              7: FlexColumnWidth(1.4), // Moyenne Generale Coef
                              8: FlexColumnWidth(1.2), // Moy. classe
                              9: FlexColumnWidth(2), // Appréciation
                            },
                            children: [
                              TableRow(
                                decoration: BoxDecoration(color: tableHeaderBg),
                                children: [
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'Matière',
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'Professeur(s)',
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'Sur',
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'Devoir',
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'Composition',
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'Coeff.',
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      _splitHeaderWords('Moyenne Generale'),
                                      textAlign: TextAlign.center,
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      _splitHeaderWords(
                                        'Moyenne Generale Coef',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'Moy. classe',
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'Appréciation prof.',
                                      style: headerTextStyle.copyWith(
                                        color: tableHeaderText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              ...names.map((subject) {
                                // Ensure each row has fixed intrinsic height to avoid border row offset assertions
                                final subjectGrades = studentGrades
                                    .where((g) => g.subject == subject)
                                    .toList();
                                final devoirs = subjectGrades
                                    .where((g) => g.type == 'Devoir')
                                    .toList();
                                final compositions = subjectGrades
                                    .where((g) => g.type == 'Composition')
                                    .toList();
                                final devoirNote = devoirs.isNotEmpty
                                    ? devoirs.first.value.toStringAsFixed(2)
                                    : '-';
                                final devoirSur = devoirs.isNotEmpty
                                    ? devoirs.first.maxValue.toStringAsFixed(2)
                                    : '-';
                                final compoNote = compositions.isNotEmpty
                                    ? compositions.first.value.toStringAsFixed(
                                        2,
                                      )
                                    : '-';
                                final compoSur = compositions.isNotEmpty
                                    ? compositions.first.maxValue
                                          .toStringAsFixed(2)
                                    : '-';
                                double total = 0;
                                double totalCoeff = 0;
                                for (final g in [...devoirs, ...compositions]) {
                                  if (g.maxValue > 0 && g.coefficient > 0) {
                                    total +=
                                        ((g.value / g.maxValue) * 20) *
                                        g.coefficient;
                                    totalCoeff += g.coefficient;
                                  }
                                }
                                final moyenneMatiere = (totalCoeff > 0)
                                    ? (total / totalCoeff)
                                    : 0.0;

                                // Trouver le professeur et pré-remplir le champ
                                final classInfo = classes.firstWhere(
                                  (c) => c.name == selectedClass,
                                  orElse: () => Class.empty(),
                                );
                                final titulaire = classInfo.titulaire ?? '-';
                                final course = subjects.firstWhere(
                                  (c) => c.name == subject,
                                  orElse: () => Course.empty(),
                                );
                                bool teachesSubject(Staff s) {
                                  final crs = s.courses;
                                  final cls = s.classes;
                                  final matchCourse =
                                      crs.contains(course.id) ||
                                      crs.any(
                                        (x) =>
                                            x.toLowerCase() ==
                                            subject.toLowerCase(),
                                      );
                                  final matchClass = cls.contains(
                                    selectedClass,
                                  );
                                  return matchCourse && matchClass;
                                }

                                final teacher = staff.firstWhere(
                                  (s) => teachesSubject(s),
                                  orElse: () => Staff.empty(),
                                );
                                final profName = teacher.id.isNotEmpty
                                    ? teacher.name
                                    : titulaire;
                                if ((profControllers[subject]?.text ?? '')
                                    .trim()
                                    .isEmpty) {
                                  profControllers[subject]?.text = profName;
                                }

                                final classSubjectAverage =
                                    _calculateClassAverageForSubject(subject);
                                if ((moyClasseControllers[subject]?.text ?? '')
                                    .trim()
                                    .isEmpty) {
                                  moyClasseControllers[subject]?.text =
                                      classSubjectAverage != null
                                      ? classSubjectAverage.toStringAsFixed(2)
                                      : '-';
                                }
                                final double subjectWeight =
                                    (weights[subject] ?? totalCoeff);
                                final double moyenneGeneraleCoef =
                                    moyenneMatiere * subjectWeight;
                                // Appréciation par défaut selon la moyenne de la matière (modifiable ensuite)
                                if ((appreciationControllers[subject]?.text ??
                                        '')
                                    .trim()
                                    .isEmpty) {
                                  String appr;
                                  if (moyenneMatiere >= 18) {
                                    appr = 'Excellent travail';
                                  } else if (moyenneMatiere >= 16) {
                                    appr = 'Très bon travail';
                                  } else if (moyenneMatiere >= 14) {
                                    appr = 'Bon travail';
                                  } else if (moyenneMatiere >= 12) {
                                    appr = 'Travail satisfaisant';
                                  } else if (moyenneMatiere >= 10) {
                                    appr = 'Travail passable';
                                  } else {
                                    appr = 'Travail insuffisant';
                                  }
                                  appreciationControllers[subject]?.text = appr;
                                }
                                // Auto-save defaults the first time they are set
                                final key =
                                    '${student.id}::$subject::${selectedClass ?? ''}::${selectedAcademicYear ?? ''}::${selectedTerm ?? ''}';
                                if (!_initialSubjectAppSave.contains(key)) {
                                  _initialSubjectAppSave.add(key);
                                  saveSubjectAppreciation(subject);
                                }

                                return TableRow(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                  ),
                                  children: [
                                    SizedBox(
                                      height: 44,
                                      child: Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Text(
                                          subject,
                                          style: TextStyle(
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 44,
                                      child: Padding(
                                        padding: EdgeInsets.all(6),
                                        child: TextField(
                                          controller: profControllers[subject],
                                          enabled: false,
                                          decoration: InputDecoration(
                                            hintText: 'Professeur',
                                            hintStyle: TextStyle(
                                              color: secondaryColor,
                                            ),
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Colors.blueGrey.shade200,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Colors.blueGrey.shade400,
                                                width: 2,
                                              ),
                                            ),
                                            fillColor: Colors.blueGrey.shade50,
                                            filled: true,
                                          ),
                                          style: TextStyle(
                                            color: secondaryColor,
                                            fontSize: 13,
                                          ),
                                          onChanged: (_) {},
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 44,
                                      child: Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Text(
                                          devoirSur != '-'
                                              ? devoirSur
                                              : compoSur,
                                          style: TextStyle(
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 44,
                                      child: Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Text(
                                          devoirNote,
                                          style: TextStyle(
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 36,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          compoNote,
                                          style: cellTextStyle.copyWith(
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 36,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          subjectWeight > 0
                                              ? subjectWeight.toStringAsFixed(2)
                                              : '-',
                                          style: cellTextStyle.copyWith(
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 36,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          moyenneMatiere.toStringAsFixed(2),
                                          style: cellTextStyle.copyWith(
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 36,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          moyenneGeneraleCoef.toStringAsFixed(
                                            2,
                                          ),
                                          style: cellTextStyle.copyWith(
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 36,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: TextField(
                                          controller:
                                              moyClasseControllers[subject],
                                          enabled: false,
                                          decoration: InputDecoration(
                                            hintText: 'Moy. classe',
                                            hintStyle: TextStyle(
                                              color: secondaryColor,
                                            ),
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Colors.blueGrey.shade200,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Colors.blueGrey.shade400,
                                                width: 2,
                                              ),
                                            ),
                                            fillColor: Colors.blueGrey.shade50,
                                            filled: true,
                                          ),
                                          style: TextStyle(
                                            color: secondaryColor,
                                            fontSize: 12,
                                          ),
                                          onChanged: (_) {},
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 44,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: TextField(
                                          controller:
                                              appreciationControllers[subject],
                                          enabled: true,
                                          decoration: InputDecoration(
                                            hintText: 'Appréciation',
                                            hintStyle: TextStyle(
                                              color: secondaryColor,
                                            ),
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Colors.blueGrey.shade200,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Colors.blueGrey.shade400,
                                                width: 2,
                                              ),
                                            ),
                                            fillColor: Colors.blueGrey.shade50,
                                            filled: true,
                                          ),
                                          maxLines: 2,
                                          style: TextStyle(
                                            color: secondaryColor,
                                            fontSize: 12,
                                          ),
                                          onChanged: (_) =>
                                              saveSubjectAppreciation(subject),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                              // Ligne des totaux (unique si showTotals)
                              if (showTotals)
                                (() {
                                  double sumCoeff = 0.0;
                                  double sumPtsEleve =
                                      0.0; // Σ (moyenne_matiere * coeff_matiere)
                                  double sumPtsClasse =
                                      0.0; // Σ (moy_classe_matiere * coeff_matiere)
                                  for (final subject in names) {
                                    final subjectGrades = studentGrades
                                        .where((g) => g.subject == subject)
                                        .toList();
                                    final devoirs = subjectGrades
                                        .where((g) => g.type == 'Devoir')
                                        .toList();
                                    final compositions = subjectGrades
                                        .where((g) => g.type == 'Composition')
                                        .toList();
                                    double total = 0.0;
                                    double totalCoeff = 0.0;
                                    for (final g in [
                                      ...devoirs,
                                      ...compositions,
                                    ]) {
                                      if (g.maxValue > 0 && g.coefficient > 0) {
                                        total +=
                                            ((g.value / g.maxValue) * 20) *
                                            g.coefficient;
                                        totalCoeff += g.coefficient;
                                      }
                                    }
                                    final moyenneMatiere = totalCoeff > 0
                                        ? (total / totalCoeff)
                                        : 0.0;
                                    final subjectWeight =
                                        (weights[subject] ?? totalCoeff);
                                    sumCoeff += subjectWeight;
                                    // Points élève = moyenne matière * coeff matière
                                    if (subjectGrades.isNotEmpty)
                                      sumPtsEleve +=
                                          moyenneMatiere * subjectWeight;
                                    final txt =
                                        (moyClasseControllers[subject]?.text ??
                                                '')
                                            .trim();
                                    final val = double.tryParse(
                                      txt.replaceAll(',', '.'),
                                    );
                                    if (val != null) {
                                      // Points classe = moyenne_classe * coeff matière
                                      sumPtsClasse += val * subjectWeight;
                                    }
                                  }
                                  final bool sumOk =
                                      (sumCoeff - 20).abs() < 1e-6;
                                  return TableRow(
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                    ),
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          'TOTAUX',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: mainColor,
                                          ),
                                        ),
                                      ),
                                      SizedBox.shrink(),
                                      SizedBox.shrink(),
                                      SizedBox.shrink(),
                                      SizedBox.shrink(),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          sumCoeff > 0
                                              ? sumCoeff.toStringAsFixed(2)
                                              : '0',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: sumOk
                                                ? secondaryColor
                                                : Colors.red,
                                          ),
                                        ),
                                      ),
                                      SizedBox.shrink(),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          sumPtsEleve > 0
                                              ? sumPtsEleve.toStringAsFixed(2)
                                              : '0',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Text(
                                          sumPtsClasse > 0
                                              ? sumPtsClasse.toStringAsFixed(2)
                                              : '0',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ),
                                      SizedBox.shrink(),
                                    ],
                                  );
                                })(),
                            ],
                          );
                        },
                      );
                    }

                    if (!hasCategories) {
                      return [buildTableForSubjects(subjectNames)];
                    }
                    // Ordonner les sections selon l'ordre des catégories, puis Non classée
                    final List<String?> orderedKeys = [];
                    for (final cat in categories) {
                      if (grouped.containsKey(cat.id)) orderedKeys.add(cat.id);
                    }
                    if (grouped.containsKey(null)) orderedKeys.add(null);

                    final List<Widget> sections = [];
                    for (final key in orderedKeys) {
                      final bool isUncat = key == null;
                      final String label = isUncat
                          ? 'Matières non classées'
                          : 'Matières ' +
                                categories
                                    .firstWhere(
                                      (c) => c.id == key,
                                      orElse: () => Category.empty(),
                                    )
                                    .name
                                    .toLowerCase();
                      final Color badge = isUncat
                          ? Colors.blueGrey
                          : Color(
                              int.parse(
                                (categories
                                        .firstWhere(
                                          (c) => c.id == key,
                                          orElse: () => Category.empty(),
                                        )
                                        .color)
                                    .replaceFirst('#', '0xff'),
                              ),
                            );
                      sections.add(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: badge,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                label,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: secondaryColor,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${grouped[key]!.length} matière(s)',
                                style: TextStyle(
                                  color: secondaryColor.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                      sections.add(
                        buildTableForSubjects(grouped[key]!, showTotals: false),
                      );
                      sections.add(const SizedBox(height: 12));
                    }
                    // Un seul TOTAUX global additionnant toutes les matières
                    sections.add(
                      FutureBuilder<Map<String, double>>(
                        future: _dbService.getClassSubjectCoefficients(
                          selectedClass ?? student.className,
                          selectedAcademicYear ?? effectiveYear,
                        ),
                        builder: (context, wSnapshot) {
                          final weights = wSnapshot.data ?? {};
                          double sumCoeff = 0.0;
                          double sumPtsEleve = 0.0;
                          double sumPtsClasse = 0.0;
                          for (final subject in subjectNames) {
                            final subjectGrades = studentGrades
                                .where((g) => g.subject == subject)
                                .toList();
                            final devoirs = subjectGrades
                                .where((g) => g.type == 'Devoir')
                                .toList();
                            final compositions = subjectGrades
                                .where((g) => g.type == 'Composition')
                                .toList();
                            double total = 0.0;
                            double totalCoeff = 0.0;
                            for (final g in [...devoirs, ...compositions]) {
                              if (g.maxValue > 0 && g.coefficient > 0) {
                                total +=
                                    ((g.value / g.maxValue) * 20) *
                                    g.coefficient;
                                totalCoeff += g.coefficient;
                              }
                            }
                            final moyenneMatiere = totalCoeff > 0
                                ? (total / totalCoeff)
                                : 0.0;
                            final subjectWeight =
                                (weights[subject] ?? totalCoeff);
                            sumCoeff += subjectWeight;
                            if (subjectGrades.isNotEmpty)
                              sumPtsEleve += moyenneMatiere * subjectWeight;
                            final txt =
                                (moyClasseControllers[subject]?.text ?? '')
                                    .trim();
                            final val = double.tryParse(
                              txt.replaceAll(',', '.'),
                            );
                            if (val != null)
                              sumPtsClasse += val * subjectWeight;
                          }
                          final bool sumOk = (sumCoeff - 20).abs() < 1e-6;
                          return Table(
                            border: TableBorder.all(
                              color: Colors.blue.shade100,
                            ),
                            columnWidths: const {
                              0: FlexColumnWidth(2),
                              1: FlexColumnWidth(2),
                              2: FlexColumnWidth(),
                              3: FlexColumnWidth(),
                              4: FlexColumnWidth(),
                              5: FlexColumnWidth(),
                              6: FlexColumnWidth(1.2),
                              7: FlexColumnWidth(1.4),
                              8: FlexColumnWidth(1.2),
                              9: FlexColumnWidth(2),
                            },
                            children: [
                              TableRow(
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                ),
                                children: [
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      'TOTAUX',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: mainColor,
                                      ),
                                    ),
                                  ),
                                  SizedBox.shrink(),
                                  SizedBox.shrink(),
                                  SizedBox.shrink(),
                                  SizedBox.shrink(),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      sumCoeff > 0
                                          ? sumCoeff.toStringAsFixed(2)
                                          : '0',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: sumOk
                                            ? secondaryColor
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                  SizedBox.shrink(),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      sumPtsEleve > 0
                                          ? sumPtsEleve.toStringAsFixed(2)
                                          : '0',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      sumPtsClasse > 0
                                          ? sumPtsClasse.toStringAsFixed(2)
                                          : '0',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  ),
                                  SizedBox.shrink(),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    );
                    return sections;
                  }(),
                  const SizedBox(height: 24),
                  // Synthèse : tableau des moyennes par période
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
                        Text(
                          'Moyennes par $_periodMode',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: mainColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<Map<String, Map<String, num>>>(
                          future: _computeRankPerTermForStudentUI(
                            student,
                            allTerms,
                          ),
                          builder: (context, snapshot) {
                            final rankPerTerm = snapshot.data ?? {};
                            return Table(
                              border: TableBorder.all(
                                color: Colors.blue.shade100,
                              ),
                              columnWidths: {
                                for (int i = 0; i < allTerms.length; i++)
                                  i: FlexColumnWidth(),
                              },
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: tableHeaderBg,
                                  ),
                                  children: List.generate(allTerms.length, (i) {
                                    final label = allTerms[i];
                                    return Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: tableHeaderText,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                                TableRow(
                                  children: List.generate(allTerms.length, (i) {
                                    // Determine if this column corresponds to the currently selected term
                                    final isSelected =
                                        selectedTerm != null &&
                                        allTerms[i] == selectedTerm;
                                    // Compute previous period index
                                    final prevIndex = i - 1;
                                    final prevAvgAvailable =
                                        prevIndex >= 0 &&
                                        prevIndex < moyennesParPeriode.length &&
                                        moyennesParPeriode[prevIndex] != null;
                                    final mainAvg =
                                        (i < moyennesParPeriode.length &&
                                            moyennesParPeriode[i] != null)
                                        ? moyennesParPeriode[i]!
                                              .toStringAsFixed(2)
                                        : '-';
                                    final prevText = prevAvgAvailable
                                        ? moyennesParPeriode[prevIndex]!
                                              .toStringAsFixed(2)
                                        : null;
                                    final term = allTerms[i];
                                    final r = rankPerTerm[term];
                                    // If moyennesParPeriode n'a pas la valeur (car 'grades' ne contient que la période sélectionnée),
                                    // utilise la moyenne calculée côté Future (avg) pour cette période
                                    String effectiveAvg = mainAvg;
                                    if (mainAvg == '-' &&
                                        r != null &&
                                        (r['avg'] ?? 0) > 0) {
                                      effectiveAvg = (r['avg'] as num)
                                          .toStringAsFixed(2);
                                    }
                                    String suffix = '';
                                    if (r != null &&
                                        (r['nb'] ?? 0) > 0 &&
                                        effectiveAvg != '-') {
                                      suffix =
                                          ' (rang ${r['rank']}/${r['nb']})';
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          RichText(
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: effectiveAvg,
                                                  style: TextStyle(
                                                    color: secondaryColor,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                if (suffix.isNotEmpty)
                                                  TextSpan(
                                                    text: ' ' + suffix,
                                                    style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (isSelected &&
                                              prevText != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Précédent: ' + prevText,
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Assiduité (de retour à sa place sous le bloc moyennes par période)
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
                        Text(
                          'Assiduité',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: mainColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: presencePercentController,
                                decoration: InputDecoration(
                                  labelText: 'Présence (%)',
                                  labelStyle: TextStyle(color: secondaryColor),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  hintText: '0.0',
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: retardsController,
                                decoration: InputDecoration(
                                  labelText: 'Retards',
                                  labelStyle: TextStyle(color: secondaryColor),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  hintText: '0',
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: absJustifieesController,
                                decoration: InputDecoration(
                                  labelText: 'Absences justifiées',
                                  labelStyle: TextStyle(color: secondaryColor),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  hintText: '0',
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: absInjustifieesController,
                                decoration: InputDecoration(
                                  labelText: 'Absences injustifiées',
                                  labelStyle: TextStyle(color: secondaryColor),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  hintText: '0',
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: conduiteController,
                          decoration: InputDecoration(
                            labelText: 'Conduite/Comportement',
                            labelStyle: TextStyle(color: secondaryColor),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            hintText: 'Ex: Très bonne conduite',
                            hintStyle: TextStyle(
                              color: Colors.blueGrey.shade400,
                            ),
                            filled: true,
                            fillColor: Colors.blueGrey.shade50,
                          ),
                          maxLines: 2,
                          style: const TextStyle(color: Colors.black87),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Sanctions :',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: sanctionsController,
                          decoration: InputDecoration(
                            hintText: 'Saisir les sanctions',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            hintStyle: TextStyle(
                              color: secondaryColor.withOpacity(0.7),
                            ),
                            filled: true,
                            fillColor: Colors.blueGrey.shade50,
                          ),
                          style: TextStyle(color: secondaryColor, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Synthèse générale
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: FutureBuilder<Map<String, dynamic>>(
                            future: _prepareReportCardData(student),
                            builder: (context, statsSnapshot) {
                              double moyenneEleve = moyenneGenerale;
                              double? moyenneClasse = moyenneGeneraleDeLaClasse;
                              double? moyenneMax = moyenneLaPlusForte;
                              double? moyenneMin = moyenneLaPlusFaible;
                              double? moyenneAnn = moyenneAnnuelle;
                              int rangValue = rang;
                              int nbElevesValue = nbEleves;
                              bool exaequoValue = false;
                              String mentionValue = mention;
                              List<double?> moyennesPeriodes =
                                  List<double?>.from(moyennesParPeriode);
                              String selectedTermValue = selectedTerm ?? '';

                              if (statsSnapshot.hasData) {
                                final stats = statsSnapshot.data!;
                                moyenneEleve =
                                    (stats['moyenneGenerale'] as double?) ??
                                    moyenneEleve;
                                moyenneClasse =
                                    stats['moyenneGeneraleDeLaClasse']
                                        as double? ??
                                    moyenneClasse;
                                moyenneMax =
                                    stats['moyenneLaPlusForte'] as double? ??
                                    moyenneMax;
                                moyenneMin =
                                    stats['moyenneLaPlusFaible'] as double? ??
                                    moyenneMin;
                                moyenneAnn =
                                    stats['moyenneAnnuelle'] as double? ??
                                    moyenneAnn;
                                rangValue =
                                    (stats['rang'] as int?) ?? rangValue;
                                nbElevesValue =
                                    (stats['nbEleves'] as int?) ??
                                    nbElevesValue;
                                exaequoValue =
                                    (stats['exaequo'] as bool?) ?? exaequoValue;
                                mentionValue =
                                    (stats['mention'] as String?) ??
                                    mentionValue;
                                moyennesPeriodes =
                                    (stats['moyennesParPeriode'] as List)
                                        .cast<double?>();
                                selectedTermValue =
                                    (stats['selectedTerm'] as String?) ??
                                    selectedTermValue;
                              }

                              // Affiche la moyenne annuelle/ rang annuel uniquement en fin de période
                              bool _isEndOfYear(
                                String periodLabel,
                                String selectedTerm,
                              ) {
                                final pl = periodLabel.toLowerCase();
                                final st = selectedTerm.toLowerCase();
                                if (pl.contains('trimestre'))
                                  return st.contains('3');
                                if (pl.contains('semestre'))
                                  return st.contains('2');
                                return false;
                              }

                              final bool showAnnual = _isEndOfYear(
                                periodLabel,
                                selectedTermValue,
                              );

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Moyenne de l\'élève : ${moyenneEleve.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                      fontSize: 18,
                                    ),
                                  ),
                                  if (moyenneClasse != null)
                                    Text(
                                      'Moyenne de la classe : ${moyenneClasse.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  if (moyenneMax != null)
                                    Text(
                                      'Moyenne la plus forte : ${moyenneMax.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  if (moyenneMin != null)
                                    Text(
                                      'Moyenne la plus faible : ${moyenneMin.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  if (showAnnual && moyenneAnn != null)
                                    Text(
                                      'Moyenne annuelle : ${moyenneAnn.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  // Moyenne annuelle de la classe
                                  if (showAnnual &&
                                      statsSnapshot.hasData &&
                                      (statsSnapshot
                                                  .data!['moyenneAnnuelleClasse']
                                              as double?) !=
                                          null)
                                    Text(
                                      'Moyenne annuelle de la classe : ${(statsSnapshot.data!['moyenneAnnuelleClasse'] as double).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  // Rang annuel
                                  if (showAnnual &&
                                      statsSnapshot.hasData &&
                                      (statsSnapshot.data!['rangAnnuel']
                                              as int?) !=
                                          null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          'Rang annuel : ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: secondaryColor,
                                          ),
                                        ),
                                        Text(
                                          '${(statsSnapshot.data!['rangAnnuel'] as int)} / $nbElevesValue',
                                          style: TextStyle(
                                            color: secondaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (moyennesPeriodes.length > 1 &&
                                      moyennesPeriodes.any(
                                        (m) => m != null,
                                      )) ...[
                                    const SizedBox(height: 8),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        'Rang : ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: secondaryColor,
                                        ),
                                      ),
                                      Text(
                                        exaequoValue
                                            ? '$rangValue (ex æquo) / $nbElevesValue'
                                            : '$rangValue / $nbElevesValue',
                                        style: TextStyle(color: secondaryColor),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        'Mention : ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: secondaryColor,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: mainColor,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          mentionValue,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Appréciation générale :',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: secondaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: appreciationGeneraleController,
                                decoration: InputDecoration(
                                  hintText: 'Saisir une appréciation générale',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                maxLines: 2,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Décision du conseil de classe :',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: secondaryColor,
                                      ),
                                    ),
                                  ),
                                  // Bouton de réinitialisation seulement en fin d'année
                                  if (isEndOfYear &&
                                      decisionAutomatique != null)
                                    IconButton(
                                      onPressed: () {
                                        decisionController.text =
                                            decisionAutomatique!;
                                        saveSynthese();
                                      },
                                      icon: Icon(
                                        Icons.refresh,
                                        size: 18,
                                        color: mainColor,
                                      ),
                                      tooltip:
                                          'Réinitialiser à la décision automatique',
                                      padding: EdgeInsets.zero,
                                      constraints: BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Indicateur de décision automatique seulement en fin d'année
                              if (isEndOfYear &&
                                  decisionAutomatique != null &&
                                  decisionController.text ==
                                      decisionAutomatique)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 16,
                                        color: Colors.blue.shade600,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Décision automatique basée sur la moyenne annuelle (${moyenneAnnuelle?.toStringAsFixed(2) ?? moyenneGenerale.toStringAsFixed(2)})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue.shade700,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              TextField(
                                controller: decisionController,
                                decoration: InputDecoration(
                                  hintText: 'Saisir la décision',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Recommandations :',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: secondaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: recommandationsController,
                                decoration: InputDecoration(
                                  hintText: 'Conseils et recommandations',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                maxLines: 2,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Forces :',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: secondaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: forcesController,
                                decoration: InputDecoration(
                                  hintText: 'Points forts',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                maxLines: 2,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Points à développer :',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: secondaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: pointsDevelopperController,
                                decoration: InputDecoration(
                                  hintText: "Axes d'amélioration",
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  hintStyle: TextStyle(
                                    color: secondaryColor.withOpacity(0.7),
                                  ),
                                  filled: true,
                                  fillColor: Colors.blueGrey.shade50,
                                ),
                                maxLines: 2,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 3e colonne retirée: Conduite, Retards, Sanctions sont déplacés sous le bloc Assiduité
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.blue.shade100,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Fait à : ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      faitAController.text.isNotEmpty
                                          ? faitAController.text
                                          : (info.address.isNotEmpty
                                              ? info.address
                                              : '__________________________'),
                                      style: TextStyle(color: secondaryColor),
                                      overflow: TextOverflow.visible,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              Text(
                                schoolLevelNotifier.value
                                        .toLowerCase()
                                        .contains('lycée')
                                    ? 'Proviseur(e) :'
                                    : 'Directeur(ice) :',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: mainColor,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '__________________________',
                                style: TextStyle(color: secondaryColor),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 32),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Le : ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: mainColor,
                                    ),
                                  ),
                                  Text(
                                    leDateController.text.isNotEmpty
                                        ? leDateController.text
                                        : DateFormat('dd/MM/yyyy')
                                            .format(DateTime.now()),
                                    style: TextStyle(color: secondaryColor),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              Builder(
                                builder: (context) {
                                  final currentClass = classes.firstWhere(
                                    (c) => c.name == selectedClass,
                                    orElse: () => Class.empty(),
                                  );
                                  final t = currentClass.titulaire ?? '';
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Titulaire : ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: mainColor,
                                            ),
                                          ),
                                          if (t.isNotEmpty)
                                            Text(
                                              t,
                                              style: TextStyle(
                                                color: secondaryColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '__________________________',
                                        style: TextStyle(color: secondaryColor),
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
                  const SizedBox(height: 8),
                  // Bouton Export PDF
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            // Demande l'orientation
                            final orientation =
                                await showDialog<String>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('Orientation du PDF'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          title: Text('Portrait'),
                                          leading: Icon(
                                            Icons.stay_current_portrait,
                                          ),
                                          onTap: () => Navigator.of(
                                            context,
                                          ).pop('portrait'),
                                        ),
                                        ListTile(
                                          title: Text('Paysage'),
                                          leading: Icon(
                                            Icons.stay_current_landscape,
                                          ),
                                          onTap: () => Navigator.of(
                                            context,
                                          ).pop('landscape'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ) ??
                                'portrait';
                            final isLandscape = orientation == 'landscape';
                            final professeurs = <String, String>{
                              for (final subject in subjectNames)
                                subject: profControllers[subject]?.text ?? '-',
                            };
                            final appreciations = <String, String>{
                              for (final subject in subjectNames)
                                subject:
                                    appreciationControllers[subject]?.text ??
                                    '-',
                            };
                            final moyennesClasse = <String, String>{
                              for (final subject in subjectNames)
                                subject:
                                    moyClasseControllers[subject]?.text ?? '-',
                            };
                            final appreciationGenerale =
                                appreciationGeneraleController.text;
                            final decision = decisionController.text;
                            final telEtab = telEtabController.text;
                            final mailEtab = mailEtabController.text;
                            final webEtab = webEtabController.text;
                            // Adresse et date d'export automatiques
                            final String faitA = (faitAController.text.trim().isNotEmpty)
                                ? faitAController.text.trim()
                                : info.address;
                            final String leDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
                            final currentClass = classes.firstWhere(
                              (c) => c.name == selectedClass,
                              orElse: () => Class.empty(),
                            );
                            final data = await _prepareReportCardData(student);
                            final List<double?> moyennesParPeriodePdf =
                                (data['moyennesParPeriode'] as List)
                                    .cast<double?>();
                            final double moyenneGeneralePdf =
                                data['moyenneGenerale'] as double;
                            final int rangPdf = data['rang'] as int;
                            final int nbElevesPdf = data['nbEleves'] as int;
                            final String mentionPdf = data['mention'] as String;
                            final List<String> allTermsPdf =
                                (data['allTerms'] as List).cast<String>();
                            final String periodLabelPdf =
                                data['periodLabel'] as String;
                            final String selectedTermPdf =
                                data['selectedTerm'] as String;
                            final String academicYearPdf =
                                data['academicYear'] as String;
                            final String niveauPdf = data['niveau'] as String;
                            final double? moyenneGeneraleDeLaClassePdf =
                                data['moyenneGeneraleDeLaClasse'] as double?;
                            final double? moyenneLaPlusFortePdf =
                                data['moyenneLaPlusForte'] as double?;
                            final double? moyenneLaPlusFaiblePdf =
                                data['moyenneLaPlusFaible'] as double?;
                            final double? moyenneAnnuellePdf =
                                data['moyenneAnnuelle'] as double?;
                            final pdfBytes =
                                await PdfService.generateReportCardPdf(
                                  student: student,
                                  schoolInfo: info,
                                  grades: (data['grades'] as List)
                                      .cast<Grade>(),
                                  professeurs: professeurs,
                                  appreciations: appreciations,
                                  moyennesClasse: moyennesClasse,
                                  appreciationGenerale: appreciationGenerale,
                                  decision: decision,
                                  recommandations:
                                      recommandationsController.text,
                                  forces: forcesController.text,
                                  pointsADevelopper:
                                      pointsDevelopperController.text,
                                  sanctions: sanctionsController.text,
                                  attendanceJustifiee:
                                      int.tryParse(
                                        absJustifieesController.text,
                                      ) ??
                                      0,
                                  attendanceInjustifiee:
                                      int.tryParse(
                                        absInjustifieesController.text,
                                      ) ??
                                      0,
                                  retards:
                                      int.tryParse(retardsController.text) ?? 0,
                                  presencePercent:
                                      double.tryParse(
                                        presencePercentController.text,
                                      ) ??
                                      0.0,
                                  conduite: conduiteController.text,
                                  telEtab: telEtab,
                                  mailEtab: mailEtab,
                                  webEtab: webEtab,
                                  titulaire: currentClass.titulaire ?? '',
                                  subjects: subjectNames,
                                  moyennesParPeriode: moyennesParPeriodePdf,
                                  moyenneGenerale: moyenneGeneralePdf,
                                  rang: rangPdf,
                                  exaequo: (data['exaequo'] as bool?) ?? false,
                                  nbEleves: nbElevesPdf,
                                  mention: mentionPdf,
                                  allTerms: allTermsPdf,
                                  periodLabel: periodLabelPdf,
                                  selectedTerm: selectedTermPdf,
                                  academicYear: academicYearPdf,
                                  faitA: faitA,
                                  leDate: leDate,
                                  isLandscape: isLandscape,
                                  niveau: niveauPdf,
                                  moyenneGeneraleDeLaClasse:
                                      moyenneGeneraleDeLaClassePdf,
                                  moyenneLaPlusForte: moyenneLaPlusFortePdf,
                                  moyenneLaPlusFaible: moyenneLaPlusFaiblePdf,
                                  moyenneAnnuelle: moyenneAnnuellePdf,
                                );
                            await Printing.layoutPdf(
                              onLayout: (format) async =>
                                  Uint8List.fromList(pdfBytes),
                            );
                          },
                          icon: Icon(Icons.picture_as_pdf),
                          label: Text('Exporter en PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: mainColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            // Demande l'orientation
                            final orientation =
                                await showDialog<String>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('Orientation du PDF'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          title: Text('Portrait'),
                                          leading: Icon(
                                            Icons.stay_current_portrait,
                                          ),
                                          onTap: () => Navigator.of(
                                            context,
                                          ).pop('portrait'),
                                        ),
                                        ListTile(
                                          title: Text('Paysage'),
                                          leading: Icon(
                                            Icons.stay_current_landscape,
                                          ),
                                          onTap: () => Navigator.of(
                                            context,
                                          ).pop('landscape'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ) ??
                                'portrait';
                            final isLandscape = orientation == 'landscape';
                            final professeurs = <String, String>{
                              for (final subject in subjectNames)
                                subject: profControllers[subject]?.text ?? '-',
                            };
                            final appreciations = <String, String>{
                              for (final subject in subjectNames)
                                subject:
                                    appreciationControllers[subject]?.text ??
                                    '-',
                            };
                            final moyennesClasse = <String, String>{
                              for (final subject in subjectNames)
                                subject:
                                    moyClasseControllers[subject]?.text ?? '-',
                            };
                            final appreciationGenerale =
                                appreciationGeneraleController.text;
                            final decision = decisionController.text;
                            final telEtab = telEtabController.text;
                            final mailEtab = mailEtabController.text;
                            final webEtab = webEtabController.text;
                            // Adresse et date d'export automatiques
                            final String faitA = (faitAController.text.trim().isNotEmpty)
                                ? faitAController.text.trim()
                                : info.address;
                            final String leDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
                            final currentClass = classes.firstWhere(
                              (c) => c.name == selectedClass,
                              orElse: () => Class.empty(),
                            );
                            final data = await _prepareReportCardData(student);
                            final List<double?> moyennesParPeriodePdf =
                                (data['moyennesParPeriode'] as List)
                                    .cast<double?>();
                            final double moyenneGeneralePdf =
                                data['moyenneGenerale'] as double;
                            final int rangPdf = data['rang'] as int;
                            final int nbElevesPdf = data['nbEleves'] as int;
                            final String mentionPdf = data['mention'] as String;
                            final List<String> allTermsPdf =
                                (data['allTerms'] as List).cast<String>();
                            final String periodLabelPdf =
                                data['periodLabel'] as String;
                            final String selectedTermPdf =
                                data['selectedTerm'] as String;
                            final String academicYearPdf =
                                data['academicYear'] as String;
                            final String niveauPdf = data['niveau'] as String;
                            final double? moyenneGeneraleDeLaClassePdf =
                                data['moyenneGeneraleDeLaClasse'] as double?;
                            final double? moyenneLaPlusFortePdf =
                                data['moyenneLaPlusForte'] as double?;
                            final double? moyenneLaPlusFaiblePdf =
                                data['moyenneLaPlusFaible'] as double?;
                            final double? moyenneAnnuellePdf =
                                data['moyenneAnnuelle'] as double?;
                            final pdfBytes =
                                await PdfService.generateReportCardPdf(
                                  student: student,
                                  schoolInfo: info,
                                  grades: (data['grades'] as List)
                                      .cast<Grade>(),
                                  professeurs: professeurs,
                                  appreciations: appreciations,
                                  moyennesClasse: moyennesClasse,
                                  appreciationGenerale: appreciationGenerale,
                                  decision: decision,
                                  recommandations:
                                      recommandationsController.text,
                                  forces: forcesController.text,
                                  pointsADevelopper:
                                      pointsDevelopperController.text,
                                  sanctions: sanctionsController.text,
                                  attendanceJustifiee:
                                      int.tryParse(
                                        absJustifieesController.text,
                                      ) ??
                                      0,
                                  attendanceInjustifiee:
                                      int.tryParse(
                                        absInjustifieesController.text,
                                      ) ??
                                      0,
                                  retards:
                                      int.tryParse(retardsController.text) ?? 0,
                                  presencePercent:
                                      double.tryParse(
                                        presencePercentController.text,
                                      ) ??
                                      0.0,
                                  conduite: conduiteController.text,
                                  telEtab: telEtab,
                                  mailEtab: mailEtab,
                                  webEtab: webEtab,
                                  titulaire: currentClass.titulaire ?? '',
                                  subjects: subjectNames,
                                  moyennesParPeriode: moyennesParPeriodePdf,
                                  moyenneGenerale: moyenneGeneralePdf,
                                  rang: rangPdf,
                                  exaequo: (data['exaequo'] as bool?) ?? false,
                                  nbEleves: nbElevesPdf,
                                  mention: mentionPdf,
                                  allTerms: allTermsPdf,
                                  periodLabel: periodLabelPdf,
                                  selectedTerm: selectedTermPdf,
                                  academicYear: academicYearPdf,
                                  faitA: faitA,
                                  leDate: leDate,
                                  isLandscape: isLandscape,
                                  niveau: niveauPdf,
                                  moyenneGeneraleDeLaClasse:
                                      moyenneGeneraleDeLaClassePdf,
                                  moyenneLaPlusForte: moyenneLaPlusFortePdf,
                                  moyenneLaPlusFaible: moyenneLaPlusFaiblePdf,
                                  moyenneAnnuelle: moyenneAnnuellePdf,
                                );
                            String? directoryPath = await FilePicker.platform
                                .getDirectoryPath(
                                  dialogTitle:
                                      'Choisir le dossier de sauvegarde',
                                );
                            if (directoryPath != null) {
                              final fileName =
                                  'Bulletin_${'${student.firstName}_${student.lastName}'.replaceAll(' ', '_')}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
                              final file = File('$directoryPath/$fileName');
                              await file.writeAsBytes(pdfBytes);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Bulletin enregistré dans $directoryPath',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          icon: Icon(Icons.save_alt),
                          label: Text('Enregistrer PDF...'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  double? _calculateClassAverageForSubject(String subject) {
    final gradesForSubject = _effectiveGradesForSubject(subject);

    if (gradesForSubject.isEmpty) return null;

    double total = 0.0;
    double totalCoeff = 0.0;
    for (final g in gradesForSubject) {
      if (g.maxValue > 0 && g.coefficient > 0) {
        total += ((g.value / g.maxValue) * 20) * g.coefficient;
        totalCoeff += g.coefficient;
      }
    }
    return totalCoeff > 0 ? total / totalCoeff : null;
  }

  // Construit la liste des notes en tenant compte des saisies en cours (_gradeDrafts)
  List<Grade> _effectiveGradesForSubject(String subject) {
    final base = grades
        .where(
          (g) =>
              g.subject == subject &&
              g.className == selectedClass &&
              g.academicYear == selectedAcademicYear &&
              g.term == selectedTerm &&
              (g.type == 'Devoir' || g.type == 'Composition') &&
              g.value != null &&
              g.value != 0,
        )
        .toList();

    // Applique les brouillons (valeur tapée mais pas encore sauvegardée)
    final Map<String, Grade> byStudent = {for (final g in base) g.studentId: g};
    _gradeDrafts.forEach((studentId, txt) {
      final v = double.tryParse(txt);
      if (v == null) return;
      final existing = byStudent[studentId];
      if (existing != null) {
        byStudent[studentId] = Grade(
          id: existing.id,
          studentId: existing.studentId,
          className: existing.className,
          academicYear: existing.academicYear,
          subjectId: existing.subjectId,
          subject: existing.subject,
          term: existing.term,
          value: v,
          label: existing.label,
          maxValue: existing.maxValue,
          coefficient: existing.coefficient,
          type: existing.type,
        );
      } else if (selectedClass != null &&
          selectedAcademicYear != null &&
          selectedTerm != null) {
        // Si pas de note existante pour cet élève, mais saisie en cours -> inclure dans le calcul
        final course = subjects.firstWhere(
          (c) => c.name == subject,
          orElse: () => Course.empty(),
        );
        byStudent[studentId] = Grade(
          studentId: studentId,
          className: selectedClass!,
          academicYear: selectedAcademicYear!,
          subjectId: course.id,
          subject: subject,
          term: selectedTerm!,
          value: v,
          label: null,
          maxValue: 20.0,
          coefficient: 1.0,
          type: 'Devoir',
        );
      }
    });
    return byStudent.values.toList();
  }

  Widget _buildArchiveTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(
            controller: archiveSearchController,
            hintText: 'Rechercher dans les archives...',
            onChanged: (val) => setState(() => _archiveSearchQuery = val),
          ),
          CheckboxListTile(
            title: Text("Rechercher dans toutes les années"),
            value: _searchAllYears,
            onChanged: (bool? value) {
              setState(() {
                _searchAllYears = value ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 16),
          if (!_searchAllYears) _buildSelectionSection(),
          const SizedBox(height: 24),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _searchAllYears
                ? _dbService.getAllArchivedReportCards()
                : (selectedAcademicYear == null ||
                      selectedAcademicYear!.isEmpty ||
                      selectedClass == null ||
                      selectedClass!.isEmpty)
                ? Future.value([])
                : _dbService.getArchivedReportCardsByClassAndYear(
                    academicYear: selectedAcademicYear!,
                    className: selectedClass!,
                  ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Text(
                    'Aucune archive trouvée pour cette sélection.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              final allArchivedReportCards = snapshot.data!;
              final studentIdsFromArchive = allArchivedReportCards
                  .map((rc) => rc['studentId'] as String)
                  .toSet();

              // Filtrer les élèves en fonction de la recherche et des archives
              final filteredStudents = students.where((student) {
                final nameMatch =
                    _archiveSearchQuery.isEmpty ||
                    '${student.firstName} ${student.lastName}'.toLowerCase().contains(
                      _archiveSearchQuery.toLowerCase(),
                    );
                final inArchive = studentIdsFromArchive.contains(student.id);
                return nameMatch && inArchive;
              }).toList();

              if (filteredStudents.isEmpty) {
                return Center(
                  child: Text(
                    'Aucun élève correspondant trouvé dans les archives.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              // Logique de pagination
              final startIndex = _archiveCurrentPage * _archiveItemsPerPage;
              final endIndex =
                  (startIndex + _archiveItemsPerPage > filteredStudents.length)
                  ? filteredStudents.length
                  : startIndex + _archiveItemsPerPage;
              final paginatedStudents = filteredStudents.sublist(
                startIndex,
                endIndex,
              );

              return Column(
                children: [
                  ...paginatedStudents.map((student) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          child: Text(
                            student.firstName.isNotEmpty ? student.firstName[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          '${student.firstName} ${student.lastName}'.trim(),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        subtitle: Text(
                          'Classe: ${student.className}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onSelected: (value) async {
                            if (value == 'profile') {
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    StudentProfilePage(student: student),
                              );
                            } else if (value == 'view') {
                              // Aperçu du bulletin (PDF preview) avec en-tête administratif harmonisé
                              try {
                                final info = await loadSchoolInfo();
                                // Orientation
                                final orientation =
                                    await showDialog<String>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Orientation du PDF'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              title: const Text('Portrait'),
                                              leading: const Icon(
                                                Icons.stay_current_portrait,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('portrait'),
                                            ),
                                            ListTile(
                                              title: const Text('Paysage'),
                                              leading: const Icon(
                                                Icons.stay_current_landscape,
                                              ),
                                              onTap: () => Navigator.of(
                                                context,
                                              ).pop('landscape'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ) ??
                                    'portrait';
                                final bool isLandscape =
                                    orientation == 'landscape';

                                // Construit les données comme pour l'export ZIP
                                final data = await _prepareReportCardData(
                                  student,
                                );
                                final subjectNames = (data['subjects'] as List)
                                    .cast<String>();
                                final archived = await _dbService.getReportCard(
                                  studentId: student.id,
                                  className: selectedClass ?? student.className,
                                  academicYear:
                                      selectedAcademicYear ??
                                      data['academicYear'],
                                  term: selectedTerm ?? data['selectedTerm'],
                                );
                                // Récupérer appréciations/professeurs/moyenne_classe enregistrées
                                final apps = await _dbService
                                    .getSubjectAppreciations(
                                      studentId: student.id,
                                      className:
                                          selectedClass ?? student.className,
                                      academicYear:
                                          selectedAcademicYear ??
                                          data['academicYear'],
                                      term:
                                          selectedTerm ?? data['selectedTerm'],
                                    );
                                final professeurs = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final appreciations = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                final moyennesClasse = <String, String>{
                                  for (final s in subjectNames) s: '-',
                                };
                                for (final row in apps) {
                                  final subject = row['subject'] as String?;
                                  if (subject != null) {
                                    professeurs[subject] =
                                        (row['professeur'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['professeur'] as String
                                        : '-';
                                    appreciations[subject] =
                                        (row['appreciation'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['appreciation'] as String
                                        : '-';
                                    moyennesClasse[subject] =
                                        (row['moyenne_classe'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? row['moyenne_classe'] as String
                                        : '-';
                                  }
                                }

                                final currentClass = classes.firstWhere(
                                  (c) =>
                                      c.name ==
                                      (selectedClass ?? student.className),
                                  orElse: () => Class.empty(),
                                );
                                final pdfBytes =
                                    await PdfService.generateReportCardPdf(
                                      student: student,
                                      schoolInfo: info,
                                      grades: (data['grades'] as List)
                                          .cast<Grade>(),
                                      professeurs: professeurs,
                                      appreciations: appreciations,
                                      moyennesClasse: moyennesClasse,
                                      appreciationGenerale:
                                          archived?['appreciation_generale']
                                              as String? ??
                                          '',
                                      decision:
                                          archived?['decision'] as String? ??
                                          '',
                                      recommandations:
                                          archived?['recommandations']
                                              as String? ??
                                          '',
                                      forces:
                                          archived?['forces'] as String? ?? '',
                                      pointsADevelopper:
                                          archived?['points_a_developper']
                                              as String? ??
                                          '',
                                      sanctions:
                                          archived?['sanctions'] as String? ??
                                          '',
                                      attendanceJustifiee:
                                          (archived?['attendance_justifiee']
                                              as int?) ??
                                          0,
                                      attendanceInjustifiee:
                                          (archived?['attendance_injustifiee']
                                              as int?) ??
                                          0,
                                      retards:
                                          (archived?['retards'] as int?) ?? 0,
                                      presencePercent:
                                          ((archived?['presence_percent']
                                                  as num?)
                                              ?.toDouble()) ??
                                          0.0,
                                      conduite:
                                          archived?['conduite'] as String? ??
                                          '',
                                      telEtab: info.telephone ?? '',
                                      mailEtab: info.email ?? '',
                                      webEtab: info.website ?? '',
                                      titulaire: currentClass.titulaire ?? '',
                                      subjects: subjectNames,
                                      moyennesParPeriode:
                                          (data['moyennesParPeriode'] as List)
                                              .cast<double?>(),
                                      moyenneGenerale:
                                          (data['moyenneGenerale'] as num)
                                              .toDouble(),
                                      rang: (data['rang'] as num).toInt(),
                                      exaequo:
                                          (data['exaequo'] as bool?) ?? false,
                                      nbEleves: (data['nbEleves'] as num)
                                          .toInt(),
                                      mention: data['mention'] as String,
                                      allTerms: (data['allTerms'] as List)
                                          .cast<String>(),
                                      periodLabel:
                                          data['periodLabel'] as String,
                                      selectedTerm:
                                          data['selectedTerm'] as String,
                                      academicYear:
                                          data['academicYear'] as String,
                                      faitA:
                                          archived?['fait_a'] as String? ?? '',
                                      leDate:
                                          archived?['le_date'] as String? ?? '',
                                      isLandscape: isLandscape,
                                      niveau: data['niveau'] as String,
                                      moyenneGeneraleDeLaClasse:
                                          (data['moyenneGeneraleDeLaClasse']
                                              as double?),
                                      moyenneLaPlusForte:
                                          (data['moyenneLaPlusForte']
                                              as double?),
                                      moyenneLaPlusFaible:
                                          (data['moyenneLaPlusFaible']
                                              as double?),
                                      moyenneAnnuelle:
                                          (data['moyenneAnnuelle'] as double?),
                                      duplicata: true,
                                    );
                                await Printing.layoutPdf(
                                  onLayout: (format) async =>
                                      Uint8List.fromList(pdfBytes),
                                );
                              } catch (e) {
                                showRootSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Impossible d\'afficher le bulletin: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'profile',
                              child: Text('Voir le profil'),
                            ),
                            const PopupMenuItem(
                              value: 'view',
                              child: Text('Voir le bulletin'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  _buildPaginationControls(filteredStudents.length),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls(int totalItems) {
    final totalPages = (totalItems / _archiveItemsPerPage).ceil();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: _archiveCurrentPage > 0
              ? () {
                  setState(() {
                    _archiveCurrentPage--;
                  });
                }
              : null,
        ),
        Text('Page ${_archiveCurrentPage + 1} sur $totalPages'),
        IconButton(
          icon: Icon(Icons.arrow_forward),
          onPressed: _archiveCurrentPage < totalPages - 1
              ? () {
                  setState(() {
                    _archiveCurrentPage++;
                  });
                }
              : null,
        ),
      ],
    );
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          // reset view state
          void resetState() {
            _importError = null;
            _importSuccessCount = 0;
            _importErrorCount = 0;
            _importProgress = 0.0;
            _importRowResults = [];
            setStateDialog(() {});
          }

          Future<void> pickAndValidate() async {
            resetState();
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['xlsx', 'xls', 'csv'],
              withData: true,
            );
            if (result == null || result.files.isEmpty) return;
            _importPickedFile = result.files.first;
            // Taille max 10MB
            if ((_importPickedFile!.size) > 10 * 1024 * 1024) {
              _importError = 'Fichier trop volumineux (>10MB)';
              setStateDialog(() {});
              return;
            }
            _importValidating = true;
            setStateDialog(() {});
            try {
              final bytes =
                  _importPickedFile!.bytes ??
                  await File(_importPickedFile!.path!).readAsBytes();
              final String ext =
                  _importPickedFile!.extension?.toLowerCase() ?? '';
              if (ext == 'csv') {
                await _parseCsvForPreview(
                  bytes,
                  setStateDialog,
                  (e) => _importError = e,
                );
              } else {
                await _parseExcelForPreview(
                  bytes,
                  setStateDialog,
                  (e) => _importError = e,
                );
              }
            } catch (e) {
              _importError = 'Erreur lecture: $e';
            } finally {
              _importValidating = false;
              setStateDialog(() {});
            }
          }

          Future<void> importNow({required bool skipErrors}) async {
            if (_importPreview == null) return;
            _importValidating = true;
            _importError = null;
            _importSuccessCount = 0;
            _importErrorCount = 0;
            _importProgress = 0;
            setStateDialog(() {});
            try {
              final result = await _performBulkImport(
                preview: _importPreview!,
                onProgress: (cur, total) {
                  _importProgress = total == 0 ? 0 : cur / total;
                  setStateDialog(() {});
                },
                onCounts: (ok, ko) {
                  _importSuccessCount = ok;
                  _importErrorCount = ko;
                  setStateDialog(() {});
                },
                skipErrors: skipErrors,
              );
              _importRowResults = result.rowResults;
              // Log import
              final first = _importPreview!.rows.isNotEmpty
                  ? _rowToMap(
                      _importPreview!.headers,
                      _importPreview!.rows.first,
                    )
                  : {};
              await _dbService.insertImportLog(
                filename: (_importPickedFile?.name ?? ''),
                user: null, // TODO: current user
                mode: skipErrors ? 'partial' : 'all_or_nothing',
                className: ((first['Classe'] ?? selectedClass ?? ''))
                    .toString(),
                academicYear: ((first['Annee'] ?? selectedAcademicYear ?? ''))
                    .toString(),
                term: ((first['Periode'] ?? selectedTerm ?? '')).toString(),
                total: _importPreview!.rows.length,
                success: _importSuccessCount,
                errors: _importErrorCount,
                warnings: 0,
                detailsJson: jsonEncode(result.rowResults),
              );
              // Invalider le cache de chargement des synthèses pour refléter les nouvelles valeurs importées
              _loadedReportCardKeys.clear();
              setState(() {});
              // Snackbar succès
              showRootSnackBar(
                SnackBar(
                  content: Text(
                    'Import terminé: ${_importSuccessCount} réussites, ${_importErrorCount} erreurs',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              _importError = '$e';
              showRootSnackBar(
                SnackBar(
                  content: Text('Erreur import: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            } finally {
              _importValidating = false;
              setStateDialog(() {});
            }
          }

          return AlertDialog(
            title: const Text('Import notes depuis Excel/CSV'),
            content: SizedBox(
              width: 900,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _importValidating ? null : pickAndValidate,
                        icon: const Icon(Icons.attach_file),
                        label: const Text(
                          'Sélectionner un fichier (.xlsx/.xls/.csv)',
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_importValidating)
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _importProgress == 0
                                ? null
                                : _importProgress,
                          ),
                        ),
                    ],
                  ),
                  if (_importError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _importError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildImportPreviewTable(),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        Text(
                          'OK: ${_importSuccessCount}  Erreurs: ${_importErrorCount}',
                        ),
                        OutlinedButton(
                          onPressed:
                              (_importPreview == null || _importValidating)
                              ? null
                              : () => importNow(skipErrors: false),
                          child: const Text('Importer (tout ou rien)'),
                        ),
                        ElevatedButton(
                          onPressed:
                              (_importPreview == null || _importValidating)
                              ? null
                              : () => importNow(skipErrors: true),
                          child: const Text('Importer (ignorer erreurs)'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_importRowResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: _importRowResults.take(100).map((res) {
                          final isError = (res['status'] == 'error');
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isError ? Icons.error : Icons.check_circle,
                              color: isError ? Colors.red : Colors.green,
                              size: 18,
                            ),
                            title: Text(
                              'Ligne ${res['row']} - ${res['status']}',
                            ),
                            subtitle: isError && res['message'] != null
                                ? Text(res['message'])
                                : null,
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImportPreviewTable() {
    if (_importPreview == null) {
      return const SizedBox.shrink();
    }
    final preview = _importPreview!;
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 350),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: preview.headers
              .map((h) => DataColumn(label: Text(h)))
              .toList(),
          rows: preview.rows.take(50).map((r) {
            return DataRow(
              cells: r.map((c) => DataCell(Text(c?.toString() ?? ''))).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _parseExcelForPreview(
    Uint8List bytes,
    void Function(void Function()) setStateDialog,
    void Function(String) setError,
  ) async {
    // Parse simple via 'excel' for headers and values
    try {
      final excel = ex.Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.isNotEmpty
          ? excel.tables.values.first
          : null;
      if (sheet == null) {
        setError('Feuille Excel vide ou invalide');
        return;
      }
      final headers = sheet.rows.isNotEmpty
          ? sheet.rows.first.map((c) => (c?.value ?? '').toString()).toList()
          : <String>[];
      final rows = <List<dynamic>>[];
      for (int i = 1; i < sheet.rows.length; i++) {
        rows.add(sheet.rows[i].map((c) => c?.value).toList());
      }
      _importPreview = _buildPreviewFromHeadersAndRows(headers, rows);
      setStateDialog(() {});
    } catch (e) {
      setError('Erreur parsing Excel: $e');
    }
  }

  Future<void> _parseCsvForPreview(
    Uint8List bytes,
    void Function(void Function()) setStateDialog,
    void Function(String) setError,
  ) async {
    try {
      final content = String.fromCharCodes(bytes);
      // Détection séparateur ; ou ,
      final hasSemicolon = content.contains(';');
      final sep = hasSemicolon ? ';' : ',';
      final lines = content
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        setError('Fichier CSV vide');
        return;
      }
      final headers = lines.first.split(sep);
      final rows = lines
          .skip(1)
          .map((l) => l.split(sep).map((s) => s.trim()).toList())
          .toList();
      _importPreview = _buildPreviewFromHeadersAndRows(headers, rows);
      setStateDialog(() {});
    } catch (e) {
      setError('Erreur parsing CSV: $e');
    }
  }

  _ImportPreview _buildPreviewFromHeadersAndRows(
    List<String> headers,
    List<List<dynamic>> rows,
  ) {
    // Validation d'en-têtes minimales
    final required = ['ID_Eleve', 'Nom', 'Classe', 'Annee', 'Periode'];
    final missing = required.where((r) => !headers.contains(r)).toList();
    final issues = <String>[];
    if (missing.isNotEmpty) {
      issues.add('En-têtes manquants: ${missing.join(', ')}');
    }
    return _ImportPreview(headers: headers, rows: rows, issues: issues);
  }

  Future<_ImportResult> _performBulkImport({
    required _ImportPreview preview,
    required void Function(int current, int total) onProgress,
    required void Function(int ok, int ko) onCounts,
    required bool skipErrors,
  }) async {
    final db = await _dbService.database;
    final total = preview.rows.length;
    int ok = 0, ko = 0, cur = 0;
    final results = <Map<String, dynamic>>[];

    // Backup simple: dupliquer tables grades + subject_appreciation + report_cards en fichiers externes non nécessaire ici (SQLite embarqué).
    // On fera transaction atomique.

    await db.transaction((txn) async {
      for (final row in preview.rows) {
        cur++;
        onProgress(cur, total);
        try {
          final map = _rowToMap(preview.headers, row);
          await _importOneRow(map, txn);
          ok++;
          results.add({'row': cur, 'status': 'ok'});
        } catch (e) {
          ko++;
          results.add({'row': cur, 'status': 'error', 'message': e.toString()});
          if (!skipErrors) {
            throw Exception(e.toString()); // abort transaction
          }
        }
        onCounts(ok, ko);
      }
    });

    // Recharger UI
    await _loadAllGradesForPeriod();
    setState(() {});
    return _ImportResult(results);
  }

  Map<String, dynamic> _rowToMap(List<String> headers, List<dynamic> row) {
    final data = <String, dynamic>{};
    for (int i = 0; i < headers.length && i < row.length; i++) {
      // Convertit les types de cellules possibles (excel) en String brut
      final dynamic cell = row[i];
      final String header = headers[i];
      String toStringCell(dynamic v) {
        if (v == null) return '';
        // excel package: CellValue types have .value
        try {
          final dynamic inner = (v as dynamic).value;
          if (inner != null) return inner.toString();
        } catch (_) {}
        return v.toString();
      }

      // Pour les colonnes texte (ID/Classe/Annee/Periode/Prof/App/MoyClasse/subject), garde en String
      data[header] = toStringCell(cell);
    }
    return data;
  }

  Future<void> _importOneRow(Map<String, dynamic> data, Transaction txn) async {
    // Champs fixes
    final String studentId = (data['ID_Eleve'] ?? '').toString();
    final String className = (data['Classe'] ?? '').toString();
    final String academicYear = (data['Annee'] ?? '').toString();
    final String term = (data['Periode'] ?? '').toString();
    if (studentId.isEmpty ||
        className.isEmpty ||
        academicYear.isEmpty ||
        term.isEmpty) {
      throw Exception('Champs requis manquants');
    }
    // Vérif élève/existence
    final st = await txn.query(
      'students',
      where: 'id = ?',
      whereArgs: [studentId],
    );
    if (st.isEmpty) {
      throw Exception("Élève introuvable: $studentId");
    }
    // Récup matières de la classe (via txn)
    final currentClass = selectedClass ?? className;
    final List<Map<String, dynamic>> subjectRows = await txn.rawQuery(
      '''
      SELECT c.* FROM courses c INNER JOIN class_courses cc ON cc.courseId = c.id WHERE cc.className = ?
    ''',
      [currentClass],
    );
    final subjectNames = subjectRows.map((m) => (m['name'] as String)).toList();

    // Scanner les colonnes matière
    for (final subject in subjectNames) {
      final devKey = 'Devoir [$subject]';
      final compKey = 'Composition [$subject]';
      final coeffDevKey = 'Coeff Devoir [$subject]';
      final coeffCompKey = 'Coeff Composition [$subject]';
      final surDevKey = 'Sur Devoir [$subject]';
      final surCompKey = 'Sur Composition [$subject]';
      final profKey = 'Prof [$subject]';
      final appKey = 'App [$subject]';
      final moyClasseKey = 'MoyClasse [$subject]';

      double? parseNum(dynamic v) {
        if (v == null) return null;
        // unwrap excel CellValue if present
        try {
          final dynamic inner = (v as dynamic).value;
          if (inner is num) return inner.toDouble();
          if (inner is String)
            return double.tryParse(inner.replaceAll(',', '.'));
        } catch (_) {}
        if (v is num) return v.toDouble();
        final s = v.toString().replaceAll(',', '.');
        return double.tryParse(s);
      }

      Future<void> upsertGrade({
        required String type,
        required String label,
        required String valueKey,
        required String coeffKey,
        required String surKey,
      }) async {
        final val = parseNum(data[valueKey]);
        if (val == null) return; // ignore empty
        if (val < 0 || val > 20) {
          throw Exception('Note invalide ($subject/$type): $val');
        }
        final coeff = parseNum(data[coeffKey]) ?? 1.0;
        final sur = parseNum(data[surKey]) ?? 20.0;
        // check existing (inclure label pour gérer plusieurs devoirs/compositions)
        final existing = await txn.query(
          'grades',
          where:
              'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ? AND type = ? AND label = ?',
          whereArgs: [
            studentId,
            className,
            academicYear,
            subject,
            term,
            type,
            label,
          ],
        );
        final courseRow = subjectRows.firstWhere(
          (r) => r['name'] == subject,
          orElse: () => <String, dynamic>{'id': ''},
        );
        final newMap = {
          'studentId': studentId,
          'className': className,
          'academicYear': academicYear,
          'subjectId': courseRow['id'] as String,
          'subject': subject,
          'term': term,
          'value': val,
          'label': label,
          'maxValue': sur,
          'coefficient': coeff,
          'type': type,
        };
        if (existing.isEmpty) {
          await txn.insert('grades', newMap);
        } else {
          await txn.update(
            'grades',
            newMap,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }

      // Import Devoir simple + séries Devoir i
      Future<void> importSeries({
        required String type,
        required String baseKey,
        required String coeffBaseKey,
        required String surBaseKey,
      }) async {
        // Base non numérotée
        await upsertGrade(
          type: type,
          label: type,
          valueKey: baseKey,
          coeffKey: coeffBaseKey,
          surKey: surBaseKey,
        );
        // Série 1..10
        for (int i = 1; i <= 10; i++) {
          final valueKey = '$type $i [$subject]';
          final coeffKey = 'Coeff $type $i [$subject]';
          final surKey = 'Sur $type $i [$subject]';
          final v = parseNum(data[valueKey]);
          if (v == null) continue;
          await upsertGrade(
            type: type,
            label: '$type $i',
            valueKey: valueKey,
            coeffKey: (data.containsKey(coeffKey) && parseNum(data[coeffKey]) != null)
                ? coeffKey
                : coeffBaseKey,
            surKey: (data.containsKey(surKey) && parseNum(data[surKey]) != null)
                ? surKey
                : surBaseKey,
          );
        }
      }

      await importSeries(
        type: 'Devoir',
        baseKey: devKey,
        coeffBaseKey: coeffDevKey,
        surBaseKey: surDevKey,
      );
      await importSeries(
        type: 'Composition',
        baseKey: compKey,
        coeffBaseKey: coeffCompKey,
        surBaseKey: surCompKey,
      );

      // Appréciations/prof
      final prof = (data[profKey] ?? '').toString();
      final app = (data[appKey] ?? '').toString();
      String moyClasse = (data[moyClasseKey] ?? '').toString();
      if (prof.isNotEmpty || app.isNotEmpty || moyClasse.isNotEmpty) {
        final existing = await txn.query(
          'subject_appreciation',
          where:
              'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
          whereArgs: [studentId, className, academicYear, subject, term],
        );
        final row = {
          'studentId': studentId,
          'className': className,
          'academicYear': academicYear,
          'subject': subject,
          'term': term,
          'professeur': prof.isNotEmpty ? prof : null,
          'appreciation': app.isNotEmpty ? app : null,
          'moyenne_classe': moyClasse.isNotEmpty ? moyClasse : null,
        };
        if (existing.isEmpty) {
          await txn.insert('subject_appreciation', row);
        } else {
          await txn.update(
            'subject_appreciation',
            row,
            where:
                'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
            whereArgs: [studentId, className, academicYear, subject, term],
          );
        }
      }

      // Calcul/MAJ de la moyenne de classe pour cette matière si non fournie
      try {
        final classSubjectGrades = await txn.query(
          'grades',
          where:
              'className = ? AND academicYear = ? AND term = ? AND subject = ?',
          whereArgs: [className, academicYear, term, subject],
        );
        double total = 0.0, coeffTotal = 0.0;
        for (final g in classSubjectGrades) {
          final double maxValue = (g['maxValue'] is int)
              ? (g['maxValue'] as int).toDouble()
              : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
          final double coefficient = (g['coefficient'] is int)
              ? (g['coefficient'] as int).toDouble()
              : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
          final double value = (g['value'] is int)
              ? (g['value'] as int).toDouble()
              : (g['value'] as num?)?.toDouble() ?? 0.0;
          if (maxValue > 0 && coefficient > 0) {
            total += ((value / maxValue) * 20) * coefficient;
            coeffTotal += coefficient;
          }
        }
        final double? classSubjectAvg = coeffTotal > 0
            ? total / coeffTotal
            : null;
        if (classSubjectAvg != null && (moyClasse.isEmpty)) {
          await txn.update(
            'subject_appreciation',
            {'moyenne_classe': classSubjectAvg.toStringAsFixed(2)},
            where:
                'studentId = ? AND className = ? AND academicYear = ? AND subject = ? AND term = ?',
            whereArgs: [studentId, className, academicYear, subject, term],
          );
        }
      } catch (_) {}
    }

    // Recalcul et sauvegarde de la synthèse du bulletin
    final studentGradesRows = await txn.query(
      'grades',
      where: 'className = ? AND academicYear = ? AND term = ?',
      whereArgs: [className, academicYear, term],
    );
    // Calcul moyenne etc. similaire au preview
    final thisStudentGrades = studentGradesRows
        .where((g) => g['studentId'] == studentId)
        .toList();
    double notes = 0, coeffs = 0;
    for (final g in thisStudentGrades) {
      final double maxValue = (g['maxValue'] is int)
          ? (g['maxValue'] as int).toDouble()
          : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
      final double coefficient = (g['coefficient'] is int)
          ? (g['coefficient'] as int).toDouble()
          : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
      final double value = (g['value'] is int)
          ? (g['value'] as int).toDouble()
          : (g['value'] as num?)?.toDouble() ?? 0.0;
      if (maxValue > 0 && coefficient > 0) {
        notes += ((value / maxValue) * 20) * coefficient;
        coeffs += coefficient;
      }
    }
    final moyenne = coeffs > 0 ? notes / coeffs : 0.0;
    final studentsRows = await txn.query(
      'students',
      where: 'className = ?',
      whereArgs: [className],
    );
    final ids = studentsRows.map((r) => r['id'] as String).toList();
    final moyennes = <double>[];
    for (final sid in ids) {
      final sg = studentGradesRows.where((g) => g['studentId'] == sid).toList();
      double n = 0, c = 0;
      for (final g in sg) {
        final double maxValue = (g['maxValue'] is int)
            ? (g['maxValue'] as int).toDouble()
            : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
        final double coefficient = (g['coefficient'] is int)
            ? (g['coefficient'] as int).toDouble()
            : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
        final double value = (g['value'] is int)
            ? (g['value'] as int).toDouble()
            : (g['value'] as num?)?.toDouble() ?? 0.0;
        if (maxValue > 0 && coefficient > 0) {
          n += ((value / maxValue) * 20) * coefficient;
          c += coefficient;
        }
      }
      moyennes.add(c > 0 ? n / c : 0.0);
    }
    moyennes.sort((a, b) => b.compareTo(a));
    final rang = moyennes.indexWhere((m) => (m - moyenne).abs() < 0.001) + 1;
    final double? moyenneGeneraleClasse = moyennes.isNotEmpty
        ? (moyennes.reduce((a, b) => a + b) / moyennes.length)
        : null;
    final double? moyenneLaPlusForte = moyennes.isNotEmpty
        ? moyennes.first
        : null;
    final double? moyenneLaPlusFaible = moyennes.isNotEmpty
        ? moyennes.last
        : null;

    // Moyennes par période (liste ordonnée de toutes les périodes de l'élève)
    final allTermsRows = await txn.query(
      'grades',
      columns: ['term'],
      where: 'studentId = ? AND className = ? AND academicYear = ?',
      whereArgs: [studentId, className, academicYear],
    );
    final termsSet = allTermsRows.map((e) => (e['term'] as String)).toSet();
    List<String> orderedTerms = termsSet.toList();
    if (orderedTerms.any((t) => t.toLowerCase().contains('semestre'))) {
      orderedTerms.sort((a, b) => a.compareTo(b));
      orderedTerms = [
        'Semestre 1',
        'Semestre 2',
      ].where((t) => termsSet.contains(t)).toList();
    } else {
      orderedTerms = [
        'Trimestre 1',
        'Trimestre 2',
        'Trimestre 3',
      ].where((t) => termsSet.contains(t)).toList();
    }
    final List<double?> moyennesParPeriode = [];
    for (final t in orderedTerms) {
      final termGrades = studentGradesRows
          .where((g) => g['studentId'] == studentId && g['term'] == t)
          .toList();
      double tn = 0, tc = 0;
      for (final g in termGrades) {
        final double maxValue = (g['maxValue'] is int)
            ? (g['maxValue'] as int).toDouble()
            : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
        final double coefficient = (g['coefficient'] is int)
            ? (g['coefficient'] as int).toDouble()
            : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
        final double value = (g['value'] is int)
            ? (g['value'] as int).toDouble()
            : (g['value'] as num?)?.toDouble() ?? 0.0;
        if (maxValue > 0 && coefficient > 0) {
          tn += ((value / maxValue) * 20) * coefficient;
          tc += coefficient;
        }
      }
      moyennesParPeriode.add(tc > 0 ? tn / tc : null);
    }

    // Moyenne annuelle (toutes périodes de l'année)
    double? moyenneAnnuelle;
    final allYearGrades = await txn.query(
      'grades',
      where: 'studentId = ? AND className = ? AND academicYear = ?',
      whereArgs: [studentId, className, academicYear],
    );
    if (allYearGrades.isNotEmpty) {
      double an = 0, ac = 0;
      for (final g in allYearGrades) {
        final double maxValue = (g['maxValue'] is int)
            ? (g['maxValue'] as int).toDouble()
            : (g['maxValue'] as num?)?.toDouble() ?? 20.0;
        final double coefficient = (g['coefficient'] is int)
            ? (g['coefficient'] as int).toDouble()
            : (g['coefficient'] as num?)?.toDouble() ?? 1.0;
        final double value = (g['value'] is int)
            ? (g['value'] as int).toDouble()
            : (g['value'] as num?)?.toDouble() ?? 0.0;
        if (maxValue > 0 && coefficient > 0) {
          an += ((value / maxValue) * 20) * coefficient;
          ac += coefficient;
        }
      }
      moyenneAnnuelle = ac > 0 ? an / ac : null;
    }

    // Mention
    String mention;
    if (moyenne >= 18)
      mention = 'EXCELLENT';
    else if (moyenne >= 16)
      mention = 'TRÈS BIEN';
    else if (moyenne >= 14)
      mention = 'BIEN';
    else if (moyenne >= 12)
      mention = 'ASSEZ BIEN';
    else if (moyenne >= 10)
      mention = 'PASSABLE';
    else
      mention = 'INSUFFISANT';
    final existingRc = await txn.query(
      'report_cards',
      where:
          'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
      whereArgs: [studentId, className, academicYear, term],
    );
    // Conserver/Mettre à jour les champs texte si déjà saisis auparavant ou importés
    Map<String, dynamic> previous = {};
    if (existingRc.isNotEmpty) {
      previous = existingRc.first;
    }
    // Lire éventuellement depuis la ligne importée si présente
    String apprGen = (data['Appreciation Generale'] ?? '').toString();
    String decision = (data['Decision'] ?? '').toString();
    String recommandations = (data['Recommandations'] ?? '').toString();
    String forces = (data['Forces'] ?? '').toString();
    String pointsDev = (data['Points a Developper'] ?? '').toString();
    String sanctions = (data['Sanctions'] ?? '').toString();

    // Assiduité (heures) depuis import si présents
    int? absJust = int.tryParse((data['Abs Justifiees'] ?? '').toString());
    int? absInj = int.tryParse((data['Abs Injustifiees'] ?? '').toString());
    int? retards = int.tryParse((data['Retards'] ?? '').toString());
    double? presence = double.tryParse(
      (data['Presence (%)'] ?? '').toString().replaceAll(',', '.'),
    );
    String conduite = (data['Conduite'] ?? '').toString();
    final rcData = {
      'studentId': studentId,
      'className': className,
      'academicYear': academicYear,
      'term': term,
      'moyenne_generale': moyenne,
      'rang': rang,
      'nb_eleves': ids.length,
      'mention': mention,
      'moyennes_par_periode': moyennesParPeriode.toString(),
      'all_terms': orderedTerms.toString(),
      'moyenne_generale_classe': moyenneGeneraleClasse,
      'moyenne_la_plus_forte': moyenneLaPlusForte,
      'moyenne_la_plus_faible': moyenneLaPlusFaible,
      'moyenne_annuelle': moyenneAnnuelle,
      'appreciation_generale': apprGen.isNotEmpty
          ? apprGen
          : previous['appreciation_generale'],
      'decision': decision.isNotEmpty ? decision : previous['decision'],
      'recommandations': recommandations.isNotEmpty
          ? recommandations
          : previous['recommandations'],
      'forces': forces.isNotEmpty ? forces : previous['forces'],
      'points_a_developper': pointsDev.isNotEmpty
          ? pointsDev
          : previous['points_a_developper'],
      'attendance_justifiee': absJust ?? previous['attendance_justifiee'],
      'attendance_injustifiee': absInj ?? previous['attendance_injustifiee'],
      'retards': retards ?? previous['retards'],
      'presence_percent': presence ?? previous['presence_percent'],
      'conduite': conduite.isNotEmpty ? conduite : previous['conduite'],
      'sanctions': sanctions.isNotEmpty ? sanctions : previous['sanctions'],
    };
    if (existingRc.isEmpty) {
      await txn.insert('report_cards', rcData);
    } else {
      await txn.update(
        'report_cards',
        rcData,
        where:
            'studentId = ? AND className = ? AND academicYear = ? AND term = ?',
        whereArgs: [studentId, className, academicYear, term],
      );
    }
  }

  Future<void> _showBulkGradeDialog() async {
    if (selectedClass == null || selectedSubject == null) {
      showRootSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner une classe et une matière.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Restreindre aux élèves de l'année académique en cours de saisie
    String? classYear;
    if (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty) {
      classYear = selectedAcademicYear;
    } else {
      classYear = classes
          .firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          )
          .academicYear;
    }
    final String effectiveYear = (classYear != null && classYear.isNotEmpty)
        ? classYear
        : academicYearNotifier.value;
    debugPrint(
      '[GradesPage] Saisie Rapide -> class=$selectedClass subject=$selectedSubject term=$selectedTerm year=$effectiveYear',
    );
    final classStudents = await _dbService.getStudents(
      className: selectedClass!,
      academicYear: effectiveYear,
    );
    // Charger le coefficient de la matière au niveau de la classe (détails de la classe)
    final Map<String, double> classWeights = await _dbService
        .getClassSubjectCoefficients(selectedClass!, effectiveYear);
    final double? subjectWeight = selectedSubject != null
        ? classWeights[selectedSubject!]
        : null;
    debugPrint(
      '[GradesPage] Saisie Rapide -> students.count=${classStudents.length}',
    );
    final Map<String, TextEditingController> devoirControllers = {
      for (var student in classStudents)
        student.id: TextEditingController(
          text: grades
              .firstWhere(
                (g) =>
                    g.studentId == student.id &&
                    g.subject == selectedSubject &&
                    g.type == 'Devoir',
                orElse: () => Grade.empty(),
              )
              .value
              .toString(),
        ),
    };
    final Map<String, TextEditingController> compositionControllers = {
      for (var student in classStudents)
        student.id: TextEditingController(
          text: grades
              .firstWhere(
                (g) =>
                    g.studentId == student.id &&
                    g.subject == selectedSubject &&
                    g.type == 'Composition',
                orElse: () => Grade.empty(),
              )
              .value
              .toString(),
        ),
    };
    // Plus de saisie directe du coefficient d'évaluation ici
    final Map<String, TextEditingController> maxControllers = {
      for (var student in classStudents)
        student.id: TextEditingController(
          text: grades
              .firstWhere(
                (g) =>
                    g.studentId == student.id && g.subject == selectedSubject,
                orElse: () => Grade.empty(),
              )
              .maxValue
              .toString(),
        ),
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: AppColors.primaryBlue),
                  const SizedBox(width: 10),
                  Text(
                    'Saisie Rapide - ${selectedSubject!}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(width: 12),
                  if (subjectWeight != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Text(
                        'Coeff. matière: ${subjectWeight.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
        content: Container(
          width: MediaQuery.of(context).size.width * 0.7,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subjectWeight != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Coeff. matière (classe): ' +
                          subjectWeight.toStringAsFixed(2),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(1),
                  },
                  border: TableBorder.all(
                    color: Theme.of(context).dividerColor,
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Élève',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Devoir',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Composition',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Sur',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    ...classStudents.map((student) {
                      return TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              '${student.firstName} ${student.lastName}'.trim(),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextFormField(
                              controller: devoirControllers[student.id],
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextFormField(
                              controller: compositionControllers[student.id],
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextFormField(
                              controller: maxControllers[student.id],
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              for (var student in classStudents) {
                final devoirNote = double.tryParse(
                  devoirControllers[student.id]!.text,
                );
                final compositionNote = double.tryParse(
                  compositionControllers[student.id]!.text,
                );
                final max = double.tryParse(maxControllers[student.id]!.text);
                final existingDevoir = grades.firstWhere(
                  (g) =>
                      g.studentId == student.id &&
                      g.subject == selectedSubject &&
                      g.type == 'Devoir',
                  orElse: () => Grade.empty(),
                );
                final existingCompo = grades.firstWhere(
                  (g) =>
                      g.studentId == student.id &&
                      g.subject == selectedSubject &&
                      g.type == 'Composition',
                  orElse: () => Grade.empty(),
                );
                final double coeffDevoir = existingDevoir.id != null
                    ? existingDevoir.coefficient
                    : 1.0;
                final double coeffCompo = existingCompo.id != null
                    ? existingCompo.coefficient
                    : 1.0;

                if (devoirNote != null) {
                  await _saveGrade(
                    student,
                    'Devoir',
                    devoirNote,
                    coeffDevoir,
                    max ?? 20.0,
                  );
                }
                if (compositionNote != null) {
                  await _saveGrade(
                    student,
                    'Composition',
                    compositionNote,
                    coeffCompo,
                    max ?? 20.0,
                  );
                }
              }
              await _loadAllGradesForPeriod();
              Navigator.of(context).pop();
              showRootSnackBar(
                const SnackBar(
                  content: Text('Notes enregistrées avec succès.'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('Tout Enregistrer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveGrade(
    Student student,
    String type,
    double value,
    double coefficient,
    double maxValue,
  ) async {
    final course = subjects.firstWhere(
      (c) => c.name == selectedSubject,
      orElse: () => Course.empty(),
    );
    Grade? grade;
    try {
      grade = grades.firstWhere(
        (g) =>
            g.studentId == student.id &&
            g.subject == selectedSubject &&
            g.type == type,
      );
    } catch (_) {
      grade = null;
    }

    final newGrade = Grade(
      id: grade?.id,
      studentId: student.id,
      className: selectedClass!,
      academicYear: selectedAcademicYear!,
      subjectId: course.id,
      subject: selectedSubject!,
      term: selectedTerm!,
      value: value,
      label: grade?.label ?? type,
      type: type,
      coefficient: coefficient,
      maxValue: maxValue,
    );
    if (grade == null) {
      await _dbService.insertGrade(newGrade);
    } else {
      await _dbService.updateGrade(newGrade);
    }
  }

  Future<Map<String, dynamic>> _prepareReportCardData(Student student) async {
    final info = await loadSchoolInfo();
    final String effectiveYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : (selectedClass != null
              ? (classes
                    .firstWhere(
                      (c) => c.name == selectedClass,
                      orElse: () => Class.empty(),
                    )
                    .academicYear)
              : academicYearNotifier.value);
    final schoolYear = effectiveYear;
    final periodLabel = _periodMode == 'Trimestre' ? 'Trimestre' : 'Semestre';
    final studentGrades = grades
        .where(
          (g) =>
              g.studentId == student.id &&
              g.className == selectedClass &&
              g.academicYear == effectiveYear &&
              g.term == selectedTerm,
        )
        .toList();
    final subjectNames = subjects.map((c) => c.name).toList();

    // Charger coefficients de matières définis au niveau de la classe
    final Map<String, double> subjectWeights = await _dbService
        .getClassSubjectCoefficients(selectedClass!, effectiveYear);
    // --- Moyennes par période ---
    final List<String> allTerms = _periodMode == 'Trimestre'
        ? ['Trimestre 1', 'Trimestre 2', 'Trimestre 3']
        : ['Semestre 1', 'Semestre 2'];
    final List<double?> moyennesParPeriode = [];
    // Pour le calcul annuel, on agrégera toutes les notes des périodes
    double totalAnnualPoints = 0.0;
    double totalAnnualWeights = 0.0;
    // Pour la moyenne annuelle de la classe et le rang annuel
    final Map<String, double> nAnnualByStudent = {};
    final Map<String, double> cAnnualByStudent = {};
    for (final term in allTerms) {
      // Charger toutes les notes de la classe pour la période, puis filtrer l'élève
      final periodGrades = await _dbService.getAllGradesForPeriod(
        className: selectedClass!,
        academicYear: effectiveYear,
        term: term,
      );
      // Calcul pondéré par matière pour l'élève
      double sumPts = 0.0;
      double sumW = 0.0;
      for (final subject in subjectNames) {
        final sg = periodGrades
            .where(
              (g) =>
                  g.studentId == student.id &&
                  g.subject == subject &&
                  (g.type == 'Devoir' || g.type == 'Composition') &&
                  g.value != null &&
                  g.value != 0,
            )
            .toList();
        if (sg.isEmpty) continue;
        double n = 0.0;
        double c = 0.0;
        for (final g in sg) {
          if (g.maxValue > 0 && g.coefficient > 0) {
            n += ((g.value / g.maxValue) * 20) * g.coefficient;
            c += g.coefficient;
          }
        }
        final double moyM = c > 0 ? (n / c) : 0.0;
        final double w = subjectWeights[subject] ?? c;
        if (w > 0) {
          sumPts += moyM * w;
          sumW += w;
        }
      }
      moyennesParPeriode.add(sumW > 0 ? (sumPts / sumW) : null);
      // Agrégation annuelle pondérée
      totalAnnualPoints += sumPts;
      totalAnnualWeights += sumW;
      // Agréger pour la classe (par élève) pour l'annuel
      for (final g in periodGrades.where(
        (g) =>
            (g.type == 'Devoir' || g.type == 'Composition') &&
            g.value != null &&
            g.value != 0,
      )) {
        if (g.maxValue > 0 && g.coefficient > 0) {
          nAnnualByStudent[g.studentId] =
              (nAnnualByStudent[g.studentId] ?? 0) +
              ((g.value / g.maxValue) * 20) * g.coefficient;
          cAnnualByStudent[g.studentId] =
              (cAnnualByStudent[g.studentId] ?? 0) + g.coefficient;
        }
      }
    }

    // Calcul de la moyenne générale pondérée par coefficients de matières (période sélectionnée)
    double sumPtsSel = 0.0;
    double sumWSel = 0.0;
    for (final subject in subjectNames) {
      final sg = studentGrades
          .where(
            (g) =>
                g.subject == subject &&
                (g.type == 'Devoir' || g.type == 'Composition') &&
                g.value != null &&
                g.value != 0,
          )
          .toList();
      if (sg.isEmpty) continue;
      double n = 0.0;
      double c = 0.0;
      for (final g in sg) {
        if (g.maxValue > 0 && g.coefficient > 0) {
          n += ((g.value / g.maxValue) * 20) * g.coefficient;
          c += g.coefficient;
        }
      }
      final double moyM = c > 0 ? (n / c) : 0.0;
      final double w = subjectWeights[subject] ?? c;
      if (w > 0) {
        sumPtsSel += moyM * w;
        sumWSel += w;
      }
    }
    final moyenneGenerale = sumWSel > 0 ? (sumPtsSel / sumWSel) : 0.0;

    // Calcul de la moyenne annuelle (toutes périodes de l'année)
    double? moyenneAnnuelle;
    if (totalAnnualWeights > 0) {
      moyenneAnnuelle = totalAnnualPoints / totalAnnualWeights;
    }
    // Moyenne annuelle de la classe et rang annuel
    double? moyenneAnnuelleClasse;
    int? rangAnnuel;
    if (nAnnualByStudent.isNotEmpty) {
      final List<double> annualAvgs = [];
      double myAnnual = moyenneAnnuelle ?? 0.0;
      nAnnualByStudent.forEach((sid, n) {
        final c = cAnnualByStudent[sid] ?? 0.0;
        final avg = c > 0 ? (n / c) : 0.0;
        annualAvgs.add(avg);
        if (sid == student.id) myAnnual = avg;
      });
      if (annualAvgs.isNotEmpty) {
        moyenneAnnuelleClasse =
            annualAvgs.reduce((a, b) => a + b) / annualAvgs.length;
        annualAvgs.sort((a, b) => b.compareTo(a));
        rangAnnuel = 1 + annualAvgs.where((v) => v > myAnnual + 0.001).length;
      }
    }

    // Calcul du rang et statistiques de classe (effectif basé sur l'année en cours uniquement)
    // Strict effectif: class academicYear must match (guard against student rows with mismatched year)
    final currentClassStudents = await _dbService
        .getStudentsByClassAndClassYear(selectedClass!, effectiveYear);
    final classStudentIds = currentClassStudents.map((s) => s.id).toList();
    final List<double> allMoyennes = classStudentIds.map((sid) {
      final sg = grades
          .where(
            (g) =>
                g.studentId == sid &&
                g.className == selectedClass &&
                g.academicYear == effectiveYear &&
                g.term == selectedTerm &&
                (g.type == 'Devoir' || g.type == 'Composition') &&
                g.value != null &&
                g.value != 0,
          )
          .toList();
      double pts = 0.0;
      double wsum = 0.0;
      for (final subject in subjectNames) {
        final sl = sg.where((g) => g.subject == subject).toList();
        if (sl.isEmpty) continue;
        double n = 0.0;
        double c = 0.0;
        for (final g in sl) {
          if (g.maxValue > 0 && g.coefficient > 0) {
            n += ((g.value / g.maxValue) * 20) * g.coefficient;
            c += g.coefficient;
          }
        }
        final double moyM = c > 0 ? (n / c) : 0.0;
        final double w = subjectWeights[subject] ?? c;
        if (w > 0) {
          pts += moyM * w;
          wsum += w;
        }
      }
      return wsum > 0 ? (pts / wsum) : 0.0;
    }).toList();
    allMoyennes.sort((a, b) => b.compareTo(a));
    const double eps = 0.001;
    final rang =
        allMoyennes.indexWhere((m) => (m - moyenneGenerale).abs() < eps) + 1;
    final int tiesCount = allMoyennes
        .where((m) => (m - moyenneGenerale).abs() < eps)
        .length;
    final bool isExAequo = tiesCount > 1;
    final int nbEleves = classStudentIds.length;
    final double? moyenneGeneraleDeLaClasse = allMoyennes.isNotEmpty
        ? allMoyennes.reduce((a, b) => a + b) / allMoyennes.length
        : null;
    final double? moyenneLaPlusForte = allMoyennes.isNotEmpty
        ? allMoyennes.reduce((a, b) => a > b ? a : b)
        : null;
    final double? moyenneLaPlusFaible = allMoyennes.isNotEmpty
        ? allMoyennes.reduce((a, b) => a < b ? a : b)
        : null;

    // Mention
    String mention;
    if (moyenneGenerale >= 18) {
      mention = 'EXCELLENT';
    } else if (moyenneGenerale >= 16) {
      mention = 'TRÈS BIEN';
    } else if (moyenneGenerale >= 14) {
      mention = 'BIEN';
    } else if (moyenneGenerale >= 12) {
      mention = 'ASSEZ BIEN';
    } else if (moyenneGenerale >= 10) {
      mention = 'PASSABLE';
    } else {
      mention = 'INSUFFISANT';
    }

    // Décision automatique du conseil de classe basée sur la moyenne annuelle
    // Ne s'affiche qu'en fin d'année (Trimestre 3 ou Semestre 2)
    String? decisionAutomatique;
    final bool isEndOfYear =
        selectedTerm == 'Trimestre 3' || selectedTerm == 'Semestre 2';

    if (isEndOfYear) {
      if (moyenneAnnuelle != null) {
        if (moyenneAnnuelle >= 16) {
          decisionAutomatique = 'Admis en classe supérieure avec félicitations';
        } else if (moyenneAnnuelle >= 14) {
          decisionAutomatique =
              'Admis en classe supérieure avec encouragements';
        } else if (moyenneAnnuelle >= 12) {
          decisionAutomatique = 'Admis en classe supérieure';
        } else if (moyenneAnnuelle >= 10) {
          decisionAutomatique = 'Admis en classe supérieure avec avertissement';
        } else if (moyenneAnnuelle >= 8) {
          decisionAutomatique = 'Admis en classe supérieure sous conditions';
        } else {
          decisionAutomatique = 'Redouble la classe';
        }
      } else {
        // Fallback sur la moyenne générale si pas de moyenne annuelle
        if (moyenneGenerale >= 16) {
          decisionAutomatique = 'Admis en classe supérieure avec félicitations';
        } else if (moyenneGenerale >= 14) {
          decisionAutomatique =
              'Admis en classe supérieure avec encouragements';
        } else if (moyenneGenerale >= 12) {
          decisionAutomatique = 'Admis en classe supérieure';
        } else if (moyenneGenerale >= 10) {
          decisionAutomatique = 'Admis en classe supérieure avec avertissement';
        } else if (moyenneGenerale >= 8) {
          decisionAutomatique = 'Admis en classe supérieure sous conditions';
        } else {
          decisionAutomatique = 'Redouble la classe';
        }
      }
    }

    return {
      'student': student,
      'schoolInfo': info,
      'grades': studentGrades,
      'subjects': subjectNames,
      'moyennesParPeriode': moyennesParPeriode,
      'moyenneGenerale': moyenneGenerale,
      'rang': rang,
      'exaequo': isExAequo,
      'nbEleves': nbEleves,
      'mention': mention,
      'allTerms': allTerms,
      'periodLabel': periodLabel,
      'selectedTerm': selectedTerm ?? '',
      'academicYear': schoolYear,
      'niveau': schoolLevelNotifier.value,
      'moyenneGeneraleDeLaClasse': moyenneGeneraleDeLaClasse,
      'moyenneLaPlusForte': moyenneLaPlusForte,
      'moyenneLaPlusFaible': moyenneLaPlusFaible,
      'moyenneAnnuelle': moyenneAnnuelle,
      'moyenneAnnuelleClasse': moyenneAnnuelleClasse,
      'rangAnnuel': rangAnnuel,
      'decisionAutomatique': decisionAutomatique,
    };
  }

  Future<void> _exportClassReportCards() async {
    if (selectedClass == null || selectedClass!.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Veuillez sélectionner une classe.')),
      );
      return;
    }

    // Restreindre à l'année académique effective (sélectionnée ou année courante)
    final String effectiveYear =
        (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
        ? selectedAcademicYear!
        : academicYearNotifier.value;
    debugPrint(
      '[GradesPage] Export ZIP -> class=$selectedClass term=$selectedTerm year=$effectiveYear',
    );
    final studentsInClass = await _dbService.getStudents(
      className: selectedClass!,
      academicYear: effectiveYear,
    );
    debugPrint(
      '[GradesPage] Export ZIP -> students.count=${studentsInClass.length}',
    );
    if (studentsInClass.isEmpty) {
      showRootSnackBar(
        SnackBar(content: Text('Aucun élève dans cette classe.')),
      );
      return;
    }

    // Choix de l'orientation (harmonise avec export unitaire)
    final orientation =
        await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Orientation du PDF'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Portrait'),
                  leading: const Icon(Icons.stay_current_portrait),
                  onTap: () => Navigator.of(context).pop('portrait'),
                ),
                ListTile(
                  title: const Text('Paysage'),
                  leading: const Icon(Icons.stay_current_landscape),
                  onTap: () => Navigator.of(context).pop('landscape'),
                ),
              ],
            ),
          ),
        ) ??
        'portrait';
    final bool isLandscape = orientation == 'landscape';

    showRootSnackBar(
      SnackBar(content: Text('Génération des bulletins en cours...')),
    );

    final archive = Archive();

    // Validation minimale: les coefficients de matières doivent totaliser > 0
    if (studentsInClass.isNotEmpty) {
      final coeffs = await _dbService.getClassSubjectCoefficients(
        selectedClass!,
        effectiveYear,
      );
      double sumWeights = 0.0;
      coeffs.forEach((_, v) {
        sumWeights += v;
      });
      if (sumWeights <= 0) {
        showRootSnackBar(
          SnackBar(
            content: Text(
              'Coefficients de matières invalides (somme ≤ 0). Veuillez les définir pour la classe.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    for (final student in studentsInClass) {
      final data = await _prepareReportCardData(student);
      // Récupérer appréciations/professeurs/moyenne_classe enregistrées
      final subjectNames = data['subjects'] as List<String>;
      final subjectApps = await _dbService.getSubjectAppreciations(
        studentId: student.id,
        className: selectedClass!,
        academicYear: effectiveYear,
        term: selectedTerm!,
      );
      final professeurs = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final appreciations = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final moyennesClasse = <String, String>{
        for (final s in subjectNames) s: '-',
      };
      final coefficients = <String, double>{};
      for (final row in subjectApps) {
        final subject = row['subject'] as String?;
        if (subject != null) {
          professeurs[subject] =
              (row['professeur'] as String?)?.trim().isNotEmpty == true
              ? row['professeur'] as String
              : '-';
          appreciations[subject] =
              (row['appreciation'] as String?)?.trim().isNotEmpty == true
              ? row['appreciation'] as String
              : '-';
          moyennesClasse[subject] =
              (row['moyenne_classe'] as String?)?.trim().isNotEmpty == true
              ? row['moyenne_classe'] as String
              : '-';
          final num? c = row['coefficient'] as num?;
          if (c != null) coefficients[subject] = c.toDouble();
        }
      }
      // Synthèse générale depuis report_cards
      final rc = await _dbService.getReportCard(
        studentId: student.id,
        className: selectedClass!,
        academicYear: selectedAcademicYear!,
        term: selectedTerm!,
      );
      final appreciationGenerale =
          rc?['appreciation_generale'] as String? ?? '';
      final decision = rc?['decision'] as String? ?? '';
      final recommandations = rc?['recommandations'] as String? ?? '';
      final forces = rc?['forces'] as String? ?? '';
      final pointsADevelopper = rc?['points_a_developper'] as String? ?? '';
      final sanctions = rc?['sanctions'] as String? ?? '';
      final attendanceJustifiee = (rc?['attendance_justifiee'] as int?) ?? 0;
      final attendanceInjustifiee =
          (rc?['attendance_injustifiee'] as int?) ?? 0;
      final retards = (rc?['retards'] as int?) ?? 0;
      final num? presenceNum = rc?['presence_percent'] as num?;
      final presencePercent = presenceNum?.toDouble() ?? 0.0;
      final conduite = rc?['conduite'] as String? ?? '';
      final faitA = rc?['fait_a'] as String? ?? '';
      final leDate = rc?['le_date'] as String? ?? '';
      final String faitAEff = faitA.trim().isNotEmpty
          ? faitA.trim()
          : (data['schoolInfo'].address as String? ?? '');
      final String leDateEff = DateFormat('dd/MM/yyyy').format(DateTime.now());

      // Ensure professor fallback from staff/titulaire if not saved
      for (final subject in subjectNames) {
        if ((professeurs[subject] ?? '-').trim().isEmpty ||
            professeurs[subject] == '-') {
          final courseObj = subjects.firstWhere(
            (c) => c.name == subject,
            orElse: () => Course.empty(),
          );
          bool teachesSubject(Staff s) {
            final crs = s.courses;
            final cls = s.classes;
            final matchCourse =
                crs.contains(courseObj.id) ||
                crs.any((x) => x.toLowerCase() == subject.toLowerCase());
            final matchClass = cls.contains(selectedClass);
            return matchCourse && matchClass;
          }

          final teacher = staff.firstWhere(
            (s) => teachesSubject(s),
            orElse: () => Staff.empty(),
          );
          if (teacher.id.isNotEmpty) {
            professeurs[subject] = teacher.name;
          } else {
            final currentClass = classes.firstWhere(
              (c) => c.name == selectedClass,
              orElse: () => Class.empty(),
            );
            if ((currentClass.titulaire ?? '').isNotEmpty) {
              professeurs[subject] = currentClass.titulaire!;
            }
          }
        }
      }
      final currentClass = classes.firstWhere(
        (c) => c.name == selectedClass,
        orElse: () => Class.empty(),
      );
      final pdfBytes = await PdfService.generateReportCardPdf(
        student: data['student'],
        schoolInfo: data['schoolInfo'],
        grades: data['grades'],
        professeurs: professeurs,
        appreciations: appreciations,
        moyennesClasse: moyennesClasse,
        appreciationGenerale: appreciationGenerale,
        decision: decision,
        recommandations: recommandations,
        forces: forces,
        pointsADevelopper: pointsADevelopper,
        sanctions: sanctions,
        attendanceJustifiee: attendanceJustifiee,
        attendanceInjustifiee: attendanceInjustifiee,
        retards: retards,
        presencePercent: presencePercent,
        conduite: conduite,
        telEtab: data['schoolInfo'].telephone ?? '',
        mailEtab: data['schoolInfo'].email ?? '',
        webEtab: data['schoolInfo'].website ?? '',
        titulaire: currentClass.titulaire ?? '',
        subjects: data['subjects'],
        moyennesParPeriode: data['moyennesParPeriode'],
        moyenneGenerale: data['moyenneGenerale'],
        rang: data['rang'],
        exaequo: (data['exaequo'] as bool?) ?? false,
        nbEleves: data['nbEleves'],
        mention: data['mention'],
        allTerms: data['allTerms'],
        periodLabel: data['periodLabel'],
        selectedTerm: data['selectedTerm'],
        academicYear: data['academicYear'],
        faitA: faitAEff,
        leDate: leDateEff,
        isLandscape: isLandscape,
        niveau: data['niveau'],
        moyenneGeneraleDeLaClasse: data['moyenneGeneraleDeLaClasse'],
        moyenneLaPlusForte: data['moyenneLaPlusForte'],
        moyenneLaPlusFaible: data['moyenneLaPlusFaible'],
        moyenneAnnuelle: data['moyenneAnnuelle'],
      );
      // Use student ID to ensure unique filenames even if names collide
      final safeName = '${student.firstName}_${student.lastName}'.replaceAll(' ', '_');
      final safeId = student.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      final fileName =
          'Bulletin_${safeName}_${safeId}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.pdf';
      debugPrint(
        '[GradesPage] Export ZIP -> adding $fileName (${pdfBytes.length} bytes)',
      );
      archive.addFile(ArchiveFile(fileName, pdfBytes.length, pdfBytes));

      // Archive the report card snapshot for this student/period
      try {
        final String effectiveYear =
            (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty)
            ? selectedAcademicYear!
            : academicYearNotifier.value;
        final gradesForPeriod = (data['grades'] as List<Grade>?) ?? [];
        await _dbService.archiveSingleReportCard(
          studentId: student.id,
          className: selectedClass!,
          academicYear: effectiveYear,
          term: selectedTerm!,
          grades: gradesForPeriod,
          professeurs: professeurs,
          appreciations: appreciations,
          moyennesClasse: moyennesClasse,
          synthese: {
            'appreciation_generale': appreciationGenerale,
            'decision': decision,
            'recommandations': recommandations,
            'forces': forces,
            'points_a_developper': pointsADevelopper,
            'fait_a': faitA,
            'le_date': leDate,
            'moyenne_generale': data['moyenneGenerale'],
            'rang': data['rang'],
            'nb_eleves': data['nbEleves'],
            'mention': data['mention'],
            'moyennes_par_periode': data['moyennesParPeriode'].toString(),
            'all_terms': data['allTerms'].toString(),
            'moyenne_generale_classe': data['moyenneGeneraleDeLaClasse'],
            'moyenne_la_plus_forte': data['moyenneLaPlusForte'],
            'moyenne_la_plus_faible': data['moyenneLaPlusFaible'],
            'moyenne_annuelle': data['moyenneAnnuelle'],
            'sanctions': sanctions,
            'attendance_justifiee': attendanceJustifiee,
            'attendance_injustifiee': attendanceInjustifiee,
            'retards': retards,
            'presence_percent': presencePercent,
            'conduite': conduite,
            'coefficients': coefficients,
          },
        );
      } catch (e) {
        debugPrint(
          '[GradesPage] Export ZIP -> archiveSingleReportCard failed for ${student.id}: $e',
        );
      }
    }

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    if (zipBytes == null) {
      showRootSnackBar(
        SnackBar(content: Text('Erreur lors de la création du fichier ZIP.')),
      );
      return;
    }

    String? directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choisir le dossier de sauvegarde',
    );
    if (directoryPath != null) {
      final fileName =
          'Bulletins_${selectedClass!.replaceAll(' ', '_')}_${selectedTerm ?? ''}_${selectedAcademicYear ?? ''}.zip';
      final file = File('$directoryPath/$fileName');
      await file.writeAsBytes(zipBytes);
      showRootSnackBar(
        SnackBar(
          content: Text('Bulletins exportés dans $directoryPath'),
          backgroundColor: Colors.green,
        ),
      );
      try {
        final u = await AuthService.instance.getCurrentUser();
        await _dbService.logAudit(
          category: 'report_card',
          action: 'export_report_cards',
          username: u?.username,
          details:
              'class=$selectedClass year=$selectedAcademicYear term=$selectedTerm count=${studentsInClass.length} file=$fileName',
        );
      } catch (_) {}
    }
  }

  void _showEditStudentGradesDialog(Student student) async {
    final List<String> subjectNames = subjects.map((c) => c.name).toList();
    // Charger les coefficients de matières définis dans les détails de la classe pour l'année en cours
    String effYear;
    if (selectedAcademicYear != null && selectedAcademicYear!.isNotEmpty) {
      effYear = selectedAcademicYear!;
    } else {
      effYear = classes
          .firstWhere(
            (c) => c.name == selectedClass,
            orElse: () => Class.empty(),
          )
          .academicYear;
      if (effYear.isEmpty) effYear = academicYearNotifier.value;
    }
    final Map<String, double> classSubjectWeights = await _dbService
        .getClassSubjectCoefficients(selectedClass!, effYear);
    // Récupère toutes les notes de l'élève pour la période sélectionnée directement depuis la base
    List<Grade> allGradesForPeriod = await _dbService.getAllGradesForPeriod(
      className: selectedClass!,
      academicYear: selectedAcademicYear!,
      term: selectedTerm!,
    );
    // Nouvelle structure : pour chaque matière, pour chaque type, liste de notes
    final types = ['Devoir', 'Composition'];
    Map<String, Map<String, List<Grade>>> subjectTypeGrades = {};
    for (final subject in subjectNames) {
      subjectTypeGrades[subject] = {};
      for (final type in types) {
        subjectTypeGrades[subject]![type] = allGradesForPeriod
            .where(
              (g) =>
                  g.studentId == student.id &&
                  g.subject == subject &&
                  g.type == type,
            )
            .toList();
        // Si aucune note, on ajoute une note vide par défaut pour la saisie
        if (subjectTypeGrades[subject]![type]!.isEmpty) {
          final course = subjects.firstWhere(
            (c) => c.name == subject,
            orElse: () => Course.empty(),
          );
          subjectTypeGrades[subject]![type] = [
            Grade(
              id: null,
              studentId: student.id,
              className: selectedClass!,
              academicYear: selectedAcademicYear!,
              subjectId: course.id,
              subject: subject,
              term: selectedTerm!,
              value: 0,
              label: subject,
              maxValue: 20,
              coefficient: 1,
              type: type,
            ),
          ];
        }
      }
    }
    // Contrôleurs pour chaque note (clé : subject-type-index)
    final Map<String, TextEditingController> valueControllers = {};
    final Map<String, TextEditingController> labelControllers = {};
    final Map<String, TextEditingController> maxValueControllers = {};
    // Coefficients d'évaluation non éditables dans ce formulaire
    subjectTypeGrades.forEach((subject, typeMap) {
      typeMap.forEach((type, gradesList) {
        for (int i = 0; i < gradesList.length; i++) {
          final key = '$subject-$type-$i';
          valueControllers[key] = TextEditingController(
            text: gradesList[i].value.toString(),
          );
          labelControllers[key] = TextEditingController(
            text: gradesList[i].label ?? subject,
          );
          maxValueControllers[key] = TextEditingController(
            text: gradesList[i].maxValue.toString(),
          );
        }
      });
    });

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Icon(Icons.edit, color: AppColors.primaryBlue),
                    const SizedBox(width: 10),
                    Text(
                      'Notes de ${student.firstName} ${student.lastName}'.trim(),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
          content: Container(
            width: MediaQuery.of(context).size.width * 0.6,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: subjectNames.map((subject) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ExpansionTile(
                      leading: const Icon(
                        Icons.subject,
                        color: AppColors.primaryBlue,
                      ),
                      title: Text(
                        subject,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      subtitle: Text(
                        'Coeff. matière (classe): ' +
                            ((classSubjectWeights[subject] != null)
                                ? classSubjectWeights[subject]!.toStringAsFixed(
                                    2,
                                  )
                                : '-'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      children: types.map((type) {
                        final gradesList = subjectTypeGrades[subject]![type]!;
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                type,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Divider(),
                              ...List.generate(gradesList.length, (i) {
                                final key = '$subject-$type-$i';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: labelControllers[key],
                                          decoration: const InputDecoration(
                                            labelText: 'Nom de la note',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          controller: valueControllers[key],
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
                                            labelText: 'Note',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          controller: maxValueControllers[key],
                                          keyboardType:
                                              TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
                                            labelText: 'Sur',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      // Coefficient supprimé de l'édition ici
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                for (final subject in subjectNames) {
                  for (final type in types) {
                    final gradesList = subjectTypeGrades[subject]![type]!;
                    for (int i = 0; i < gradesList.length; i++) {
                      final key = '$subject-$type-$i';
                      final value = double.tryParse(
                        valueControllers[key]!.text,
                      );
                      final maxValue = double.tryParse(
                        maxValueControllers[key]!.text,
                      );
                      final coefficient = gradesList[i].coefficient;
                      final label = labelControllers[key]!.text;

                      if (value != null) {
                        final course = subjects.firstWhere(
                          (c) => c.name == subject,
                          orElse: () => Course.empty(),
                        );
                        final newGrade = Grade(
                          id: gradesList[i].id,
                          studentId: student.id,
                          className: selectedClass!,
                          academicYear: selectedAcademicYear!,
                          subjectId: course.id,
                          subject: subject,
                          term: selectedTerm!,
                          value: value,
                          label: label,
                          maxValue: maxValue ?? 20,
                          coefficient: (coefficient == 0 || coefficient.isNaN)
                              ? 1
                              : coefficient,
                          type: type,
                        );
                        if (newGrade.id == null) {
                          await _dbService.insertGrade(newGrade);
                        } else {
                          await _dbService.updateGrade(newGrade);
                        }
                      }
                    }
                  }
                }
                await _loadAllGradesForPeriod();
                Navigator.of(context).pop();
                showRootSnackBar(
                  const SnackBar(
                    content: Text('Notes enregistrées avec succès.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _isDarkMode ? _buildDarkTheme() : _buildLightTheme();
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: _isDarkMode ? Colors.black : Colors.grey[100],
        body: Column(
          children: [
            _buildHeader(context, _isDarkMode, isDesktop),
            const SizedBox(height: 16),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGradeInputTab(),
                  _buildReportCardsTab(),
                  _buildArchiveTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
