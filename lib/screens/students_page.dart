import 'package:flutter/material.dart';
import 'package:school_manager/screens/dashboard_home.dart';

import 'package:school_manager/constants/colors.dart';
import 'package:school_manager/constants/sizes.dart';
import 'package:school_manager/constants/strings.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/screens/students/class_details_page.dart';
import 'package:school_manager/screens/students/widgets/chart_card.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:school_manager/screens/students/widgets/student_registration_form.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/screens/students/student_profile_page.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/utils/academic_year.dart';

class StudentsPage extends StatefulWidget {
  @override
  _StudentsPageState createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  final DatabaseService _dbService = DatabaseService();
  Map<String, int> _classDistribution = {};
  Map<String, int> _academicYearDistribution = {};
  List<Map<String, dynamic>> _tableData = [];
  List<Student> _allStudents = []; // Store all students for search

  // Filtres sélectionnés
  String? _selectedClassFilter;
  String? _selectedGenderFilter;
  String? _selectedYearFilter;

  String _classKey(Class cls) => '${cls.name}:::${cls.academicYear}';
  String _classLabel(Class cls) => '${cls.name} (${cls.academicYear})';
  Class? _classFromKey(String? key, List<Class> classes) {
    if (key == null) return null;
    final parts = key.split(':::');
    if (parts.length != 2) return null;
    final name = parts.first;
    final year = parts.last;
    for (final cls in classes) {
      if (cls.name == name && cls.academicYear == year) {
        return cls;
      }
    }
    return null;
  }

  String _searchQuery = '';
  String _currentAcademicYear = '2024-2025';
  bool _showStudentView = false; // Toggle between class view and student view

  @override
  void initState() {
    super.initState();
    academicYearNotifier.addListener(_onAcademicYearChanged);
    getCurrentAcademicYear().then((year) {
      setState(() {
        _currentAcademicYear = year;
        if (_selectedYearFilter == null) {
          _selectedYearFilter = year;
        }
      });
      _loadData();
    });
  }

  void _onAcademicYearChanged() {
    setState(() {
      _currentAcademicYear = academicYearNotifier.value;
      _selectedYearFilter = academicYearNotifier.value;
    });
    _loadData();
  }

