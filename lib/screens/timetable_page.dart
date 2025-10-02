import 'package:flutter/material.dart';
import 'package:school_manager/constants/colors.dart';



import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/utils/academic_year.dart';
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

class _TimetablePageState extends State<TimetablePage> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';

  String? _selectedClassKey;
  String? _selectedTeacherFilter;
  bool _isClassView = true;

  List<Class> _classes = [];
  List<Staff> _teachers = [];
  List<Course> _subjects = [];
  List<TimetableEntry> _timetableEntries = []; // Add this line to define the timetable entries
  SchoolInfo? _schoolInfo;

  // Label de l'année académique courante (ex: "2025-2026"). Nullable pour compatibilité.
  String? _currentAcademicYearLabel;

  String _classKey(Class c) => '${c.name}:::${c.academicYear}';
  String _classKeyFromValues(String name, String academicYear) => '$name:::${academicYear}';
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

  final List<String> _daysOfWeek = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];

  final List<String> _timeSlots = [
    '08:00 - 09:00',
    '09:00 - 10:00',
    '10:00 - 11:00',
    '11:00 - 12:00',
    '13:00 - 14:00',
    '14:00 - 15:00',
    '15:00 - 16:00',
  ];

  final DatabaseService _dbService = DatabaseService();

  @override
  void initState() {
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    super.initState();
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

    // Construire les créneaux horaires dynamiquement à partir des entrées
    final Set<String> uniqueTimes = {};
    for (var entry in _timetableEntries) {
      try {
        if (entry.startTime != null && entry.startTime.toString().isNotEmpty) {
          uniqueTimes.add(entry.startTime.toString());
        }
        if (entry.endTime != null && entry.endTime.toString().isNotEmpty) {
          uniqueTimes.add(entry.endTime.toString());
        }
      } catch (_) {
        // ignore
      }
    }

    // Si aucune entrée, utiliser des créneaux par défaut
    if (uniqueTimes.isEmpty) {
      uniqueTimes.addAll([
        '08:00',
        '09:00',
        '10:00',
        '11:00',
        '12:00',
        '13:00',
        '14:00',
        '15:00',
        '16:00'
      ]);
    }

    List<String> sortedUniqueTimes = uniqueTimes.toList();
    // Tri robuste des chaînes de temps au format HH:mm
    sortedUniqueTimes.sort((a, b) {
      try {
        final aParts = a.split(':');
        final bParts = b.split(':');
        final aHour = int.parse(aParts[0]);
        final aMinute = int.parse(aParts[1]);
        final bHour = int.parse(bParts[0]);
        final bMinute = int.parse(bParts[1]);
        if (aHour != bHour) return aHour.compareTo(bHour);
        return aMinute.compareTo(bMinute);
      } catch (_) {
        return a.compareTo(b);
      }
    });

    // Construire les intervalles (ex: 08:00 - 09:00)
    _timeSlots.clear();
    for (int i = 0; i < sortedUniqueTimes.length - 1; i++) {
      _timeSlots.add('${sortedUniqueTimes[i]} - ${sortedUniqueTimes[i + 1]}');
    }

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
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
                            border: OutlineInputBorder(),
                          ),
                          items: _classes.map((cls) {
                            return DropdownMenuItem<String>(
                              value: _classKey(cls),
                              child: Text(_classLabel(cls), style: theme.textTheme.bodyMedium),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedClassKey = newValue;
                            });
                          },
                        ),
                      )
                    else
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedTeacherFilter,
                          decoration: InputDecoration(
                            labelText: 'Filtrer par Enseignant',
                            labelStyle: theme.textTheme.bodyMedium,
                            border: OutlineInputBorder(),
                          ),
                          items: _teachers.map((teacher) {
                            return DropdownMenuItem<String>(
                              value: teacher.name,
                              child: Text(teacher.name, style: theme.textTheme.bodyMedium),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedTeacherFilter = newValue;
                            });
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
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: ListView.builder(
                    itemCount: _classes.length,
                    itemBuilder: (context, index) {
                      final aClass = _classes[index];
                      return ListTile(
                        title: Text(_classLabel(aClass), style: theme.textTheme.bodyMedium),
                        selected: _classKey(aClass) == _selectedClassKey,
                        onTap: () {
                          setState(() {
                            _selectedClassKey = _classKey(aClass);
                          });
                        },
                      );
                    },
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildTimetableDisplay(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableDisplay(BuildContext context) {
    final theme = Theme.of(context);
    return DataTable(
      columnSpacing: 20,
      horizontalMargin: 10,
      dataRowMaxHeight: double.infinity, // Allow rows to expand vertically
      columns: [
        DataColumn(label: Text('Heure', style: theme.textTheme.titleMedium)),
        ..._daysOfWeek.map((day) => DataColumn(label: Text(day, style: theme.textTheme.titleMedium))),
      ],
      rows: _timeSlots.map((timeSlot) {
        return DataRow(
          cells: [
            DataCell(Text(timeSlot, style: theme.textTheme.bodyMedium)),
            ..._daysOfWeek.map((day) {
              final timeSlotParts = timeSlot.split(' - ');
              final slotStartTime = timeSlotParts[0];

              final filteredEntries = _timetableEntries.where((e) {
                final matchesSearch = _searchQuery.isEmpty ||
                    e.className.toLowerCase().contains(_searchQuery) ||
                    e.teacher.toLowerCase().contains(_searchQuery) ||
                    e.subject.toLowerCase().contains(_searchQuery) ||
                    e.room.toLowerCase().contains(_searchQuery);

                if (_isClassView) {
                  final classKey = _classKeyFromValues(e.className, e.academicYear);
                  return e.dayOfWeek == day &&
                      e.startTime == slotStartTime &&
                      (_selectedClassKey == null || classKey == _selectedClassKey) &&
                      matchesSearch;
                } else {
                  return e.dayOfWeek == day &&
                         e.startTime == slotStartTime &&
                         (_selectedTeacherFilter == null || e.teacher == _selectedTeacherFilter) &&
                         matchesSearch;
                }
              });

              final entriesForSlot = filteredEntries.toList();

              return DataCell(
                GestureDetector(
                  onTap: () => _showAddEditTimetableEntryDialog(entry: entriesForSlot.isNotEmpty ? entriesForSlot.first : null),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: entriesForSlot.isNotEmpty ? AppColors.primaryBlue.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: entriesForSlot.isNotEmpty ? AppColors.primaryBlue : Colors.grey.shade300),
                    ),
                    child: entriesForSlot.isNotEmpty
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: entriesForSlot.map((entry) => Text(
                              '${entry.subject} ${entry.room}\n${entry.teacher} - ${entry.className}',
                              style: theme.textTheme.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )).toList(),
                          )
                        : Center(child: Text('+', style: theme.textTheme.bodyMedium)),
                  ),
                ),
              );
            }),
          ],
        );
      }).toList(),
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
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
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
              hintStyle: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6)),
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
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  void _showAddEditTimetableEntryDialog({TimetableEntry? entry}) {
    final _formKey = GlobalKey<FormState>();
    final scaffoldMessenger = ScaffoldMessenger.of(context); // Get ScaffoldMessengerState here
    String? selectedSubject = entry?.subject;
    String? selectedTeacher = entry?.teacher;
    String? selectedClassKey = entry != null
        ? _classKeyFromValues(entry.className, entry.academicYear)
        : _selectedClassKey;
    String? selectedDay = entry?.dayOfWeek;
    TextEditingController startTimeController = TextEditingController(text: entry?.startTime);
    TextEditingController endTimeController = TextEditingController(text: entry?.endTime);
    TextEditingController roomController = TextEditingController(text: entry?.room);

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
                  Icon(entry == null ? Icons.add_box : Icons.edit, color: AppColors.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry == null ? 'Ajouter un cours à l\'emploi du temps' : 'Modifier le cours',
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
                  value: selectedSubject,
                  items: _subjects.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                  onChanged: (value) => selectedSubject = value,
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Enseignant', 
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outlined),
                  ),
                  value: selectedTeacher,
                  items: _teachers.map((t) => DropdownMenuItem(value: t.name, child: Text(t.name))).toList(),
                  onChanged: (value) => selectedTeacher = value,
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Classe', 
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  value: selectedClassKey,
                  items: _classes
                      .map((c) => DropdownMenuItem(
                            value: _classKey(c),
                            child: Text(_classLabel(c)),
                          ))
                      .toList(),
                  onChanged: (value) => selectedClassKey = value,
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Jour de la semaine', 
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  value: selectedDay,
                  items: _daysOfWeek.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (value) => selectedDay = value,
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
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
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
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
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
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
                    const SnackBar(content: Text('Classe introuvable. Veuillez réessayer.')),
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
                    const SnackBar(content: Text('Cours ajouté avec succès.'), backgroundColor: Colors.green),
                  );
                } else {
                  await _dbService.updateTimetableEntry(newEntry);
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Cours modifié avec succès.'), backgroundColor: Colors.green),
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
                final bool confirmDelete = await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      backgroundColor: Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFE11D48)),
                          SizedBox(width: 8),
                          Text('Confirmer la suppression', style: TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      content: const Text('Êtes-vous sûr de vouloir supprimer ce cours ?'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Annuler'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48), foregroundColor: Colors.white),
                          child: const Text('Supprimer'),
                        ),
                      ],
                    );
                  },
                ) ?? false; // In case dialog is dismissed by tapping outside

                if (confirmDelete) {
                    final TimetableEntry? deletedEntry = entry; // Store the entry before deletion
                    await _dbService.deleteTimetableEntry(deletedEntry!.id!); // Delete the entry
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
                                const SnackBar(content: Text('Suppression annulée.'), backgroundColor: Colors.blue),
                              );
                            }
                          },
                        ),
                      ),
                    );
                  }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
          const SnackBar(content: Text('Informations de l\'école non disponibles. Veuillez configurer les informations de l\'école dans les paramètres.'), backgroundColor: Colors.red),
        );
        return;
      }
    }

    final String currentAcademicYear = await getCurrentAcademicYear();

    final classFilter = _classFromKey(_selectedClassKey);
    final filteredEntries = _timetableEntries.where((e) {
      if (exportBy == 'class') {
        if (classFilter == null) return true;
        return e.className == classFilter.name && e.academicYear == classFilter.academicYear;
      } else { // teacher
        return _selectedTeacherFilter == null || e.teacher == _selectedTeacherFilter;
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

    // Headers
    sheetObject.appendRow([TextCellValue('Heure'), ..._daysOfWeek.map((day) => TextCellValue(day))]);

    // Add data rows
    final classFilter = _classFromKey(_selectedClassKey);
    final classLabel = classFilter != null ? _classLabel(classFilter) : '';

    for (var timeSlot in _timeSlots) {
      final timeSlotParts = timeSlot.split(' - ');
      final slotStartTime = timeSlotParts[0];

      List<CellValue> row = [TextCellValue(timeSlot)];
      for (var day in _daysOfWeek) {
        final entriesForSlot = _timetableEntries.where((e) {
          if (exportBy == 'class') {
            return e.dayOfWeek == day &&
                e.startTime == slotStartTime &&
                (classFilter == null || (e.className == classFilter.name && e.academicYear == classFilter.academicYear));
          } else { // teacher
            return e.dayOfWeek == day &&
                e.startTime == slotStartTime &&
                (_selectedTeacherFilter == null || e.teacher == _selectedTeacherFilter);
          }
        }).toList();

        if (entriesForSlot.isNotEmpty) {
          String cellText = entriesForSlot.map((entry) {
            return '${entry.subject} ${entry.room}\n${entry.teacher} - ${entry.className}';
          }).join('\n\n');
          row.add(TextCellValue(cellText));
        } else {
          row.add(TextCellValue(''));
        }
      }
      sheetObject.appendRow(row);
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
