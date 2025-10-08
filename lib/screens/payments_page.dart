import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:docx_template/docx_template.dart';

import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/screens/dashboard_home.dart';
// import removed: grades page not needed here
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:open_file/open_file.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/screens/students/student_profile_page.dart';
// import removed: duplicate and unused
import 'package:school_manager/services/auth_service.dart';

class PaymentsPage extends StatefulWidget {
  @override
  _PaymentsPageState createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final DatabaseService _dbService = DatabaseService();
  List<Payment> _payments = [];
  Map<String, Student> _studentsById = {};
  Map<String, Class> _classesByName = {};
  bool _isLoading = true;
  int _currentPage = 0;
  static const int _rowsPerPage = 10;
  String? _selectedClassFilter;
  String? _selectedYearFilter;
  String? _selectedGenderFilter;
  String? _selectedStatusFilter; // null or 'annules'
  int _currentTab = 0;
  List<Payment> _cancelledPayments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index;
          _currentPage = 0;
        });
      }
    });
    academicYearNotifier.addListener(_onAcademicYearChanged);
    getCurrentAcademicYear().then((year) {
      setState(() {
        _selectedYearFilter = year;
      });
      _fetchPayments();
    });
  }

  void _onAcademicYearChanged() {
    setState(() {
      _selectedYearFilter = academicYearNotifier.value;
    });
    _fetchPayments();
  }

  Future<void> _fetchPayments() async {
    final payments = await _dbService.getAllPayments();
    final students = await _dbService.getStudents();
    final classes = await _dbService.getClasses();

    // Utiliser l'année académique courante de l'application
    final currentAcademicYear = await getCurrentAcademicYear();
    // Load cancelled for the same year
    final cancelled = await _dbService.getCancelledPaymentsForYear(currentAcademicYear);

    // Filtrer les classes pour l'année courante
    final filteredClasses = classes
        .where((c) => c.academicYear == currentAcademicYear)
        .toList();

    final studentsById = {for (var s in students) s.id: s};
    // Construire map name->Class en prenant en compte l'année académique (la clé student.className n'inclut pas l'année),
    // on garde uniquement les classes de l'année courante.
    final classesByName = {for (var c in filteredClasses) c.name: c};

    // Filtrer les paiements pour n'inclure que ceux de l'année académique courante
    final filteredPayments = payments
        .where((p) => p.classAcademicYear == currentAcademicYear)
        .toList();

    setState(() {
      _payments = filteredPayments;
      _studentsById = studentsById;
      _classesByName = classesByName;
      _cancelledPayments = cancelled;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    academicYearNotifier.removeListener(_onAcademicYearChanged);
    super.dispose();
  }

  List<Map<String, dynamic>> get allRows {
    // Associe chaque élève à son dernier paiement (ou null si aucun)
    final List<Map<String, dynamic>> rows = [];
    for (final student in _studentsById.values) {
      final studentPayments = _payments
          .where((p) => p.studentId == student.id && !p.isCancelled)
          .toList();
      Payment? lastPayment;
      if (studentPayments.isNotEmpty) {
        studentPayments.sort((a, b) => b.date.compareTo(a.date));
        lastPayment = studentPayments.first;
      }
      rows.add({'student': student, 'payment': lastPayment});
    }
    return rows;
  }

  List<Map<String, dynamic>> get filteredRows {
    List<Map<String, dynamic>> rows = allRows;
    if (_selectedClassFilter != null) {
      rows = rows
          .where(
            (row) =>
                (row['student'] as Student).className == _selectedClassFilter,
          )
          .toList();
    }
    if (_selectedYearFilter != null) {
      // Filtrer à la fois par année de la classe ET année de l'élève
      final classNames = _classesByName.entries
          .where((e) => e.value.academicYear == _selectedYearFilter)
          .map((e) => e.key)
          .toSet();
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final classOk = classNames.contains(student.className);
        final studentOk = student.academicYear == _selectedYearFilter;
        return classOk && studentOk;
      }).toList();
    }
    if (_selectedGenderFilter != null) {
      rows = rows
          .where(
            (row) =>
                (row['student'] as Student).gender == _selectedGenderFilter,
          )
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final name = student.name.toLowerCase();
        final classe = student.className.toLowerCase();
        return name.contains(_searchQuery.toLowerCase()) ||
            classe.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    // Filtrage par statut via tab
    if (_currentTab == 1) {
      // Impayés (aucun paiement)
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final studentPayments = _payments
            .where((p) => p.studentId == student.id && !p.isCancelled)
            .toList();
        return studentPayments.isEmpty;
      }).toList();
    } else if (_currentTab == 2) {
      // En attente (a payé partiellement, mais pas tout)
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final classe = _classesByName[student.className];
        final montantMax =
            (classe?.fraisEcole ?? 0) + (classe?.fraisCotisationParallele ?? 0);
        final studentPayments = _payments
            .where((p) => p.studentId == student.id && !p.isCancelled)
            .toList();
        final totalPaid = studentPayments.fold<double>(
          0,
          (sum, pay) => sum + pay.amount,
        );
        return studentPayments.isNotEmpty &&
            (montantMax == 0 || totalPaid < montantMax);
      }).toList();
    } else if (_currentTab == 3) {
      // Payés
      rows = rows.where((row) {
        final student = row['student'] as Student;
        final classe = _classesByName[student.className];
        final montantMax =
            (classe?.fraisEcole ?? 0) + (classe?.fraisCotisationParallele ?? 0);
        final totalPaid = _payments
            .where((pay) => pay.studentId == student.id && !pay.isCancelled)
            .fold<double>(0, (sum, pay) => sum + pay.amount);
        return montantMax > 0 && totalPaid >= montantMax;
      }).toList();
    }
    return rows;
  }

  List<Map<String, dynamic>> get paginatedRows {
    final start = _currentPage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, filteredRows.length);
    return filteredRows.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, isDarkMode, isDesktop),
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _buildPaymentsTable(context, isDarkMode, theme),
              ),
            ],
          ),
        ),
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
                      Icons.payment_rounded,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des Paiements',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Gérez les frais de scolarité, générez des reçus et suivez les soldes impayés.',
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
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Rechercher par nom d\'étudiant ou classe',
              hintStyle: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsTable(
    BuildContext context,
    bool isDarkMode,
    ThemeData theme,
  ) {
    final totalPages = (filteredRows.length / _rowsPerPage).ceil();
    final classList = _classesByName.keys.toList()..sort();
    final yearList =
        _classesByName.values.map((c) => c.academicYear).toSet().toList()
          ..sort();
    final genderList = ['M', 'F'];
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // TabBar pour filtrer par statut
            Container(
              margin: const EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: 0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: theme.cardColor,
                        boxShadow: [
                          BoxShadow(
                            color: theme.shadowColor.withOpacity(0.1),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF6366F1).withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        tabs: const [
                          Tab(text: 'Tous'),
                          Tab(text: 'Impayés'),
                          Tab(text: 'En attente'),
                          Tab(text: 'Payés'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Boutons d'export
                  ElevatedButton.icon(
                    onPressed: () => _exportToPdf(theme),
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
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
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _exportToExcel(theme),
                    icon: const Icon(Icons.grid_on, color: Colors.white),
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
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _exportToWord(theme),
                    icon: const Icon(Icons.description, color: Colors.white),
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Filtre classe
                  DropdownButton<String?>(
                    value: _selectedClassFilter,
                    hint: Text(
                      'Classe',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Toutes les classes',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      ...classList.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c,
                          child: Text(
                            c,
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedClassFilter = value),
                    dropdownColor: theme.cardColor,
                    iconEnabledColor: theme.iconTheme.color,
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  const SizedBox(width: 16),
                  // Filtre année
                  ValueListenableBuilder<String>(
                    valueListenable: academicYearNotifier,
                    builder: (context, currentYear, _) {
                      return DropdownButton<String?>(
                        value: _selectedYearFilter,
                        hint: Text(
                          'Année',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Toutes les années',
                              style: TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                          DropdownMenuItem<String?>(
                            value: currentYear,
                            child: Text(
                              'Année courante ($currentYear)',
                              style: TextStyle(
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                          ...yearList
                              .where((y) => y != currentYear)
                              .map(
                                (y) => DropdownMenuItem<String?>(
                                  value: y,
                                  child: Text(
                                    y,
                                    style: TextStyle(
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ),
                              ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedYearFilter = value),
                        dropdownColor: theme.cardColor,
                        iconEnabledColor: theme.iconTheme.color,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  // Filtre sexe
                  DropdownButton<String?>(
                    value: _selectedGenderFilter,
                    hint: Text(
                      'Sexe',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'Tous',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'M',
                        child: Text(
                          'Garçons',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'F',
                        child: Text(
                          'Filles',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedGenderFilter = value),
                    dropdownColor: theme.cardColor,
                    iconEnabledColor: theme.iconTheme.color,
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  const SizedBox(width: 16),
                  // Filtre statut (annulés)
                  DropdownButton<String?>(
                    value: _selectedStatusFilter,
                    hint: Text(
                      'État',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Actifs'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'annules',
                        child: Text('Annulés'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _selectedStatusFilter = value),
                    dropdownColor: theme.cardColor,
                    iconEnabledColor: theme.iconTheme.color,
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            if (_selectedStatusFilter == 'annules') ...[
              _buildCancelledHeader(theme),
              Expanded(
                child: ListView.builder(
                  itemCount: _cancelledPayments.length,
                  itemBuilder: (context, i) {
                    final pay = _cancelledPayments[i];
                    final student = _studentsById[pay.studentId];
                    return _buildCancelledRow(theme, student, pay);
                  },
                ),
              ),
            ] else ...[
              _buildTableHeader(isDarkMode, theme),
              Expanded(
                child: ListView.builder(
                  itemCount: paginatedRows.length,
                  itemBuilder: (context, index) {
                    final row = paginatedRows[index];
                    final student = row['student'] as Student;
                    final payment = row['payment'] as Payment?;
                    return _buildTableRowV2(student, payment, isDarkMode, theme);
                  },
                ),
              ),
            ],
            if (totalPages > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left),
                      onPressed: _currentPage > 0
                          ? () => setState(() => _currentPage--)
                          : null,
                    ),
                    Text(
                      'Page ${_currentPage + 1} / $totalPages',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right),
                      onPressed: _currentPage < totalPages - 1
                          ? () => setState(() => _currentPage++)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(bool isDarkMode, ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('Nom de l\'Étudiant', flex: 3, theme: theme),
          _buildHeaderCell('Classe', flex: 2, theme: theme),
          _buildHeaderCell('Date de Paiement', flex: 2, theme: theme),
          _buildHeaderCell('Montant', flex: 2, theme: theme),
          _buildHeaderCell('Commentaire', flex: 3, theme: theme),
          _buildHeaderCell('Enregistré par', flex: 2, theme: theme),
          _buildHeaderCell('Statut', flex: 2, theme: theme),
          _buildHeaderCell('Action', flex: 2, theme: theme),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    String text, {
    int flex = 1,
    required ThemeData theme,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: theme.textTheme.bodyMedium?.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCancelledHeader(ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('Étudiant', flex: 3, theme: theme),
          _buildHeaderCell('Classe', flex: 2, theme: theme),
          _buildHeaderCell('Date', flex: 2, theme: theme),
          _buildHeaderCell('Montant', flex: 2, theme: theme),
          _buildHeaderCell('Motif', flex: 3, theme: theme),
          _buildHeaderCell('Annulé par', flex: 2, theme: theme),
        ],
      ),
    );
  }

  Widget _buildCancelledRow(ThemeData theme, Student? student, Payment p) {
    final studentName = student?.name ?? p.studentId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          _buildCell(studentName, flex: 3, isName: true, isDarkMode: false, theme: theme),
          _buildCell(p.className, flex: 2, isDarkMode: false, theme: theme),
          _buildCell(p.date.substring(0, 10), flex: 2, isDarkMode: false, theme: theme),
          _buildCell(p.amount.toStringAsFixed(0), flex: 2, isDarkMode: false, theme: theme),
          _buildCell(p.cancelReason ?? '-', flex: 3, isDarkMode: false, theme: theme),
          _buildCell(p.cancelBy ?? '-', flex: 2, isDarkMode: false, theme: theme),
        ],
      ),
    );
  }

  Widget _buildCell(
    String text, {
    int flex = 1,
    bool isName = false,
    required bool isDarkMode,
    required ThemeData theme,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isName ? FontWeight.w600 : FontWeight.w400,
          color: isName
              ? theme.textTheme.bodyLarge?.color
              : theme.textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  Widget _buildTableRowV2(
    Student student,
    Payment? p,
    bool isDarkMode,
    ThemeData theme,
  ) {
    final classe = _classesByName[student.className];
    final montantMax =
        (classe?.fraisEcole ?? 0) + (classe?.fraisCotisationParallele ?? 0);
    final totalPaid = _payments
        .where((pay) => pay.studentId == student.id && !pay.isCancelled)
        .fold<double>(0, (sum, pay) => sum + pay.amount);
    final bool isPaid = montantMax > 0 && totalPaid >= montantMax;
    final bool hasPayment = p != null;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _buildCell(
            student.name,
            flex: 3,
            isName: true,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            student.className,
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            hasPayment ? p!.date.replaceFirst('T', ' ').substring(0, 16) : '',
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            hasPayment ? '${p!.amount.toStringAsFixed(2)} FCFA' : '',
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            hasPayment ? (p!.comment ?? '') : '',
            flex: 3,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          _buildCell(
            hasPayment ? (p!.recordedBy ?? '-') : '',
            flex: 2,
            isDarkMode: isDarkMode,
            theme: theme,
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: isPaid
                      ? [Color(0xFF10B981), Color(0xFF059669)]
                      : [Color(0xFFEF4444), Color(0xFFDC2626)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isPaid ? Color(0xFF10B981) : Color(0xFFEF4444))
                        .withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                isPaid ? 'Payé' : (hasPayment ? 'En attente' : 'Impayé'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          _buildActionCellV2(student, p, isDarkMode, theme),
        ],
      ),
    );
  }

  Widget _buildActionCellV2(
    Student student,
    Payment? p,
    bool isDarkMode,
    ThemeData theme,
  ) {
    return Expanded(
      flex: 2,
      child: Align(
        alignment: Alignment.center,
        child: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
          onSelected: (value) async {
            if (value == 'view_recu' && p != null) {
              await _handleReceiptPdf(p, student, theme, saveOnly: false);
            } else if (value == 'save_recu' && p != null) {
              await _handleReceiptPdf(p, student, theme, saveOnly: true);
            } else if (value == 'ajouter') {
              _showAddPaymentDialog(student, theme);
            } else if (value == 'details') {
              _showStudentDetailsDialog(student, theme);
            } else if (value == 'profile') {
              showDialog(
                context: context,
                builder: (context) => StudentProfilePage(student: student),
              );
            }
          },

          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view_recu',
              enabled: p != null,
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_rounded,
                    color: p != null ? theme.colorScheme.primary : Colors.grey,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voir reçu',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'save_recu',
              enabled: p != null,
              child: Row(
                children: [
                  Icon(
                    Icons.save_alt,
                    color: p != null ? theme.colorScheme.primary : Colors.grey,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Enregistrer reçu',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'ajouter',
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    color: theme.colorScheme.secondary,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Ajouter paiement',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.onSurface,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voir détails',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  Icon(
                    Icons.person_search,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voir profil élève',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                ],
              ),
            ),
          ],
          color: theme.cardColor, // Set background color of the popup menu
        ),
      ),
    );
  }

  void _showAddPaymentDialog(Student student, ThemeData theme) async {
    final classe = _classesByName[student.className];
    final double fraisEcole = classe?.fraisEcole ?? 0;
    final double fraisCotisation = classe?.fraisCotisationParallele ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    if (montantMax == 0) {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Alerte',
          content: Text(
            'Veuillez renseigner un montant de frais d\'école ou de cotisation dans la fiche classe avant d\'enregistrer un paiement.',
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
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
          content: Text(
            'L\'élève a déjà tout payé pour cette classe.',
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
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
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          fields: const [],
          onSubmit: () => Navigator.of(context).pop(),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: 'Paiement pour ${student.name}',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Montant maximum autorisé : ${reste.toStringAsFixed(2)} FCFA',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Déjà payé : ${totalPaid.toStringAsFixed(2)} FCFA',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
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
          try {
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Paiement enregistré avec succès'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop();
            _fetchPayments();
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erreur lors de l\'enregistrement: $e'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Annuler',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final val = double.tryParse(montantController.text);
              if (val == null || val < 0) return;
              if (val > reste) {
                showMontantDepasseAlerte();
                return;
              }
              try {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Paiement enregistré avec succès'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.of(context).pop();
                _fetchPayments();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erreur lors de l\'enregistrement: $e'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            },
            child: const Text('Valider', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showStudentDetailsDialog(Student student, ThemeData theme) async {
    final classe = _classesByName[student.className];
    final double fraisEcole = classe?.fraisEcole ?? 0;
    final double fraisCotisation = classe?.fraisCotisationParallele ?? 0;
    final double montantMax = fraisEcole + fraisCotisation;
    final totalPaid = await _dbService.getTotalPaidForStudent(student.id);
    final reste = montantMax - totalPaid;
    final status = (montantMax > 0 && totalPaid >= montantMax)
        ? 'Payé'
        : 'En attente';
    final payments = await _dbService.getPaymentsForStudent(student.id);
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
              _buildDetailRow('Nom complet', student.name, theme),
              _buildDetailRow('ID', student.id, theme),
              _buildDetailRow('Date de naissance', student.dateOfBirth, theme),
              _buildDetailRow(
                'Sexe',
                student.gender == 'M' ? 'Garçon' : 'Fille',
                theme,
              ),
              _buildDetailRow('Classe', student.className, theme),
              _buildDetailRow('Adresse', student.address, theme),
              _buildDetailRow('Contact', student.contactNumber, theme),
              _buildDetailRow('Email', student.email, theme),
              _buildDetailRow(
                'Contact d\'urgence',
                student.emergencyContact,
                theme,
              ),
              _buildDetailRow('Tuteur', student.guardianName, theme),
              _buildDetailRow('Contact tuteur', student.guardianContact, theme),
              if (student.medicalInfo != null &&
                  student.medicalInfo!.isNotEmpty)
                _buildDetailRow('Infos médicales', student.medicalInfo!, theme),
              const SizedBox(height: 16),
              Divider(color: theme.dividerColor),
              Text(
                'Paiement',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Montant dû',
                '${montantMax.toStringAsFixed(2)} FCFA',
                theme,
              ),
              _buildDetailRow(
                'Déjà payé',
                '${totalPaid.toStringAsFixed(2)} FCFA',
                theme,
              ),
              _buildDetailRow(
                'Reste à payer',
                reste <= 0 ? 'Payé' : '${reste.toStringAsFixed(2)} FCFA',
                theme,
              ),
              _buildDetailRow('Statut', status, theme),
              const SizedBox(height: 8),
              if (payments.isNotEmpty) ...[
                Text(
                  'Historique des paiements',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                ...payments.map(
                  (p) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: theme.cardColor,
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
                              color: p.isCancelled
                                  ? Colors.grey
                                  : theme.textTheme.bodyLarge?.color,
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
                              color: p.isCancelled
                                  ? Colors.grey
                                  : theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                          if ((p.recordedBy ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Enregistré par : ${p.recordedBy}',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (p.comment != null && p.comment!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Commentaire : ${p.comment!}',
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
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
                                  icon: Icon(
                                    Icons.picture_as_pdf,
                                    color: Colors.blue,
                                  ),
                                  tooltip: 'Voir le reçu',
                                  onPressed: () => _handleReceiptPdf(
                                    p,
                                    student,
                                    theme,
                                    saveOnly: false,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.save_alt,
                                    color: Colors.blueGrey,
                                  ),
                                  tooltip: 'Enregistrer le reçu',
                                  onPressed: () => _handleReceiptPdf(
                                    p,
                                    student,
                                    theme,
                                    saveOnly: true,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Aucun paiement enregistré.',
                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                ),
              ],
            ],
          ),
        ),
        fields: const [],
        onSubmit: () => Navigator.of(context).pop(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Fermer',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReceiptPdf(
    Payment p,
    Student? student,
    ThemeData theme, {
    bool saveOnly = false,
  }) async {
    if (student == null) return;

    final classe = _classesByName[student.className];
    if (classe == null) return; // Should not happen

    final allPayments = await _dbService.getPaymentsForStudent(student.id);
    final totalPaid = allPayments
        .where((p) => !p.isCancelled)
        .fold(0.0, (sum, item) => sum + item.amount);
    final totalDue =
        (classe.fraisEcole ?? 0) + (classe.fraisCotisationParallele ?? 0);

    final schoolInfo = await loadSchoolInfo();
    final pdfBytes = await PdfService.generatePaymentReceiptPdf(
      currentPayment: p,
      allPayments: allPayments,
      student: student,
      schoolInfo: schoolInfo,
      studentClass: classe,
      totalPaid: totalPaid,
      totalDue: totalDue,
    );

    if (saveOnly) {
      String? directoryPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisir le dossier de sauvegarde',
      );
      if (directoryPath != null) {
        final fileName =
            'Recu_Paiement_${student.name.replaceAll(' ', '_')}_${p.date.substring(0, 10)}.pdf';
        final file = File('$directoryPath/$fileName');
        await file.writeAsBytes(pdfBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reçu enregistré dans $directoryPath'),
            backgroundColor: Colors.green,
          ),
        );
        // Ouvrir le PDF immédiatement
        try {
          await OpenFile.open(file.path);
        } catch (_) {}
      }
    } else {
      // Écrire le PDF dans un fichier temporaire et l'ouvrir
      final tmpDir = await getTemporaryDirectory();
      final fileName =
          'Recu_Paiement_${student.name.replaceAll(' ', '_')}_${p.date.substring(0, 19).replaceAll(':', '-')}.pdf';
      final file = File('${tmpDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      try {
        await OpenFile.open(file.path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reçu PDF ouvert'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir le PDF'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label : ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          ),
        ],
      ),
    );
  }

  void _exportToPdf(ThemeData theme) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF en cours...'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
      final rows = filteredRows.map((row) {
        final student = row['student'] as Student;
        final payment = row['payment'] as Payment?;
        final classe = _classesByName[student.className];
        final montantMax =
            (classe?.fraisEcole ?? 0) + (classe?.fraisCotisationParallele ?? 0);
        final totalPaid = _payments
            .where((pay) => pay.studentId == student.id && !pay.isCancelled)
            .fold<double>(0, (sum, pay) => sum + pay.amount);
        return {
          'student': student,
          'payment': payment,
          'classe': classe,
          'totalPaid': totalPaid,
        };
      }).toList();
      final pdfBytes = await PdfService.exportPaymentsListPdf(rows: rows);
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final file = File(
        '$dirPath/export_paiements_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(pdfBytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export PDF réussi : ${file.path}'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
      // Ouvrir le PDF immédiatement
      try {
        await OpenFile.open(file.path);
      } catch (_) {}
    } catch (e) {
      print('Erreur export PDF : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export PDF : $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  void _exportToExcel(ThemeData theme) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel en cours...'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
      final excel = Excel.createExcel();
      final sheet = excel['Paiements'];
      // En-têtes
      sheet.appendRow([
        TextCellValue('Nom'),
        TextCellValue('Classe'),
        TextCellValue('Année'),
        TextCellValue('Montant payé'),
        TextCellValue('Date'),
        TextCellValue('Statut'),
        TextCellValue('Commentaire'),
      ]);
      for (final row in filteredRows) {
        final student = row['student'] as Student;
        final payment = row['payment'] as Payment?;
        final classe = _classesByName[student.className];
        final montantMax =
            (classe?.fraisEcole ?? 0) + (classe?.fraisCotisationParallele ?? 0);
        final totalPaid = _payments
            .where((pay) => pay.studentId == student.id && !pay.isCancelled)
            .fold<double>(0, (sum, pay) => sum + pay.amount);
        String statut;
        if (montantMax > 0 && totalPaid >= montantMax) {
          statut = 'Payé';
        } else if (payment != null && totalPaid > 0) {
          statut = 'En attente';
        } else {
          statut = 'Impayé';
        }
        sheet.appendRow([
          TextCellValue(student.name),
          TextCellValue(student.className),
          TextCellValue(classe?.academicYear ?? ''),
          payment?.amount != null
              ? DoubleCellValue(payment!.amount)
              : TextCellValue(''),
          payment != null
              ? TextCellValue(
                  payment.date.replaceFirst('T', ' ').substring(0, 16),
                )
              : TextCellValue(''),
          TextCellValue(statut),
          TextCellValue(payment?.comment ?? ''),
        ]);
      }
      final bytes = excel.encode()!;
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final file = File(
        '$dirPath/export_paiements_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Excel réussi : ${file.path}'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Erreur export Excel : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Excel : $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  void _exportToWord(ThemeData theme) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Word en cours...'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choisissez un dossier de sauvegarde',
      );
      if (dirPath == null) return;
      final docx = await _generatePaymentsDocx(theme);
      final file = File(
        '$dirPath/export_paiements_${DateTime.now().millisecondsSinceEpoch}.docx',
      );
      await file.writeAsBytes(docx);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Word réussi : ${file.path}'),
          backgroundColor: theme.colorScheme.primary,
        ),
      );
    } catch (e) {
      print('Erreur export Word : $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur export Word : $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  Future<List<int>> _generatePaymentsDocx(ThemeData theme) async {
    try {
      final bytes = await DefaultAssetBundle.of(
        context,
      ).load('assets/empty.docx');
      final docx = await DocxTemplate.fromBytes(bytes.buffer.asUint8List());

      // Créer une nouvelle liste modifiable
      final List<Map<String, String>> rows = [];

      for (final row in filteredRows) {
        final student = row['student'] as Student;
        final payment = row['payment'] as Payment?;
        final classe = _classesByName[student.className];
        final montantMax =
            (classe?.fraisEcole ?? 0) + (classe?.fraisCotisationParallele ?? 0);
        final totalPaid = _payments
            .where((pay) => pay.studentId == student.id && !pay.isCancelled)
            .fold<double>(0, (sum, pay) => sum + pay.amount);

        String statut;
        if (montantMax > 0 && totalPaid >= montantMax) {
          statut = 'Payé';
        } else if (payment != null && totalPaid > 0) {
          statut = 'En attente';
        } else {
          statut = 'Impayé';
        }

        // Ajouter les données dans un Map
        rows.add({
          'nom': student.name,
          'classe': student.className,
          'annee': classe?.academicYear ?? '',
          'montant': payment?.amount?.toString() ?? '',
          'date': payment != null
              ? payment.date.replaceFirst('T', ' ').substring(0, 16)
              : '',
          'statut': statut,
          'commentaire': payment?.comment ?? '',
        });
      }

      // Créer le contenu du document
      final content = Content();

      // Ajouter les données au template
      content.add(
        TableContent(
          'paiements',
          rows
              .map(
                (row) => RowContent()
                  ..add(TextContent('nom', row['nom'] ?? ''))
                  ..add(TextContent('classe', row['classe'] ?? ''))
                  ..add(TextContent('annee', row['annee'] ?? ''))
                  ..add(TextContent('montant', row['montant'] ?? ''))
                  ..add(TextContent('date', row['date'] ?? ''))
                  ..add(TextContent('statut', row['statut'] ?? ''))
                  ..add(TextContent('commentaire', row['commentaire'] ?? '')),
              )
              .toList(),
        ),
      );

      // Générer le document
      final generatedDoc = await docx.generate(content);
      if (generatedDoc == null) {
        throw Exception('Échec de la génération du document Word');
      }

      // Convertir en List<int> modifiable
      return List<int>.from(generatedDoc);
    } catch (e) {
      print('Erreur génération Word : $e');
      rethrow;
    }
  }
}