  @override
  void dispose() {
    academicYearNotifier.removeListener(_onAcademicYearChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    final classDist = await _dbService.getClassDistribution();
    final yearDist = await _dbService.getAcademicYearDistribution();
    final students = await _dbService.getStudents();
    final classes = await _dbService.getClasses();
    
    // Store all students for search functionality
    setState(() {
      _allStudents = students;
    });

    final tableData = classes.map((cls) {
      final key = _classKey(cls);
      final label = _classLabel(cls);
      // Compter uniquement les élèves de l'année académique de la classe
      final filteredStudents = students.where((s) => s.className == cls.name && s.academicYear == cls.academicYear).toList();
      final studentCount = filteredStudents.length;
      final boys = filteredStudents.where((s) => s.gender == 'M').length;
      final girls = filteredStudents.where((s) => s.gender == 'F').length;
      return {
        'classKey': key,
        'classLabel': label,
        'className': cls.name,
        'total': studentCount.toString(),
        'boys': boys.toString(),
        'girls': girls.toString(),
        'year': cls.academicYear,
      };
    }).toList();

    setState(() {
      _classDistribution = classDist;
      _academicYearDistribution = yearDist;
      _tableData = tableData;
      if (_selectedClassFilter != null) {
        final exists = tableData.any((row) => row['classKey'] == _selectedClassFilter);
        if (!exists) {
          _selectedClassFilter = null;
        }
      }
    });
  }

  List<Map<String, dynamic>> get _filteredTableData {
    return _tableData.where((data) {
      final matchClass = _selectedClassFilter == null || data['classKey'] == _selectedClassFilter;
      final matchYear = _selectedYearFilter == null || data['year'] == _selectedYearFilter;
      if (_selectedGenderFilter != null) {
        if (_selectedGenderFilter == 'M' && data['boys'] == '0') return false;
        if (_selectedGenderFilter == 'F' && data['girls'] == '0') return false;
      }
      
      // Enhanced search: include student names
      final matchSearch = _searchQuery.isEmpty || _matchesSearchQuery(data);
      
      return matchClass && matchYear && matchSearch;
    }).toList();
  }
  
  bool _isSearchingByStudentName(String query) {
    if (query.isEmpty) return false;
    
    final lowerQuery = query.toLowerCase();
    
    // Check if query matches any student name
    final matchingStudents = _allStudents.where((student) => 
      student.name.toLowerCase().contains(lowerQuery)
    ).toList();
    
    // If we found students and the query doesn't match class names, show student view
    if (matchingStudents.isNotEmpty) {
      // Check if query also matches class names
      final matchingClasses = _tableData.where((data) {
        final classLabel = (data['classLabel'] as String).toLowerCase();
        final year = data['year'].toLowerCase();
        return classLabel.contains(lowerQuery) || year.contains(lowerQuery);
      }).toList();
      
      // If no class matches, definitely show student view
      if (matchingClasses.isEmpty) {
        return true;
      }
      
      // If both students and classes match, prefer student view for personal names
      // (assuming personal names are more specific than class names)
      return true;
    }
    
    return false;
  }

  bool _matchesSearchQuery(Map<String, dynamic> data) {
    if (_searchQuery.isEmpty) return true;
    
    final query = _searchQuery.toLowerCase();
    
    // Search in class name and year
    final classLabel = (data['classLabel'] as String).toLowerCase();
    final year = data['year'].toLowerCase();
    
    if (classLabel.contains(query) || year.contains(query)) {
      return true;
    }
    
    // Search in student names for this class
    final className = data['className'] as String;
    final classYear = data['year'] as String;
    
    final studentsInClass = _allStudents.where((student) => 
      student.className == className && student.academicYear == classYear
    ).toList();
    
    return studentsInClass.any((student) => 
      student.name.toLowerCase().contains(query)
    );
  }
  
  List<Student> get _filteredStudents {
    if (_searchQuery.isEmpty) return [];
    
    final query = _searchQuery.toLowerCase();
    return _allStudents.where((student) {
      // Apply year filter
      final matchYear = _selectedYearFilter == null || student.academicYear == _selectedYearFilter;
      
      // Apply gender filter
      final matchGender = _selectedGenderFilter == null || student.gender == _selectedGenderFilter;
      
      // Apply class filter
      final matchClass = _selectedClassFilter == null || 
        _classFromKey(_selectedClassFilter, [])?.name == student.className;
      
      // Apply search query
      final matchSearch = student.name.toLowerCase().contains(query);
      
      return matchYear && matchGender && matchClass && matchSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(AppSizes.padding),
          child: Container(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                SizedBox(height: AppSizes.padding),
                _buildActionButtons(context),
                SizedBox(height: AppSizes.padding),
                _buildFilters(context),
                SizedBox(height: AppSizes.padding),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_showStudentView) ...[
                          _buildChartsSection(context, constraints),
                          SizedBox(height: AppSizes.padding),
                          _buildDataTable(context),
                        ] else ...[
                          _buildStudentListView(context),
                        ],
                        SizedBox(height: AppSizes.padding),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween, // To push notification icon to the end
            children: [
              Row( // This inner Row contains the icon, title, and description
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
                      Icons.people,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column( // Title and description
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.studentsTitle,
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color, // Use bodyLarge for title
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Gérez les informations des élèves, leurs classes et leurs performances académiques.',
                        style: TextStyle(
                          fontSize: isDesktop ? 16 : 14,
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7), // Use bodyMedium for description
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Notification icon back in place
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowDark.withOpacity(0.1),
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
            decoration: InputDecoration(
              hintText: 'Rechercher par classe, année ou nom d\'élève...',
              hintStyle: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6)),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
            onChanged: (value) {
              final trimmedValue = value.trim();
              setState(() {
                _searchQuery = trimmedValue;
                // Switch to student view if searching by student name
                _showStudentView = _isSearchingByStudentName(trimmedValue);
              });
            },
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final classMap = <String, String>{
      for (final row in _tableData)
        row['classKey'] as String: row['classLabel'] as String,
    };
    final yearList = _tableData.map((e) => e['year'] as String).toSet().toList();
    return Wrap(
      spacing: AppSizes.smallSpacing,
      runSpacing: AppSizes.smallSpacing,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedClassFilter,
              hint: Text(AppStrings.classFilter, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color)),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('Toutes les classes', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color))),
                ...classMap.entries.map(
                  (entry) => DropdownMenuItem<String?>(
                    value: entry.key,
                    child: Text(entry.value, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color)),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _selectedClassFilter = value),
              dropdownColor: Theme.of(context).cardColor,
              iconEnabledColor: Theme.of(context).iconTheme.color,
              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedGenderFilter,
              hint: Text(AppStrings.genderFilter, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color)),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('Tous', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color))),
                DropdownMenuItem<String?>(value: 'M', child: Text('Garçons', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color))),
                DropdownMenuItem<String?>(value: 'F', child: Text('Filles', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color))),
              ],
              onChanged: (value) => setState(() => _selectedGenderFilter = value),
              dropdownColor: Theme.of(context).cardColor,
              iconEnabledColor: Theme.of(context).iconTheme.color,
              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color),
            ),
          ),
        ),
        ValueListenableBuilder<String>(
          valueListenable: academicYearNotifier,
          builder: (context, currentYear, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor!),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedYearFilter,
                  hint: Text(AppStrings.yearFilter, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color)),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text('Toutes les années', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color))),
                    DropdownMenuItem<String?>(value: currentYear, child: Text('Année courante ($currentYear)', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color))),
                    ...yearList.where((y) => y != currentYear).map((y) => DropdownMenuItem<String?>(value: y, child: Text(y, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color)))),
                  ],
                  onChanged: (value) => setState(() => _selectedYearFilter = value),
                  dropdownColor: Theme.of(context).cardColor,
                  iconEnabledColor: Theme.of(context).iconTheme.color,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color),
                ),
              ),
            );
          },
        ),
        if (_selectedClassFilter != null || _selectedGenderFilter != null || _selectedYearFilter != null)
          TextButton.icon(
            onPressed: () => setState(() {
              _selectedClassFilter = null;
              _selectedGenderFilter = null;
              _selectedYearFilter = _currentAcademicYear;
            }),
            icon: Icon(Icons.clear, color: Theme.of(context).textTheme.bodyMedium!.color),
            label: Text('Réinitialiser', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color)),
          ),
      ],
    );
  }

  Widget _buildChartsSection(BuildContext context, BoxConstraints constraints) {
    return constraints.maxWidth > 600
        ? Row(
            children: [
              Expanded(
                child: ChartCard(
                  title: AppStrings.classDistributionTitle,
                  total: _classDistribution.values.fold(0, (a, b) => a + b).toString(),
                  percentage: _classDistribution.isEmpty ? '0%' : '+12%',
                  maxY: (_classDistribution.values.isEmpty ? 1 : _classDistribution.values.reduce((a, b) => a > b ? a : b)).toDouble() + 10,
                  bottomTitles: _classDistribution.keys.toList(),
                  barValues: _classDistribution.values.map((e) => e.toDouble()).toList(),
                  aspectRatio: AppSizes.chartAspectRatio,
                ),
              ),
              SizedBox(width: AppSizes.spacing),
              Expanded(
                child: ChartCard(
                  title: AppStrings.academicYearTitle,
                  total: _academicYearDistribution.values.fold(0, (a, b) => a + b).toString(),
                  percentage: _academicYearDistribution.isEmpty ? '0%' : '+5%',
                  maxY: (_academicYearDistribution.values.isEmpty ? 1 : _academicYearDistribution.values.reduce((a, b) => a > b ? a : b)).toDouble() + 10,
                  bottomTitles: _academicYearDistribution.keys.toList(),
                  barValues: _academicYearDistribution.values.map((e) => e.toDouble()).toList(),
                  aspectRatio: AppSizes.chartAspectRatio,
                ),
              ),
            ],
          )
        : Column(
            children: [
              ChartCard(
                title: AppStrings.classDistributionTitle,
                total: _classDistribution.values.fold(0, (a, b) => a + b).toString(),
                percentage: _classDistribution.isEmpty ? '0%' : '+12%',
                maxY: (_classDistribution.values.isEmpty ? 1 : _classDistribution.values.reduce((a, b) => a > b ? a : b)).toDouble() + 10,
                bottomTitles: _classDistribution.keys.toList(),
                barValues: _classDistribution.values.map((e) => e.toDouble()).toList(),
                aspectRatio: AppSizes.chartAspectRatio,
              ),
              SizedBox(height: AppSizes.spacing),
              ChartCard(
                title: AppStrings.academicYearTitle,
                total: _academicYearDistribution.values.fold(0, (a, b) => a + b).toString(),
                percentage: _academicYearDistribution.isEmpty ? '0%' : '+5%',
                maxY: (_academicYearDistribution.values.isEmpty ? 1 : _academicYearDistribution.values.reduce((a, b) => a > b ? a : b)).toDouble() + 10,
                bottomTitles: _academicYearDistribution.keys.toList(),
                barValues: _academicYearDistribution.values.map((e) => e.toDouble()).toList(),
                aspectRatio: AppSizes.chartAspectRatio,
              ),
            ],
          );
  }

  Widget _buildDataTable(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowDark.withOpacity(0.2),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
          // Make the table visually larger and more readable
          headingRowHeight: 60,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          columnSpacing: 32,
          columns: [
            DataColumn(
              label: Text(
                AppStrings.classLabel,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                AppStrings.totalStudentsLabel,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                AppStrings.boysLabel,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                AppStrings.girlsLabel,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                AppStrings.academicYearLabel,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                AppStrings.actionsLabel,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyMedium!.color,
                ),
              ),
            ),
          ],
          rows: _filteredTableData.map((data) => _buildRow(
            context,
            data['classKey'] as String,
            data['classLabel'] as String,
            data['total'],
            data['boys'],
            data['girls'],
            data['year'],
          )).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  DataRow _buildRow(
    BuildContext context,
    String classKey,
    String classLabel,
    String total,
    String male,
    String female,
    String year,
  ) {
    final keyParts = classKey.split(':::');
    final className = keyParts.isNotEmpty ? keyParts.first : classLabel;
    final classYear = keyParts.length > 1 ? keyParts.last : year;
    return DataRow(
      cells: [
        DataCell(
          Text(
            classLabel,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
        ),
        DataCell(
          Text(
            total,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
        ),
        DataCell(
          Text(
            male,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
        ),
        DataCell(
          Text(
            female,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
        ),
        DataCell(
          Text(
            year,
            style: TextStyle(
              fontSize: 15.0,
              color: Theme.of(context).textTheme.bodyMedium!.color,
            ),
          ),
        ),
        DataCell(
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  final classes = await DatabaseService().getClasses();
                  final classObjFull = _classFromKey(classKey, classes) ?? Class(
                    name: className,
                    academicYear: classYear,
                    titulaire: null,
                    fraisEcole: null,
                    fraisCotisationParallele: null,
                  );
                  final classStudents = await DatabaseService().getStudentsByClassAndClassYear(
                    className,
                    classYear,
                  );
                  await showDialog(
                    context: context,
                    builder: (context) => ClassDetailsPage(
                      classe: classObjFull,
                      students: classStudents,
                    ),
                  );
                  await _loadData();
                },
                child: Text(
                  AppStrings.viewDetails,
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyMedium!.color,
                  ),
                ),
              ),
              
            ],
          ),
        ),
      ],
    );
  }

  void _showEditStudentDialog(BuildContext context, Student student) {
    final GlobalKey<StudentRegistrationFormState> studentFormKey = GlobalKey<StudentRegistrationFormState>();
    
    showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: 'Modifier l\'élève',
        content: StudentRegistrationForm(
          key: studentFormKey,
          student: student, // Pass the existing student data
          onSubmit: () {
            _loadData();
            Navigator.pop(context);
            // Afficher une notification de succès
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Élève modifié avec succès!'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          },
        ),
        fields: const [],
        onSubmit: () {
          studentFormKey.currentState?.submitForm();
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => studentFormKey.currentState?.submitForm(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Modifier'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final GlobalKey<StudentRegistrationFormState> studentFormKey = GlobalKey<StudentRegistrationFormState>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: () {
            print('Ajouter un Élève button pressed');
            try {
              showDialog(
                context: context,
                builder: (context) => CustomDialog(
                  title: AppStrings.addStudent,
                  content: StudentRegistrationForm(
                    key: studentFormKey,
                    onSubmit: () {
                      print('Student form submitted');
                      _loadData();
                      Navigator.pop(context);
                      // Afficher une notification de succès
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Élève ajouté avec succès!'),
                            ],
                          ),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
                    },
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
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Ajouter'),
                    ),
                  ],
                ),
              );
            } catch (e) {
              print('Error opening student dialog: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erreur: $e')),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            elevation: null,
          ),
          child: const Text(
            'Ajouter un élève',
            style: TextStyle(fontSize: AppSizes.textFontSize, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => _ClassDialog(
                onSubmit: () {},
              ),
            );
            if (ok == true) {
              await _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Classe ajoutée avec succès!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.grey.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
          child: const Text(
            'Ajouter une classe',
            style: TextStyle(fontSize: AppSizes.textFontSize, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentListView(BuildContext context) {
    final filteredStudents = _filteredStudents;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.person_search, color: Theme.of(context).primaryColor),
                SizedBox(width: 12),
                Text(
                  'Élèves trouvés (${filteredStudents.length})',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                ),
              ],
            ),
          ),
          if (filteredStudents.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Aucun élève trouvé pour cette recherche.',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium!.color,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: filteredStudents.length,
              itemBuilder: (context, index) {
                final student = filteredStudents[index];
                return _buildStudentCard(context, student);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(BuildContext context, Student student) {
    final theme = Theme.of(context);
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor!.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Student avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Icon(
              Icons.person,
              color: theme.primaryColor,
              size: 24,
            ),
          ),
          SizedBox(width: 16),
          
          // Student info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge!.color,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.class_, size: 16, color: theme.textTheme.bodyMedium!.color),
                    SizedBox(width: 4),
                    Text(
                      '${student.className} (${student.academicYear})',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium!.color,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      student.gender == 'M' ? Icons.male : Icons.female,
                      size: 16,
                      color: student.gender == 'M' ? Colors.blue : Colors.pink,
                    ),
                    SizedBox(width: 4),
                    Text(
                      student.gender == 'M' ? 'Garçon' : 'Fille',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium!.color,
                      ),
                    ),
                    SizedBox(width: 16),
                    Icon(Icons.phone, size: 16, color: theme.textTheme.bodyMedium!.color),
                    SizedBox(width: 4),
                    Text(
                      student.contactNumber.isNotEmpty ? student.contactNumber : 'Non renseigné',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium!.color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Action buttons
          Row(
            children: [
              IconButton(
                onPressed: () async {
                  final classes = await DatabaseService().getClasses();
                  final classObj = classes.firstWhere(
                    (c) => c.name == student.className && c.academicYear == student.academicYear,
                    orElse: () => Class(
                      name: student.className,
                      academicYear: student.academicYear,
                      titulaire: null,
                      fraisEcole: null,
                      fraisCotisationParallele: null,
                    ),
                  );
                  final classStudents = await DatabaseService().getStudentsByClassAndClassYear(
                    student.className,
                    student.academicYear,
                  );
                  await showDialog(
                    context: context,
                    builder: (context) => ClassDetailsPage(
                      classe: classObj,
                      students: classStudents,
                    ),
                  );
                  await _loadData();
                },
                icon: Icon(Icons.visibility, color: theme.primaryColor),
                tooltip: 'Voir la classe',
              ),
              IconButton(
                onPressed: () {
                  // Navigate to student profile or edit dialog
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StudentProfilePage(student: student),
                    ),
                  );
                },
                icon: Icon(Icons.person, color: theme.primaryColor),
                tooltip: 'Voir le profil',
              ),
              IconButton(
                onPressed: () {
                  _showEditStudentDialog(context, student);
                },
                icon: Icon(Icons.edit, color: theme.primaryColor),
                tooltip: 'Modifier l\'élève',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClassDialog extends StatefulWidget {
  final VoidCallback onSubmit;

  const _ClassDialog({required this.onSubmit});

  @override
  State<_ClassDialog> createState() => __ClassDialogState();
}

class __ClassDialogState extends State<_ClassDialog> {
  final _formKey = GlobalKey<FormState>();
  final classNameController = TextEditingController();
  final academicYearController = TextEditingController();
  final titulaireController = TextEditingController();
  final fraisEcoleController = TextEditingController();
  final fraisCotisationParalleleController = TextEditingController();
  final DatabaseService _dbService = DatabaseService();

  @override
  void initState() {
    super.initState();
    academicYearController.text = academicYearNotifier.value;
  }

  @override
  void dispose() {
    classNameController.dispose();
    academicYearController.dispose();
    titulaireController.dispose();
    fraisEcoleController.dispose();
    fraisCotisationParalleleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomDialog(
      title: AppStrings.addClass,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomFormField(
              controller: classNameController,
              labelText: AppStrings.classNameDialog,
              hintText: 'Enter le nom de la classe',
              validator: (value) => value!.isEmpty ? AppStrings.required : null,
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: academicYearController,
              labelText: AppStrings.academicYearDialog,
              hintText: 'Enter l\'année scolaire',
              validator: (value) => value!.isEmpty ? AppStrings.required : null,
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: titulaireController,
              labelText: 'Titulaire',
              hintText: 'Nom du titulaire de la classe',
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: fraisEcoleController,
              labelText: 'Frais d\'école',
              hintText: 'Montant des frais d\'école',
              validator: (value) {
                if (value != null && value.isNotEmpty && double.tryParse(value) == null) {
                  return 'Veuillez entrer un montant valide';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSizes.smallSpacing),
            CustomFormField(
              controller: fraisCotisationParalleleController,
              labelText: 'Frais de cotisation parallèle',
              hintText: 'Montant des frais de cotisation parallèle',
              validator: (value) {
                if (value != null && value.isNotEmpty && double.tryParse(value) == null) {
                  return 'Veuillez entrer un montant valide';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      fields: const [],
      onSubmit: () async {
        if (_formKey.currentState!.validate()) {
          try {
            final cls = Class(
              name: classNameController.text,
              academicYear: academicYearController.text,
              titulaire: titulaireController.text.isNotEmpty ? titulaireController.text : null,
              fraisEcole: fraisEcoleController.text.isNotEmpty ? double.tryParse(fraisEcoleController.text) : null,
              fraisCotisationParallele: fraisCotisationParalleleController.text.isNotEmpty ? double.tryParse(fraisCotisationParalleleController.text) : null,
            );
            await _dbService.insertClass(cls);
            // Close dialog and notify parent for snackbar
            Navigator.pop(context, true);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors de l\'enregistrement: $e')),
            );
          }
        }
      },
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              try {
                final cls = Class(
                  name: classNameController.text,
                  academicYear: academicYearController.text,
                  titulaire: titulaireController.text.isNotEmpty ? titulaireController.text : null,
                  fraisEcole: fraisEcoleController.text.isNotEmpty ? double.tryParse(fraisEcoleController.text) : null,
                  fraisCotisationParallele: fraisCotisationParalleleController.text.isNotEmpty ? double.tryParse(fraisCotisationParalleleController.text) : null,
                );
                await _dbService.insertClass(cls);
                Navigator.pop(context, true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erreur lors de l\'enregistrement: $e')),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
