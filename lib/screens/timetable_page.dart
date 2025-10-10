import 'package:flutter/material.dart';
import 'package:school_manager/constants/colors.dart';

import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/services/scheduling_service.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/utils/timetable_prefs.dart' as ttp;
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({Key? key}) : super(key: key);

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';

  String? _selectedClassKey;
  String? _selectedTeacherFilter;
  bool _isClassView = true;

  List<Class> _classes = [];
  List<Staff> _teachers = [];
  List<Course> _subjects = [];
  List<TimetableEntry> _timetableEntries =
      []; // Add this line to define the timetable entries
  SchoolInfo? _schoolInfo;

  // Label de l'année académique courante (ex: "2025-2026"). Nullable pour compatibilité.
  String? _currentAcademicYearLabel;

  String _classKey(Class c) => '${c.name}:::${c.academicYear}';
  String _classKeyFromValues(String name, String academicYear) =>
      '$name:::${academicYear}';
  String _classLabel(Class c) => '${c.name} (${c.academicYear})';
  Class? _classFromKey(String? key) {
    if (key == null) return null;
    final parts = key.split(':::');
    if (parts.length != 2) return null;
    final name = parts.first;
    final year = parts.last;
    for (final c in _classes) {
      if (c.name == name && c.academicYear == year) {
        return c;
      }
    }
    return null;
  }

  final List<String> _daysOfWeek = List.of(ttp.kDefaultDays);

  final List<String> _timeSlots = List.of(ttp.kDefaultSlots);
  Set<String> _breakSlots = <String>{};
  // Auto-generation settings
  final TextEditingController _morningStartCtrl = TextEditingController();
  final TextEditingController _morningEndCtrl = TextEditingController();
  final TextEditingController _afternoonStartCtrl = TextEditingController();
  final TextEditingController _afternoonEndCtrl = TextEditingController();
  final TextEditingController _sessionMinutesCtrl = TextEditingController(text: '60');
  final TextEditingController _sessionsPerSubjectCtrl = TextEditingController(text: '1');
  final TextEditingController _teacherMaxPerDayCtrl = TextEditingController(text: '0');
  final TextEditingController _classMaxPerDayCtrl = TextEditingController(text: '0');
  final TextEditingController _subjectMaxPerDayCtrl = TextEditingController(text: '0');
  bool _clearBeforeGen = false;
  bool _isGenerating = false;
  bool _saturateAll = false;
  // Block sizing settings
  final TextEditingController _blockDefaultCtrl = TextEditingController(text: '2');
  final TextEditingController _threeHourThresholdCtrl = TextEditingController(text: '1.5');

  final DatabaseService _dbService = DatabaseService();
  late final SchedulingService _scheduling;
  Set<String> _teacherUnavailKeys = <String>{}; // format: 'Day|HH:mm'
  // Scroll controllers for navigating the timetable
  final ScrollController _classListScrollCtrl = ScrollController();
  final ScrollController _tableVScrollCtrl = ScrollController();
  final ScrollController _tableHScrollCtrl = ScrollController();
  late TabController _tabController;

  @override
  void initState() {
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    super.initState();
    _scheduling = SchedulingService(_dbService);
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadData();
  }

  Future<void> _loadData() async {
    // Utiliser la valeur canonicalisée de l'application pour l'année académique
    // (stockée dans SharedPreferences via utils/academic_year.dart) afin que
    // le filtrage corresponde aux classes créées par l'utilisateur.
    final currentAcademicYear = await getCurrentAcademicYear();

    // Charger les données depuis le service DB
    final allClasses = await _dbService.getClasses();
    final allTeachers = await _dbService.getStaff();
    final allSubjects = await _dbService.getCourses();
    final schoolInfo = await _dbService.getSchoolInfo();
    final allEntries = await _dbService.getTimetableEntries();

    // Filtrer par année académique courante
    _classes = allClasses.where((c) {
      try {
        return (c.academicYear ?? '') == currentAcademicYear;
      } catch (_) {
        // Si le modèle n'a pas le champ academicYear, on garde tout (fallback)
        return true;
      }
    }).toList();

    _teachers = allTeachers;
    _subjects = allSubjects;
    _schoolInfo = schoolInfo;

    _timetableEntries = allEntries.where((e) {
      try {
        return (e.academicYear ?? '') == currentAcademicYear;
      } catch (_) {
        // fallback: si pas de champ, conserver l'entrée
        return true;
      }
    }).toList();

    // Charger la configuration des jours, créneaux et pauses depuis les préférences
    final prefDays = await ttp.loadDays();
    final prefSlots = await ttp.loadSlots();
    final prefBreaks = await ttp.loadBreakSlots();
    _daysOfWeek
      ..clear()
      ..addAll(prefDays);
    _timeSlots
      ..clear()
      ..addAll(prefSlots);
    _breakSlots = prefBreaks;

    // Load auto-gen prefs
    _morningStartCtrl.text = await ttp.loadMorningStart();
    _morningEndCtrl.text = await ttp.loadMorningEnd();
    _afternoonStartCtrl.text = await ttp.loadAfternoonStart();
    _afternoonEndCtrl.text = await ttp.loadAfternoonEnd();
    _sessionMinutesCtrl.text = (await ttp.loadSessionMinutes()).toString();
    _blockDefaultCtrl.text = (await ttp.loadBlockDefaultSlots()).toString();
    _threeHourThresholdCtrl.text = (await ttp.loadThreeHourThreshold()).toString();

    setState(() {
      // initialiser la sélection de classe/enseignant si nécessaire
      if (_selectedClassKey == null && _classes.isNotEmpty) {
        _selectedClassKey = _classKey(_classes.first);
      } else if (_selectedClassKey != null) {
        final current = _classFromKey(_selectedClassKey);
        if (current == null && _classes.isNotEmpty) {
          _selectedClassKey = _classKey(_classes.first);
        }
      }

      if (_selectedTeacherFilter == null && _teachers.isNotEmpty) {
        _selectedTeacherFilter = _teachers.first.name;
      }

      // on peut exposer l'année académique courante pour affichage
      _currentAcademicYearLabel = currentAcademicYear;
    });

    // Load selected teacher unavailability if in teacher view
    if (!_isClassView &&
        _selectedTeacherFilter != null &&
        _selectedTeacherFilter!.isNotEmpty) {
      await _loadTeacherUnavailability(
        _selectedTeacherFilter!,
        currentAcademicYear,
      );
    }
  }

  Future<void> _loadTeacherUnavailability(
    String teacherName,
    String academicYear,
  ) async {
    final rows = await _dbService.getTeacherUnavailability(
      teacherName,
      academicYear,
    );
    setState(() {
      _teacherUnavailKeys = rows
          .map((e) => '${e['dayOfWeek']}|${e['startTime']}')
          .toSet();
    });
  }

  Class? _selectedClass() => _classFromKey(_selectedClassKey);

  Staff? _findTeacherForSubject(String subject, Class cls) {
    final both = _teachers.firstWhere(
      (t) => t.courses.contains(subject) && t.classes.contains(cls.name),
      orElse: () => Staff.empty(),
    );
    if (both.id.isNotEmpty) return both;
    final any = _teachers.firstWhere(
      (t) => t.courses.contains(subject),
      orElse: () => Staff.empty(),
    );
    return any.id.isNotEmpty ? any : null;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _morningStartCtrl.dispose();
    _morningEndCtrl.dispose();
    _afternoonStartCtrl.dispose();
    _afternoonEndCtrl.dispose();
    _sessionMinutesCtrl.dispose();
    _sessionsPerSubjectCtrl.dispose();
    _teacherMaxPerDayCtrl.dispose();
    _classMaxPerDayCtrl.dispose();
    _subjectMaxPerDayCtrl.dispose();
    _blockDefaultCtrl.dispose();
    _threeHourThresholdCtrl.dispose();
    _tabController.dispose();
    _classListScrollCtrl.dispose();
    _tableVScrollCtrl.dispose();
    _tableHScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context, isDarkMode, isDesktop),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0EA5E9), Color(0xFF10B981)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0EA5E9).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                tabs: const [
                  Tab(text: 'Paramètres'),
                  Tab(text: 'Emploi du temps'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: paramètres & génération
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildAutoGenPanel(context),
                ),
                // Tab 2: tableau + filtres + exports + palette
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ToggleButtons(
                                isSelected: [_isClassView, !_isClassView],
                                onPressed: (index) {
                                  setState(() {
                                    _isClassView = index == 0;
                                  });
                                },
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: Text('Classe', style: theme.textTheme.bodyMedium),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: Text('Enseignant', style: theme.textTheme.bodyMedium),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              if (_isClassView)
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedClassKey,
                                    decoration: InputDecoration(
                                      labelText: 'Filtrer par Classe',
                                      labelStyle: theme.textTheme.bodyMedium,
                                      border: const OutlineInputBorder(),
                                    ),
                                    isDense: true,
                                    isExpanded: true,
                                    items: _classes
                                        .map((cls) => DropdownMenuItem<String>(
                                              value: _classKey(cls),
                                              child: Text(_classLabel(cls), style: theme.textTheme.bodyMedium),
                                            ))
                                        .toList(),
                                    onChanged: (v) => setState(() => _selectedClassKey = v),
                                  ),
                                )
                              else
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedTeacherFilter,
                                    decoration: InputDecoration(
                                      labelText: 'Filtrer par Enseignant',
                                      labelStyle: theme.textTheme.bodyMedium,
                                      border: const OutlineInputBorder(),
                                    ),
                                    isDense: true,
                                    isExpanded: true,
                                    items: _teachers
                                        .map((t) => DropdownMenuItem<String>(
                                              value: t.name,
                                              child: Text(t.name, style: theme.textTheme.bodyMedium),
                                            ))
                                        .toList(),
                                    onChanged: (v) async {
                                      setState(() => _selectedTeacherFilter = v);
                                      if (v != null && v.isNotEmpty) {
                                        final year = await getCurrentAcademicYear();
                                        await _loadTeacherUnavailability(v, year);
                                      }
                                    },
                                  ),
                                ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: _showAddEditTimetableEntryDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Ajouter un cours'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _exportTimetableToPdf(exportBy: _isClassView ? 'class' : 'teacher'),
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('Exporter PDF'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: () => _exportTimetableToExcel(exportBy: _isClassView ? 'class' : 'teacher'),
                                icon: const Icon(Icons.grid_on),
                                label: const Text('Exporter Excel'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isClassView) _buildClassSubjectHoursSummary(context),
                          if (_isClassView) _buildSubjectPalette(context),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 200,
                            child: Scrollbar(
                              controller: _classListScrollCtrl,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _classListScrollCtrl,
                                itemCount: _classes.length,
                                itemBuilder: (context, index) {
                                  final aClass = _classes[index];
                                  return ListTile(
                                    title: Text(_classLabel(aClass), style: theme.textTheme.bodyMedium),
                                    selected: _classKey(aClass) == _selectedClassKey,
                                    onTap: () => setState(() => _selectedClassKey = _classKey(aClass)),
                                  );
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: _tableVScrollCtrl,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _tableVScrollCtrl,
                                scrollDirection: Axis.vertical,
                                child: Scrollbar(
                                  controller: _tableHScrollCtrl,
                                  thumbVisibility: true,
                                  notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                                  child: SingleChildScrollView(
                                    controller: _tableHScrollCtrl,
                                    scrollDirection: Axis.horizontal,
                                    child: _buildTimetableGrid(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, int>> _computeClassSubjectMinutes(Class cls) async {
    final assigned = await _dbService.getCoursesForClass(cls.name, cls.academicYear);
    final names = assigned.map((c) => c.name).toSet();
    final Map<String, int> minutes = { for (final n in names) n: 0 };
    for (final e in _timetableEntries) {
      if (e.className == cls.name && e.academicYear == cls.academicYear) {
        final start = _toMin(e.startTime);
        final end = _toMin(e.endTime);
        final diff = (end > start) ? (end - start) : 0;
        minutes[e.subject] = (minutes[e.subject] ?? 0) + diff;
      }
    }
    return minutes;
  }

  Widget _buildClassSubjectHoursSummary(BuildContext context) {
    final cls = _selectedClass();
    if (cls == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, int>>(
      future: _computeClassSubjectMinutes(cls),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }
        final data = snap.data!;
        if (data.isEmpty) return const SizedBox.shrink();
        String fmtHours(int minutes) {
          final h = minutes / 60.0;
          if ((h - h.round()).abs() < 1e-6) return '${h.round()}h';
          return '${h.toStringAsFixed(1)}h';
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: data.entries.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule, size: 14, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 6),
                    Text(
                      '${e.key}: ${fmtHours(e.value)}',
                      style: const TextStyle(
                        color: Color(0xFF3B82F6),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  int _toMin(String t) {
    try {
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    } catch (_) {
      return 0;
    }
  }

  String _fmtHHmm(int m) {
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mi = (m % 60).toString().padLeft(2, '0');
    return '$h:$mi';
  }

  List<String> _buildSlotsFromSegments() {
    final int session = int.tryParse(_sessionMinutesCtrl.text) ?? 60;
    final segs = <List<int>>[];
    final ms = _toMin(_morningStartCtrl.text);
    final me = _toMin(_morningEndCtrl.text);
    final as = _toMin(_afternoonStartCtrl.text);
    final ae = _toMin(_afternoonEndCtrl.text);
    if (me > ms + 10) segs.add([ms, me]);
    if (ae > as + 10) segs.add([as, ae]);
    final slots = <String>[];
    for (final seg in segs) {
      int cur = seg[0];
      while (cur + session <= seg[1]) {
        final start = _fmtHHmm(cur);
        final end = _fmtHHmm(cur + session);
        slots.add('$start - $end');
        cur += session;
      }
    }
    return slots;
  }

  Widget _buildAutoGenPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_mode, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Text(
                'Auto-génération des emplois du temps',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_isGenerating) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Jours de la semaine (sélection)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Jours:'),
                    ...['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi']
                        .map((d) => FilterChip(
                              label: Text(d),
                              selected: _daysOfWeek.contains(d),
                              onSelected: (sel) async {
                                setState(() {
                                  if (sel) {
                                    if (!_daysOfWeek.contains(d)) _daysOfWeek.add(d);
                                  } else {
                                    _daysOfWeek.remove(d);
                                  }
                                });
                                await ttp.saveDays(_daysOfWeek);
                              },
                            ))
                        .toList(),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _morningStartCtrl,
                  decoration: const InputDecoration(labelText: 'Début matin'),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _morningEndCtrl,
                  decoration: const InputDecoration(labelText: 'Fin matin'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _afternoonStartCtrl,
                  decoration: const InputDecoration(labelText: 'Début après-midi'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _afternoonEndCtrl,
                  decoration: const InputDecoration(labelText: 'Fin après-midi'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _sessionMinutesCtrl,
                  decoration: const InputDecoration(labelText: 'Durée cours (min)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String>(
                  value: _blockDefaultCtrl.text,
                  decoration: const InputDecoration(labelText: 'Taille bloc par défaut'),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('1h')),
                    DropdownMenuItem(value: '2', child: Text('2h')),
                    DropdownMenuItem(value: '3', child: Text('3h')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _blockDefaultCtrl.text = v);
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _threeHourThresholdCtrl,
                  decoration: const InputDecoration(labelText: 'Seuil bloc 3h (coef×moyenne)'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _sessionsPerSubjectCtrl,
                  decoration: const InputDecoration(labelText: 'Séances/matière (semaine)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _teacherMaxPerDayCtrl,
                  decoration: const InputDecoration(labelText: 'Max cours/jour (enseignant)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _classMaxPerDayCtrl,
                  decoration: const InputDecoration(labelText: 'Max cours/jour (classe)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _subjectMaxPerDayCtrl,
                  decoration: const InputDecoration(labelText: 'Max par matière/jour (classe)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _clearBeforeGen,
                    onChanged: (v) => setState(() => _clearBeforeGen = v),
                  ),
                  const Text('Effacer avant génération'),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _saturateAll,
                    onChanged: (v) => setState(() => _saturateAll = v),
                  ),
                  const Text('Saturer toutes les heures'),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isGenerating ? null : _onGenerateForAllClasses,
                icon: const Icon(Icons.apartment, color: Colors.white),
                label: const Text('Générer pour toutes les classes', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
              ),
              ElevatedButton.icon(
                onPressed: _isGenerating ? null : _onGenerateForAllTeachers,
                icon: const Icon(Icons.person, color: Colors.white),
                label: const Text('Générer pour tous les enseignants', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.successGreen),
              ),
              // Génération ciblée selon la vue
              if (_isClassView)
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _onGenerateForSelectedClass,
                  icon: const Icon(Icons.class_, color: Colors.white),
                  label: const Text('Générer pour la classe sélectionnée', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                )
              else
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _onGenerateForSelectedTeacher,
                  icon: const Icon(Icons.person_outline, color: Colors.white),
                  label: const Text('Générer pour l\'enseignant sélectionné', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveAutoGenPrefs() async {
    await ttp.saveMorningStart(_morningStartCtrl.text.trim());
    await ttp.saveMorningEnd(_morningEndCtrl.text.trim());
    await ttp.saveAfternoonStart(_afternoonStartCtrl.text.trim());
    await ttp.saveAfternoonEnd(_afternoonEndCtrl.text.trim());
    final minutes = int.tryParse(_sessionMinutesCtrl.text) ?? 60;
    await ttp.saveSessionMinutes(minutes);
    await ttp.saveBlockDefaultSlots(int.tryParse(_blockDefaultCtrl.text) ?? 2);
    await ttp.saveThreeHourThreshold(double.tryParse(_threeHourThresholdCtrl.text) ?? 1.5);
    // Also persist generated slots for consistency
    final slots = _buildSlotsFromSegments();
    await ttp.saveSlots(slots);
    setState(() {
      _timeSlots
        ..clear()
        ..addAll(slots);
    });
  }

  Future<void> _onGenerateForAllClasses() async {
    setState(() => _isGenerating = true);
    try {
      await _saveAutoGenPrefs();
      final slots = List<String>.from(_timeSlots);
      int total = 0;
      for (final cls in _classes) {
        int created = 0;
        if (_saturateAll) {
          created = await _scheduling.autoSaturateForClass(
            targetClass: cls,
            daysOfWeek: _daysOfWeek,
            timeSlots: slots,
            breakSlots: _breakSlots,
            clearExisting: _clearBeforeGen,
          );
        } else {
          created = await _scheduling.autoGenerateForClass(
            targetClass: cls,
            daysOfWeek: _daysOfWeek,
            timeSlots: slots,
            breakSlots: _breakSlots,
            clearExisting: _clearBeforeGen,
            sessionsPerSubject: int.tryParse(_sessionsPerSubjectCtrl.text) ?? 1,
            enforceTeacherWeeklyHours: true,
            teacherMaxPerDay: int.tryParse(_teacherMaxPerDayCtrl.text) ?? 0,
            classMaxPerDay: int.tryParse(_classMaxPerDayCtrl.text) ?? 0,
            subjectMaxPerDay: int.tryParse(_subjectMaxPerDayCtrl.text) ?? 0,
            blockDefaultSlots: int.tryParse(_blockDefaultCtrl.text) ?? 2,
            threeHourThreshold: double.tryParse(_threeHourThresholdCtrl.text) ?? 1.5,
          );
        }
        total += created;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Génération terminée: $total cours créés.')),
        );
      }
      try {
        await _dbService.logAudit(
          category: 'timetable',
          action: 'auto_generate_classes',
          details: 'classes=${_classes.length} slots=${slots.length} days=${_daysOfWeek.length} saturate=${_saturateAll ? 1 : 0}',
        );
      } catch (_) {}
    } finally {
      setState(() => _isGenerating = false);
      await _loadData();
    }
  }

  Future<void> _onGenerateForAllTeachers() async {
    setState(() => _isGenerating = true);
    try {
      await _saveAutoGenPrefs();
      final slots = List<String>.from(_timeSlots);
      int total = 0;
      for (final t in _teachers) {
        int created = 0;
        if (_saturateAll) {
          created = await _scheduling.autoSaturateForTeacher(
            teacher: t,
            daysOfWeek: _daysOfWeek,
            timeSlots: slots,
            breakSlots: _breakSlots,
            clearExisting: _clearBeforeGen,
          );
        } else {
          created = await _scheduling.autoGenerateForTeacher(
            teacher: t,
            daysOfWeek: _daysOfWeek,
            timeSlots: slots,
            breakSlots: _breakSlots,
            clearExisting: _clearBeforeGen,
            sessionsPerSubject: int.tryParse(_sessionsPerSubjectCtrl.text) ?? 1,
            enforceTeacherWeeklyHours: true,
            teacherMaxPerDay: int.tryParse(_teacherMaxPerDayCtrl.text) ?? 0,
            classMaxPerDay: int.tryParse(_classMaxPerDayCtrl.text) ?? 0,
            subjectMaxPerDay: int.tryParse(_subjectMaxPerDayCtrl.text) ?? 0,
          );
        }
        total += created;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Génération (enseignants) terminée: $total cours créés.')),
        );
      }
      try {
        await _dbService.logAudit(
          category: 'timetable',
          action: 'auto_generate_teachers',
          details: 'teachers=${_teachers.length} slots=${slots.length} days=${_daysOfWeek.length} saturate=${_saturateAll ? 1 : 0}',
        );
      } catch (_) {}
    } finally {
      setState(() => _isGenerating = false);
      await _loadData();
    }
  }

  Future<void> _onGenerateForSelectedClass() async {
    final cls = _selectedClass();
    if (cls == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune classe sélectionnée.')),
      );
      return;
    }
    setState(() => _isGenerating = true);
    try {
      await _saveAutoGenPrefs();
      final created = _saturateAll
          ? await _scheduling.autoSaturateForClass(
              targetClass: cls,
              daysOfWeek: _daysOfWeek,
              timeSlots: List<String>.from(_timeSlots),
              breakSlots: _breakSlots,
              clearExisting: _clearBeforeGen,
            )
          : await _scheduling.autoGenerateForClass(
              targetClass: cls,
              daysOfWeek: _daysOfWeek,
              timeSlots: List<String>.from(_timeSlots),
              breakSlots: _breakSlots,
              clearExisting: _clearBeforeGen,
              sessionsPerSubject: int.tryParse(_sessionsPerSubjectCtrl.text) ?? 1,
              enforceTeacherWeeklyHours: true,
              teacherMaxPerDay: int.tryParse(_teacherMaxPerDayCtrl.text) ?? 0,
              classMaxPerDay: int.tryParse(_classMaxPerDayCtrl.text) ?? 0,
              subjectMaxPerDay: int.tryParse(_subjectMaxPerDayCtrl.text) ?? 0,
              blockDefaultSlots: int.tryParse(_blockDefaultCtrl.text) ?? 2,
              threeHourThreshold: double.tryParse(_threeHourThresholdCtrl.text) ?? 1.5,
            );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Génération: $created cours pour ${cls.name}.')),
        );
      }
      try {
        await _dbService.logAudit(
          category: 'timetable',
          action: 'auto_generate_class',
          details: 'class=${cls.name} year=${cls.academicYear} saturate=${_saturateAll ? 1 : 0}',
        );
      } catch (_) {}
    } finally {
      setState(() => _isGenerating = false);
      await _loadData();
    }
  }

  Future<void> _onGenerateForSelectedTeacher() async {
    final teacherName = _selectedTeacherFilter;
    if (teacherName == null || teacherName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun enseignant sélectionné.')),
      );
      return;
    }
    final teacher = _teachers.firstWhere(
      (t) => t.name == teacherName,
      orElse: () => Staff.empty(),
    );
    if (teacher.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enseignant introuvable.')),
      );
      return;
    }
    setState(() => _isGenerating = true);
    try {
      await _saveAutoGenPrefs();
      final created = _saturateAll
          ? await _scheduling.autoSaturateForTeacher(
              teacher: teacher,
              daysOfWeek: _daysOfWeek,
              timeSlots: List<String>.from(_timeSlots),
              breakSlots: _breakSlots,
              clearExisting: _clearBeforeGen,
            )
          : await _scheduling.autoGenerateForTeacher(
              teacher: teacher,
              daysOfWeek: _daysOfWeek,
              timeSlots: List<String>.from(_timeSlots),
              breakSlots: _breakSlots,
              clearExisting: _clearBeforeGen,
              sessionsPerSubject: int.tryParse(_sessionsPerSubjectCtrl.text) ?? 1,
              enforceTeacherWeeklyHours: true,
              teacherMaxPerDay: int.tryParse(_teacherMaxPerDayCtrl.text) ?? 0,
              classMaxPerDay: int.tryParse(_classMaxPerDayCtrl.text) ?? 0,
              subjectMaxPerDay: int.tryParse(_subjectMaxPerDayCtrl.text) ?? 0,
            );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Génération: $created cours pour $teacherName.')),
        );
      }
      try {
        await _dbService.logAudit(
          category: 'timetable',
          action: 'auto_generate_teacher',
          details: 'teacher=$teacherName saturate=${_saturateAll ? 1 : 0}',
        );
      } catch (_) {}
    } finally {
      setState(() => _isGenerating = false);
      await _loadData();
    }
  }

  Widget _buildTimetableDisplay(BuildContext context) {
    final theme = Theme.of(context);
    return DataTable(
      columnSpacing: 20,
      horizontalMargin: 10,
      dataRowMaxHeight: double.infinity, // Allow rows to expand vertically
      columns: [
        DataColumn(label: Text('Heure', style: theme.textTheme.titleMedium)),
        ..._daysOfWeek.map(
          (day) =>
              DataColumn(label: Text(day, style: theme.textTheme.titleMedium)),
        ),
      ],
      rows: _timeSlots.map((timeSlot) {
        return DataRow(
          cells: [
            DataCell(Text(timeSlot, style: theme.textTheme.bodyMedium)),
            ..._daysOfWeek.map((day) {
              final timeSlotParts = timeSlot.split(' - ');
              final slotStartTime = timeSlotParts[0];
              final slotEndTime = timeSlotParts.length > 1
                  ? timeSlotParts[1]
                  : slotStartTime;

              final filteredEntries = _timetableEntries.where((e) {
                final matchesSearch =
                    _searchQuery.isEmpty ||
                    e.className.toLowerCase().contains(_searchQuery) ||
                    e.teacher.toLowerCase().contains(_searchQuery) ||
                    e.subject.toLowerCase().contains(_searchQuery) ||
                    e.room.toLowerCase().contains(_searchQuery);

                if (_isClassView) {
                  final classKey = _classKeyFromValues(
                    e.className,
                    e.academicYear,
                  );
                  return e.dayOfWeek == day &&
                      e.startTime == slotStartTime &&
                      (_selectedClassKey == null ||
                          classKey == _selectedClassKey) &&
                      matchesSearch;
                } else {
                  return e.dayOfWeek == day &&
                      e.startTime == slotStartTime &&
                      (_selectedTeacherFilter == null ||
                          e.teacher == _selectedTeacherFilter) &&
                      matchesSearch;
                }
              });

              final entriesForSlot = filteredEntries.toList();
              final isBreak = _breakSlots.contains(timeSlot);
              final isUnavailableForTeacher =
                  !_isClassView &&
                  (_selectedTeacherFilter != null &&
                      _selectedTeacherFilter!.isNotEmpty) &&
                  _teacherUnavailKeys.contains('$day|$slotStartTime');

              return DataCell(
                DragTarget<TimetableEntry>(
                  onWillAccept: (data) => !isBreak && !isUnavailableForTeacher,
                  onAccept: (entry) async {
                    if (isBreak) return;
                    if (isUnavailableForTeacher &&
                        (entry.teacher == _selectedTeacherFilter)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Créneau indisponible pour l\'enseignant.',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    // Prevent conflicts (same class or same teacher at same time)
                    final conflict = _timetableEntries.any(
                      (e) =>
                          e.dayOfWeek == day &&
                          e.startTime == slotStartTime &&
                          (e.className == entry.className ||
                              (entry.teacher.isNotEmpty &&
                                  e.teacher == entry.teacher)) &&
                          e.id != entry.id,
                    );
                    if (conflict) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Conflit détecté (classe/enseignant déjà occupé).',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    // Insert new (from palette) or move existing
                    if (entry.id == null) {
                      final cls = _selectedClass();
                      if (cls == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Sélectionnez une classe avant d\'ajouter.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      final toCreate = TimetableEntry(
                        subject: entry.subject,
                        teacher: entry.teacher,
                        className: cls.name,
                        academicYear: cls.academicYear,
                        dayOfWeek: day,
                        startTime: slotStartTime,
                        endTime: slotEndTime,
                        room: entry.room,
                      );
                      await _dbService.insertTimetableEntry(toCreate);
                    } else {
                      // Preserve duration when moving
                      int? _toMin(String s) {
                        try {
                          final p = s.split(':');
                          return int.parse(p[0]) * 60 + int.parse(p[1]);
                        } catch (_) {
                          return null;
                        }
                      }

                      String _fmt(int m) {
                        final h = (m ~/ 60).toString().padLeft(2, '0');
                        final mi = (m % 60).toString().padLeft(2, '0');
                        return '$h:$mi';
                      }

                      final dur = (() {
                        final a = _toMin(entry.startTime);
                        final b = _toMin(entry.endTime);
                        if (a != null && b != null && b > a) return b - a;
                        final ss = _toMin(slotStartTime);
                        final se = _toMin(slotEndTime);
                        return (ss != null && se != null && se > ss)
                            ? se - ss
                            : null;
                      })();
                      final ns = _toMin(slotStartTime);
                      final ne = (ns != null && dur != null)
                          ? ns + dur
                          : _toMin(slotEndTime);
                      final newEnd = (ne != null) ? _fmt(ne) : slotEndTime;
                      final moved = TimetableEntry(
                        id: entry.id,
                        subject: entry.subject,
                        teacher: entry.teacher,
                        className: entry.className,
                        academicYear: entry.academicYear,
                        dayOfWeek: day,
                        startTime: slotStartTime,
                        endTime: newEnd,
                        room: entry.room,
                      );
                      await _dbService.updateTimetableEntry(moved);
                    }
                    await _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cours placé.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  builder: (ctx, candidate, rejected) {
                    final isActive = candidate.isNotEmpty;
                    return GestureDetector(
                      onTap: () => _showAddEditTimetableEntryDialog(
                        entry: entriesForSlot.isNotEmpty
                            ? entriesForSlot.first
                            : null,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isBreak
                              ? Colors.grey.withOpacity(0.15)
                              : isUnavailableForTeacher
                              ? const Color(0xFFE11D48).withOpacity(0.08)
                              : entriesForSlot.isNotEmpty
                              ? AppColors.primaryBlue.withOpacity(0.1)
                              : (isActive
                                    ? AppColors.primaryBlue.withOpacity(0.06)
                                    : Colors.transparent),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isBreak
                                ? Colors.grey
                                : isUnavailableForTeacher
                                ? const Color(0xFFE11D48)
                                : isActive
                                ? AppColors.primaryBlue
                                : (entriesForSlot.isNotEmpty
                                      ? AppColors.primaryBlue
                                      : Colors.grey.shade300),
                          ),
                        ),
                        child: entriesForSlot.isNotEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: entriesForSlot.map((entry) {
                                  final content = Text(
                                    '${entry.subject} ${entry.room}\n${entry.teacher} - ${entry.className}',
                                    style: theme.textTheme.bodyMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                  return Draggable<TimetableEntry>(
                                    data: entry,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryBlue
                                              .withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          '${entry.subject} (${entry.startTime})',
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.4,
                                      child: content,
                                    ),
                                    child: content,
                                  );
                                }).toList(),
                              )
                            : Center(
                                child: Text(
                                  isBreak ? 'Pause' : '+',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSubjectPalette(BuildContext context) {
    final theme = Theme.of(context);
    final cls = _selectedClass();
    if (cls == null || _subjects.isEmpty) return const SizedBox.shrink();
    Color _subjectColor(String name) {
      const palette = [
        Color(0xFF60A5FA),
        Color(0xFFF472B6),
        Color(0xFFF59E0B),
        Color(0xFF34D399),
        Color(0xFFA78BFA),
        Color(0xFFFB7185),
        Color(0xFF38BDF8),
        Color(0xFF10B981),
      ];
      final idx = name.codeUnits.fold<int>(
        0,
        (a, b) => (a + b) % palette.length,
      );
      return palette[idx];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Text(
              'Palette (glisser-déposer pour ajouter)',
              style: theme.textTheme.labelLarge,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _subjects.map((s) {
              final teacher = _findTeacherForSubject(s.name, cls)?.name ?? '';
              final col = _subjectColor(s.name);
              final chip = Chip(
                label: Text(
                  '${s.name}${teacher.isNotEmpty ? ' · $teacher' : ''}',
                ),
                backgroundColor: col.withOpacity(0.14),
              );
              return Draggable<TimetableEntry>(
                data: TimetableEntry(
                  subject: s.name,
                  teacher: teacher,
                  className: cls.name,
                  academicYear: cls.academicYear,
                  dayOfWeek: '',
                  startTime: '',
                  endTime: '',
                  room: '',
                ),
                feedback: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: col.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      s.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.4, child: chip),
                child: chip,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text('Légende', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _subjects.take(12).map((s) {
              final col = _subjectColor(s.name);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: col.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: col.withOpacity(0.5)),
                ),
                child: Text(s.name, style: theme.textTheme.bodySmall),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Advanced stacked grid with merged visual blocks per duration
  Widget _buildTimetableGrid(BuildContext context) {
    final theme = Theme.of(context);
    // Helpers
    int? toMin(String s) {
      s = s.trim();
      final upper = s.toUpperCase();
      bool pm = upper.endsWith('PM');
      bool am = upper.endsWith('AM');
      if (pm || am) {
        s = s.replaceAll(RegExp(r'(?i)\s*(AM|PM)\s*$'), '');
      }
      final parts = s.split(':');
      if (parts.length >= 2) {
        int? h = int.tryParse(parts[0]);
        int? m = int.tryParse(parts[1]);
        if (h == null || m == null) return null;
        if (pm && h < 12) h += 12;
        if (am && h == 12) h = 0;
        return h * 60 + m;
      }
      return null;
    }

    List<String> bounds() {
      final set = <String>{};
      for (final slot in _timeSlots) {
        final p = slot.split(' - ');
        if (p.isNotEmpty) set.add(p.first.trim());
        if (p.length > 1) set.add(p[1].trim());
      }
      final list = set.toList();
      list.sort((a, b) => (toMin(a) ?? 0).compareTo((toMin(b) ?? 0)));
      return list;
    }

    final boundaries = bounds();
    if (boundaries.length < 2) {
      return _buildTimetableDisplay(context); // fallback
    }
    int indexFor(String t) {
      int? tm = toMin(t);
      if (tm == null) return 0;
      int best = 0;
      int bestDiff = 1 << 30;
      for (int i = 0; i < boundaries.length; i++) {
        final diff = ((toMin(boundaries[i]) ?? 0) - tm).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          best = i;
        }
      }
      return best;
    }

    Color subjectColor(String name) {
      const palette = [
        Color(0xFF60A5FA),
        Color(0xFFF472B6),
        Color(0xFFF59E0B),
        Color(0xFF34D399),
        Color(0xFFA78BFA),
        Color(0xFFFB7185),
        Color(0xFF38BDF8),
        Color(0xFF10B981),
      ];
      final idx = name.codeUnits.fold<int>(
        0,
        (a, b) => (a + b) % palette.length,
      );
      return palette[idx];
    }

    // Filter for current view
    final entries = _timetableEntries.where((e) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          e.className.toLowerCase().contains(_searchQuery) ||
          e.teacher.toLowerCase().contains(_searchQuery) ||
          e.subject.toLowerCase().contains(_searchQuery) ||
          e.room.toLowerCase().contains(_searchQuery);
      if (_isClassView) {
        final classKey = _classKeyFromValues(e.className, e.academicYear);
        return (_selectedClassKey == null || classKey == _selectedClassKey) &&
            matchesSearch;
      } else {
        return (_selectedTeacherFilter == null ||
                e.teacher == _selectedTeacherFilter) &&
            matchesSearch;
      }
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final leftGutter = 90.0;
        final topGutter = 20.0;
        // Provide finite dimensions even when unconstrained (inside scroll views)
        const double defaultCol = 160.0;
        const double defaultRow = 64.0;
        final rowCount = boundaries.length - 1;
        final calcGridWidth = constraints.hasBoundedWidth
            ? (constraints.maxWidth - leftGutter).clamp(0.0, double.infinity)
            : defaultCol * _daysOfWeek.length;
        final calcGridHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - topGutter).clamp(0.0, double.infinity)
            : defaultRow * (rowCount > 0 ? rowCount : 1);
        final colWidth = (calcGridWidth / _daysOfWeek.length);
        final rowHeight = (calcGridHeight / (rowCount > 0 ? rowCount : 1));
        final stackWidth = leftGutter + colWidth * _daysOfWeek.length;
        final stackHeight =
            topGutter + rowHeight * (rowCount > 0 ? rowCount : 1);
        final children = <Widget>[];

        // Day headers
        for (int d = 0; d < _daysOfWeek.length; d++) {
          children.add(
            Positioned(
              left: leftGutter + d * colWidth,
              top: 0,
              width: colWidth,
              height: topGutter,
              child: Center(
                child: Text(_daysOfWeek[d], style: theme.textTheme.titleMedium),
              ),
            ),
          );
        }

        // Time labels + lines
        for (int i = 0; i < boundaries.length; i++) {
          final y = topGutter + i * rowHeight;
          children.add(
            Positioned(
              left: 0,
              top: y - 8,
              width: leftGutter - 10,
              height: 16,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(boundaries[i], style: theme.textTheme.bodySmall),
              ),
            ),
          );
          children.add(
            Positioned(
              left: leftGutter,
              right: 0,
              top: y,
              height: 1,
              child: Container(color: theme.dividerColor.withOpacity(0.3)),
            ),
          );
        }

        // Break overlay
        for (int i = 0; i < rowCount; i++) {
          final slot = '${boundaries[i]} - ${boundaries[i + 1]}';
          if (_breakSlots.contains(slot)) {
            children.add(
              Positioned(
                left: leftGutter,
                top: topGutter + i * rowHeight,
                width: colWidth * _daysOfWeek.length,
                height: rowHeight,
                child: Container(color: Colors.grey.withOpacity(0.12)),
              ),
            );
          }
        }

        // Teacher unavailability overlay (teacher view)
        if (!_isClassView &&
            _selectedTeacherFilter != null &&
            _selectedTeacherFilter!.isNotEmpty) {
          for (int i = 0; i < rowCount; i++) {
            for (int d = 0; d < _daysOfWeek.length; d++) {
              final key = '${_daysOfWeek[d]}|${boundaries[i]}';
              if (_teacherUnavailKeys.contains(key)) {
                children.add(
                  Positioned(
                    left: leftGutter + d * colWidth,
                    top: topGutter + i * rowHeight,
                    width: colWidth,
                    height: rowHeight,
                    child: Container(
                      color: const Color(0xFFE11D48).withOpacity(0.08),
                    ),
                  ),
                );
              }
            }
          }
        }

        // Drop zones per (day, segment)
        for (int i = 0; i < rowCount; i++) {
          final slotStart = boundaries[i];
          final slotEnd = boundaries[i + 1];
          for (int d = 0; d < _daysOfWeek.length; d++) {
            final isBreak = _breakSlots.contains('$slotStart - $slotEnd');
            final isUnavailable =
                !_isClassView &&
                (_selectedTeacherFilter != null &&
                    _selectedTeacherFilter!.isNotEmpty) &&
                _teacherUnavailKeys.contains('${_daysOfWeek[d]}|$slotStart');
            children.add(
              Positioned(
                left: leftGutter + d * colWidth,
                top: topGutter + i * rowHeight,
                width: colWidth,
                height: rowHeight,
                child: DragTarget<TimetableEntry>(
                  onWillAccept: (data) => !isBreak && !isUnavailable,
                  onAccept: (entry) async {
                    if (isBreak || isUnavailable) return;
                    final conflict = _timetableEntries.any(
                      (e) =>
                          e.dayOfWeek == _daysOfWeek[d] &&
                          e.startTime == slotStart &&
                          (e.className == entry.className ||
                              (entry.teacher.isNotEmpty &&
                                  e.teacher == entry.teacher)) &&
                          e.id != entry.id,
                    );
                    if (conflict) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Conflit détecté.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    if (entry.id == null) {
                      final cls = _selectedClass();
                      if (cls == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sélectionnez une classe.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      final toCreate = TimetableEntry(
                        subject: entry.subject,
                        teacher: entry.teacher,
                        className: cls.name,
                        academicYear: cls.academicYear,
                        dayOfWeek: _daysOfWeek[d],
                        startTime: slotStart,
                        endTime: slotEnd,
                        room: entry.room,
                      );
                      await _dbService.insertTimetableEntry(toCreate);
                    } else {
                      int? m(String s) => toMin(s);
                      String fmt(int v) =>
                          '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
                      final dur = (() {
                        final a = m(entry.startTime);
                        final b = m(entry.endTime);
                        if (a != null && b != null && b > a) return b - a;
                        final ss = m(slotStart);
                        final se = m(slotEnd);
                        return (ss != null && se != null && se > ss)
                            ? se - ss
                            : null;
                      })();
                      final ns = m(slotStart);
                      final ne = (ns != null && dur != null)
                          ? ns + dur
                          : m(slotEnd);
                      final newEnd = (ne != null) ? fmt(ne) : slotEnd;
                      final moved = TimetableEntry(
                        id: entry.id,
                        subject: entry.subject,
                        teacher: entry.teacher,
                        className: entry.className,
                        academicYear: entry.academicYear,
                        dayOfWeek: _daysOfWeek[d],
                        startTime: slotStart,
                        endTime: newEnd,
                        room: entry.room,
                      );
                      await _dbService.updateTimetableEntry(moved);
                    }
                    await _loadData();
                  },
                  builder: (ctx, cand, rej) => GestureDetector(
                    onTap: () => _showAddEditTimetableEntryDialog(
                      prefilledDay: _daysOfWeek[d],
                      prefilledStart: slotStart,
                      prefilledEnd: slotEnd,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );
          }
        }

        // Render entries as positioned blocks
        for (final e in entries) {
          final dayIndex = _daysOfWeek.indexOf(e.dayOfWeek);
          if (dayIndex < 0) continue;
          final sIdx = indexFor(e.startTime);
          int eIdx = indexFor(e.endTime);
          if (eIdx <= sIdx) eIdx = (sIdx + 1).clamp(0, boundaries.length - 1);
          final top = topGutter + sIdx * rowHeight + 2;
          final height = (eIdx - sIdx) * rowHeight - 4;
          final color = subjectColor(e.subject);
          final text =
              '${e.subject} ${e.room}\n${e.teacher} - ${e.className}\n${e.startTime} - ${e.endTime}';
          final content = Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.8)),
            ),
            child: Text(
              text,
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          );
          children.add(
            Positioned(
              left: leftGutter + dayIndex * colWidth + 2,
              top: top,
              width: colWidth - 4,
              height: height > 28 ? height : 28,
              child: Draggable<TimetableEntry>(
                data: e,
                feedback: Material(color: Colors.transparent, child: content),
                childWhenDragging: Opacity(opacity: 0.4, child: content),
                child: GestureDetector(
                  onTap: () => _showAddEditTimetableEntryDialog(entry: e),
                  child: content,
                ),
              ),
            ),
          );
        }

        return SizedBox(
          width: stackWidth.isFinite ? stackWidth : null,
          height: stackHeight.isFinite ? stackHeight : null,
          child: Stack(children: children),
        );
      },
    );
  }

  Future<void> _autoGenerateForSelectedClass() async {
    final cls = _classFromKey(_selectedClassKey);
    if (cls == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner une classe.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool clearExisting = false;
    int sessionsPerSubject = 1;
    int teacherMaxPerDay = 0;
    int classMaxPerDay = 0;
    int subjectMaxPerDay = 0;

    final confirmed = await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Auto-générer pour la classe'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Classe: ${_classLabel(cls)}'),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: clearExisting,
                  onChanged: (v) => setState(() => clearExisting = v ?? false),
                  title: const Text("Vider l'emploi du temps avant génération"),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Séances par matière (hebdo)'),
                    DropdownButton<int>(
                      value: sessionsPerSubject,
                      items: const [1, 2, 3]
                          .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                          .toList(),
                      onChanged: (v) => setState(() => sessionsPerSubject = v ?? 1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Max cours/jour (classe)'),
                    DropdownButton<int>(
                      value: classMaxPerDay,
                      items: const [0, 3, 4, 5, 6, 7, 8]
                          .map((n) => DropdownMenuItem(value: n, child: Text(n == 0 ? 'Illimité' : '$n')))
                          .toList(),
                      onChanged: (v) => setState(() => classMaxPerDay = v ?? 0),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Max séances/jour par matière'),
                    DropdownButton<int>(
                      value: subjectMaxPerDay,
                      items: const [0, 1, 2, 3]
                          .map((n) => DropdownMenuItem(value: n, child: Text(n == 0 ? 'Illimité' : '$n')))
                          .toList(),
                      onChanged: (v) => setState(() => subjectMaxPerDay = v ?? 0),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Max cours/jour par enseignant'),
                    DropdownButton<int>(
                      value: teacherMaxPerDay,
                      items: const [0, 3, 4, 5, 6, 7, 8]
                          .map((n) => DropdownMenuItem(value: n, child: Text(n == 0 ? 'Illimité' : '$n')))
                          .toList(),
                      onChanged: (v) => setState(() => teacherMaxPerDay = v ?? 0),
                    ),
                  ],
                ),
],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Générer'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;

    // After dialog closes, run generation
    final created = await _scheduling.autoGenerateForClass(
      targetClass: cls,
      daysOfWeek: _daysOfWeek,
      timeSlots: _timeSlots,
      breakSlots: _breakSlots,
      clearExisting: clearExisting,
      sessionsPerSubject: sessionsPerSubject,
      teacherMaxPerDay: teacherMaxPerDay == 0 ? null : teacherMaxPerDay,
      classMaxPerDay: classMaxPerDay == 0 ? null : classMaxPerDay,
      subjectMaxPerDay: subjectMaxPerDay == 0 ? null : subjectMaxPerDay,
    );
    await _loadData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Génération terminée: $created cours ajoutés.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _autoGenerateForSelectedTeacher() async {
    if (_selectedTeacherFilter == null || _selectedTeacherFilter!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un enseignant.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final teacher = _teachers.firstWhere(
      (t) => t.name == _selectedTeacherFilter,
      orElse: () => Staff.empty(),
    );
    if (teacher.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enseignant introuvable.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool clearExisting = false;
    int sessionsPerSubject = 1;
    int teacherMaxPerDay = 0;
    int weeklyHours = teacher.weeklyHours ?? 0;
    final List<int> weeklyHoursOptions = [0, 5, 10, 12, 15, 18, 20, 24, 30, 36, 40];
    if (weeklyHours != 0 && !weeklyHoursOptions.contains(weeklyHours)) {
      weeklyHoursOptions.insert(1, weeklyHours);
    }
    int subjectMaxPerDay = 0;
    int classMaxPerDay = 0;

    final confirmed = await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text("Auto-générer pour l'enseignant"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Enseignant: ${teacher.name}'),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: clearExisting,
                  onChanged: (v) => setState(() => clearExisting = v ?? false),
                  title: const Text('Vider ses cours avant génération'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Séances par matière (hebdo)'),
                    DropdownButton<int>(
                      value: sessionsPerSubject,
                      items: const [1, 2, 3]
                          .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                          .toList(),
                      onChanged: (v) => setState(() => sessionsPerSubject = v ?? 1),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Heures hebdomadaires à enseigner'),
                    DropdownButton<int>(
                      value: weeklyHours,
                      items: weeklyHoursOptions
                          .map((n) => DropdownMenuItem<int>(value: n, child: Text(n == 0 ? 'Illimité' : '$n')))
                          .toList(),
                      onChanged: (v) => setState(() => weeklyHours = v ?? 0),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Max cours/jour (classe)'),
                    DropdownButton<int>(
                      value: classMaxPerDay,
                      items: const [0, 3, 4, 5, 6, 7, 8]
                          .map((n) => DropdownMenuItem(value: n, child: Text(n == 0 ? 'Illimité' : '$n')))
                          .toList(),
                      onChanged: (v) => setState(() => classMaxPerDay = v ?? 0),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Max séances/jour par matière'),
                    DropdownButton<int>(
                      value: subjectMaxPerDay,
                      items: const [0, 1, 2, 3]
                          .map((n) => DropdownMenuItem(value: n, child: Text(n == 0 ? 'Illimité' : '$n')))
                          .toList(),
                      onChanged: (v) => setState(() => subjectMaxPerDay = v ?? 0),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Max cours/jour par enseignant'),
                    DropdownButton<int>(
                      value: teacherMaxPerDay,
                      items: const [0, 3, 4, 5, 6, 7, 8]
                          .map((n) => DropdownMenuItem(value: n, child: Text(n == 0 ? 'Illimité' : '$n')))
                          .toList(),
                      onChanged: (v) => setState(() => teacherMaxPerDay = v ?? 0),
                    ),
                  ],
                ),
],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Générer'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;

    // Persist weekly hours preference for this teacher
    try {
      await _dbService.updateTeacherWeeklyHours(
        teacher.id,
        weeklyHours == 0 ? null : weeklyHours,
      );
    } catch (_) {}

    final created = await _scheduling.autoGenerateForTeacher(
      teacher: teacher,
      daysOfWeek: _daysOfWeek,
      timeSlots: _timeSlots,
      breakSlots: _breakSlots,
      clearExisting: clearExisting,
      sessionsPerSubject: sessionsPerSubject,
      teacherMaxPerDay: teacherMaxPerDay == 0 ? null : teacherMaxPerDay,
      teacherWeeklyHours: weeklyHours,
      subjectMaxPerDay: subjectMaxPerDay == 0 ? null : subjectMaxPerDay,
      classMaxPerDay: classMaxPerDay == 0 ? null : classMaxPerDay,
    );
    await _loadData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Génération terminée: $created cours ajoutés.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _showEditGridDialog() async {
    final days = List<String>.from(_daysOfWeek);
    final slots = List<String>.from(_timeSlots);
    final breaks = Set<String>.from(_breakSlots);

    final daysController = TextEditingController();
    final slotStartController = TextEditingController();
    final slotEndController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Éditer jours / créneaux / pauses'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Jours', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: days
                          .map(
                            (d) => Chip(
                              label: Text(d),
                              onDeleted: () {
                                setState(() {
                                  days.remove(d);
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: daysController,
                            decoration: const InputDecoration(
                              labelText: 'Ajouter un jour (ex: Dimanche)',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final v = daysController.text.trim();
                            if (v.isNotEmpty && !days.contains(v)) {
                              setState(() => days.add(v));
                              daysController.clear();
                            }
                          },
                          child: const Text('Ajouter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Créneaux (HH:mm - HH:mm)',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: slots
                          .map(
                            (s) => InputChip(
                              label: Text(s),
                              onDeleted: () {
                                setState(() => slots.remove(s));
                              },
                            ),
                          )
                          .toList(),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: slotStartController,
                            decoration: const InputDecoration(
                              labelText: 'Début (ex: 08:00)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: slotEndController,
                            decoration: const InputDecoration(
                              labelText: 'Fin (ex: 09:00)',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final a = slotStartController.text.trim();
                            final b = slotEndController.text.trim();
                            if (a.isNotEmpty && b.isNotEmpty) {
                              final slot = '$a - $b';
                              if (!slots.contains(slot)) {
                                setState(() => slots.add(slot));
                                slotStartController.clear();
                                slotEndController.clear();
                              }
                            }
                          },
                          child: const Text('Ajouter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pauses (sélectionner les créneaux à marquer comme pause)',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Column(
                      children: slots
                          .map(
                            (s) => CheckboxListTile(
                              title: Text(s),
                              value: breaks.contains(s),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    breaks.add(s);
                                  } else {
                                    breaks.remove(s);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            ElevatedButton(
              onPressed: () async {
                await ttp.saveDays(days);
                await ttp.saveSlots(slots);
                await ttp.saveBreakSlots(breaks);
                Navigator.of(context).pop();
                await _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Configuration enregistrée.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showTeacherUnavailabilityDialog() async {
    if (_selectedTeacherFilter == null || _selectedTeacherFilter!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un enseignant.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final teacherName = _selectedTeacherFilter!;
    final year = await getCurrentAcademicYear();
    // Local editable copy
    final Set<String> edits = Set<String>.from(_teacherUnavailKeys);

    await showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text('Indisponibilités • $teacherName'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _daysOfWeek.map((day) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(day, style: theme.textTheme.titleSmall),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _timeSlots.map((slot) {
                          final slotStart = slot.split(' - ').first;
                          final key = '$day|$slotStart';
                          final checked = edits.contains(key);
                          return FilterChip(
                            selected: checked,
                            label: Text(slot),
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  edits.add(key);
                                } else {
                                  edits.remove(key);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            ElevatedButton(
              onPressed: () async {
                final rows = edits.map((k) {
                  final parts = k.split('|');
                  return {'dayOfWeek': parts[0], 'startTime': parts[1]};
                }).toList();
                await _dbService.saveTeacherUnavailability(
                  teacherName: teacherName,
                  academicYear: year,
                  slots: rows,
                );
                Navigator.of(context).pop();
                await _loadTeacherUnavailability(teacherName, year);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Indisponibilités enregistrées.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  // Copied _buildHeader method from grades_page.dart
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
                      Icons.calendar_today, // Changed icon to calendar_today
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des Emplois du Temps', // Changed title
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Créez et gérez les plannings de cours par classe et par enseignant.', // Changed description
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
              // Removed quick actions and notification icon for simplicity, can be added later if needed
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
          const SizedBox(height: 12), // Add spacing
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Rechercher un emploi du temps...',
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
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  void _showAddEditTimetableEntryDialog({
    TimetableEntry? entry,
    String? prefilledDay,
    String? prefilledStart,
    String? prefilledEnd,
  }) {
    final _formKey = GlobalKey<FormState>();
    final scaffoldMessenger = ScaffoldMessenger.of(
      context,
    ); // Get ScaffoldMessengerState here
    String? selectedSubject = entry?.subject;
    String? selectedTeacher = entry?.teacher;
    String? selectedClassKey = entry != null
        ? _classKeyFromValues(entry.className, entry.academicYear)
        : _selectedClassKey;
    String? selectedDay = entry?.dayOfWeek ?? prefilledDay;
    TextEditingController startTimeController = TextEditingController(
      text: entry?.startTime ?? prefilledStart,
    );
    TextEditingController endTimeController = TextEditingController(
      text: entry?.endTime ?? prefilledEnd,
    );
    TextEditingController roomController = TextEditingController(
      text: entry?.room,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                children: [
                  Icon(
                    entry == null ? Icons.add_box : Icons.edit,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry == null
                          ? 'Ajouter un cours à l\'emploi du temps'
                          : 'Modifier le cours',
                      style: Theme.of(context).textTheme.headlineMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Matière',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.book_outlined),
                  ),
                  isDense: true,
                  isExpanded: true,
                  value: (() {
                    final items = _subjects.map((s) => s.name).toSet();
                    return (selectedSubject != null &&
                            items.contains(selectedSubject))
                        ? selectedSubject
                        : null;
                  })(),
                  items: _subjects
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.name,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => selectedSubject = value,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Enseignant',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outlined),
                  ),
                  isDense: true,
                  isExpanded: true,
                  value: (() {
                    final items = _teachers.map((t) => t.name).toSet();
                    return (selectedTeacher != null &&
                            items.contains(selectedTeacher))
                        ? selectedTeacher
                        : null;
                  })(),
                  items: _teachers
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.name,
                          child: Text(t.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => selectedTeacher = value,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Classe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  isDense: true,
                  isExpanded: true,
                  value: (() {
                    final items = _classes.map((c) => _classKey(c)).toSet();
                    if (selectedClassKey != null &&
                        items.contains(selectedClassKey)) {
                      return selectedClassKey;
                    }
                    if (_selectedClassKey != null &&
                        items.contains(_selectedClassKey)) {
                      return _selectedClassKey;
                    }
                    return null;
                  })(),
                  items: _classes
                      .map(
                        (c) => DropdownMenuItem(
                          value: _classKey(c),
                          child: Text(_classLabel(c)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => selectedClassKey = value,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Jour de la semaine',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  isDense: true,
                  isExpanded: true,
                  value: (() {
                    return (selectedDay != null &&
                            _daysOfWeek.contains(selectedDay))
                        ? selectedDay
                        : null;
                  })(),
                  items: _daysOfWeek
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (value) => selectedDay = value,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: startTimeController,
                  decoration: const InputDecoration(
                    labelText: 'Heure de début',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time_outlined),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (picked != null) {
                      startTimeController.text = picked.format(context);
                    }
                  },
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: endTimeController,
                  decoration: const InputDecoration(
                    labelText: 'Heure de fin',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time_outlined),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (picked != null) {
                      endTimeController.text = picked.format(context);
                    }
                  },
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: roomController,
                  decoration: const InputDecoration(
                    labelText: 'Salle',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.room_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                final classData = _classFromKey(selectedClassKey);
                if (classData == null) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Classe introuvable. Veuillez réessayer.'),
                    ),
                  );
                  return;
                }
                final newEntry = TimetableEntry(
                  id: entry?.id, // Pass existing ID if editing
                  subject: selectedSubject!,
                  teacher: selectedTeacher!,
                  className: classData.name,
                  academicYear: classData.academicYear,
                  dayOfWeek: selectedDay!,
                  startTime: startTimeController.text,
                  endTime: endTimeController.text,
                  room: roomController.text,
                );

                if (entry == null) {
                  await _dbService.insertTimetableEntry(newEntry);
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Cours ajouté avec succès.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  await _dbService.updateTimetableEntry(newEntry);
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Cours modifié avec succès.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                Navigator.of(context).pop();
                _loadData(); // Reload data to update the display
              }
            },
            child: Text(entry == null ? 'Enregistrer' : 'Modifier'),
          ),
          if (entry != null) // Add delete button for existing entries
            ElevatedButton(
              onPressed: () async {
                // Show confirmation dialog
                final bool confirmDelete =
                    await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          backgroundColor: Theme.of(context).cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFE11D48),
                              ),
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
                          content: const Text(
                            'Êtes-vous sûr de vouloir supprimer ce cours ?',
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Annuler'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE11D48),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Supprimer'),
                            ),
                          ],
                        );
                      },
                    ) ??
                    false; // In case dialog is dismissed by tapping outside

                if (confirmDelete) {
                  final TimetableEntry? deletedEntry =
                      entry; // Store the entry before deletion
                  await _dbService.deleteTimetableEntry(
                    deletedEntry!.id!,
                  ); // Delete the entry
                  Navigator.of(context).pop(); // Close the add/edit dialog
                  _loadData(); // Reload data to update the display
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Cours supprimé avec succès.'),
                      backgroundColor: Colors.green,
                      action: SnackBarAction(
                        label: 'Annuler',
                        onPressed: () async {
                          if (deletedEntry != null) {
                            await _dbService.insertTimetableEntry(deletedEntry);
                            _loadData(); // Reload data to update the display
                            // Dismiss the current dialog first if it's still open
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            }
                            // Now show the SnackBar from the main Scaffold's context
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text('Suppression annulée.'),
                                backgroundColor: Colors.blue,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Supprimer'),
            ),
        ],
      ),
    );
  }

  Future<void> _exportTimetableToPdf({required String exportBy}) async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return; // User canceled the picker

    if (_schoolInfo == null) {
      await _loadData(); // Attempt to load data if not already loaded
      if (_schoolInfo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Informations de l\'école non disponibles. Veuillez configurer les informations de l\'école dans les paramètres.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final String currentAcademicYear = await getCurrentAcademicYear();

    final classFilter = _classFromKey(_selectedClassKey);
    final filteredEntries = _timetableEntries.where((e) {
      if (exportBy == 'class') {
        if (classFilter == null) return true;
        return e.className == classFilter.name &&
            e.academicYear == classFilter.academicYear;
      } else {
        // teacher
        return _selectedTeacherFilter == null ||
            e.teacher == _selectedTeacherFilter;
      }
    }).toList();

    final classLabel = classFilter != null ? _classLabel(classFilter) : '';
    final title = exportBy == 'class'
        ? 'Emploi du temps de la classe $classLabel'
        : 'Emploi du temps du professeur(e) ${_selectedTeacherFilter ?? ''}';

    final bytes = await PdfService.generateTimetablePdf(
      schoolInfo: _schoolInfo!,
      academicYear: currentAcademicYear,
      daysOfWeek: _daysOfWeek,
      timeSlots: _timeSlots,
      timetableEntries: filteredEntries,
      title: title,
    );

    final fileName = exportBy == 'class'
        ? 'emploi du temps de la classe $classLabel.pdf'
        : 'emploi du temps du professeur(e) ${_selectedTeacherFilter ?? ''}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(bytes);
    OpenFile.open(file.path);
  }

  Future<void> _exportTimetableToExcel({required String exportBy}) async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return; // User canceled the picker

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Emploi du Temps'];

    // Header row
    sheetObject
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue(
      'Heure',
    );
    for (int d = 0; d < _daysOfWeek.length; d++) {
      sheetObject
          .cell(CellIndex.indexByColumnRow(columnIndex: d + 1, rowIndex: 0))
          .value = TextCellValue(
        _daysOfWeek[d],
      );
    }

    Color _subjectColor(String name) {
      const palette = [
        Color(0xFF60A5FA),
        Color(0xFFF472B6),
        Color(0xFFF59E0B),
        Color(0xFF34D399),
        Color(0xFFA78BFA),
        Color(0xFFFB7185),
        Color(0xFF38BDF8),
        Color(0xFF10B981),
      ];
      final idx = name.codeUnits.fold<int>(
        0,
        (a, b) => (a + b) % palette.length,
      );
      return palette[idx];
    }

    String _hex(Color c) =>
        '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}';

    final classFilter = _classFromKey(_selectedClassKey);
    final classLabel = classFilter != null ? _classLabel(classFilter) : '';

    for (int r = 0; r < _timeSlots.length; r++) {
      final timeSlot = _timeSlots[r];
      final timeSlotParts = timeSlot.split(' - ');
      final slotStartTime = timeSlotParts[0];
      sheetObject
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1))
          .value = TextCellValue(
        timeSlot,
      );
      for (int d = 0; d < _daysOfWeek.length; d++) {
        final day = _daysOfWeek[d];
        final entriesForSlot = _timetableEntries.where((e) {
          if (exportBy == 'class') {
            return e.dayOfWeek == day &&
                e.startTime == slotStartTime &&
                (classFilter == null ||
                    (e.className == classFilter.name &&
                        e.academicYear == classFilter.academicYear));
          } else {
            return e.dayOfWeek == day &&
                e.startTime == slotStartTime &&
                (_selectedTeacherFilter == null ||
                    e.teacher == _selectedTeacherFilter);
          }
        }).toList();

        final cell = sheetObject.cell(
          CellIndex.indexByColumnRow(columnIndex: d + 1, rowIndex: r + 1),
        );
        if (entriesForSlot.isNotEmpty) {
          final first = entriesForSlot.first;
          final text = entriesForSlot
              .map(
                (e) => '${e.subject} ${e.room}\n${e.teacher} - ${e.className}',
              )
              .join('\n\n');
          cell.value = TextCellValue(text);
          cell.cellStyle = CellStyle(
            backgroundColorHex: _hex(_subjectColor(first.subject)).excelColor,
          );
        } else {
          cell.value = TextCellValue('');
        }
      }
    }

    final fileName = exportBy == 'class'
        ? 'emploi du temps de la classe $classLabel.xlsx'
        : 'emploi du temps du professeur(e) ${_selectedTeacherFilter ?? ''}.xlsx';
    final file = File('$directory/$fileName');
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
      OpenFile.open(file.path);
    }
  }
}
