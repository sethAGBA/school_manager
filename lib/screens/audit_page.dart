import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/models/student.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';


class AuditPage extends StatefulWidget {
  const AuditPage({Key? key}) : super(key: key);

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _searchUser = TextEditingController();
  String? _selectedCategory;
  String? _selectedUser; // Filtre par utilisateur exact
  String _sortOrder = 'desc'; // 'desc' (Plus récent) ou 'asc' (Plus ancien)
  String? _statusFilter; // null: tous, 'success', 'failure'
  DateTime? _selectedDate; // Filtre par date (journée)
  String? _quickRange; // 'today' | 'week' | 'month'
  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];
  Map<String, String> _studentNameById = {};
  final Set<int> _expandedLogs = <int>{};
  String _searchQuery = '';
  List<String> _usernames = [];

  // Libellés FR pour les catégories et actions d'audit
  final Map<String, String> _categoryLabels = const {
    'auth': 'Authentification',
    'timetable': 'Emploi du temps',
    'report_card': 'Bulletin',
    'user': 'Utilisateur',
    'payment': 'Paiement',
    'student': 'Élève',
    'staff': 'Personnel',
    'class': 'Classe',
    'subjects': 'Matières',
    'grade': 'Note',
    'inventory': 'Inventaire',
    'expense': 'Dépense',
    'class_course': 'Cours de classe',
    'settings': 'Paramètres',
    'signatures': 'Signatures & Cachets',
    'safe_mode': 'Mode coffre fort',
    'export': 'Export',
    'data': 'Données',
    'error': 'Erreur',
    'system': 'Système',
  };
  final List<String> _categoryOrder = const [
    'auth',
    'timetable',
    'report_card',
    'user',
    'payment',
    'student',
    'staff',
    'class',
    'subjects',
    'grade',
    'inventory',
    'expense',
    'class_course',
    'settings',
    'signatures',
    'safe_mode',
    'export',
    'data',
    'error',
    'system',
  ];

  final Map<String, String> _actionLabels = const {
    // Auth
    'login_success': 'Connexion réussie',
    'login_failed': 'Connexion échouée',
    // Paiements
    'insert_payment': 'Paiement enregistré',
    'update_payment': 'Paiement mis à jour',
    'delete_payment': 'Paiement supprimé',
    'cancel_payment': 'Paiement annulé',
    'cancel_payment_reason': 'Motif d’annulation du paiement modifié',
    // Export inventaire spécifique
    'inventaire_excel': 'Export inventaire Excel',
    // Élèves
    'insert_student': 'Élève ajouté',
    'update_student': 'Élève mis à jour',
    'delete_student': 'Élève supprimé',
    'delete_student_deep': 'Élève supprimé (avec dépendances)',
    // Personnel
    'insert_staff': 'Personnel ajouté',
    'update_staff': 'Personnel mis à jour',
    'delete_staff': 'Personnel supprimé',
    // Inventaire
    'insert_item': 'Article ajouté',
    'update_item': 'Article mis à jour',
    'delete_item': 'Article supprimé',
    // Dépenses
    'insert_expense': 'Dépense ajoutée',
    'update_expense': 'Dépense mise à jour',
    'delete_expense': 'Dépense supprimée',
    // Matières / catégories
    'insert_course': 'Matière ajoutée',
    'update_course': 'Matière mise à jour',
    'delete_course': 'Matière supprimée',
    'insert_category': 'Catégorie ajoutée',
    'update_category': 'Catégorie mise à jour',
    'delete_category': 'Catégorie supprimée',
    // Classes
    'insert_class': 'Classe ajoutée',
    'update_class': 'Classe mise à jour',
    'delete_class': 'Classe supprimée',
    'add_course_to_class': 'Matière ajoutée à la classe',
    // Notes
    'insert_grade': 'Note ajoutée',
    'update_grade': 'Note mise à jour',
    'delete_grade': 'Note supprimée',
    'upsert_subject_app': 'Enregistrement de matière pour l’élève',
    // Export
    'export_pdf': 'Export PDF',
    'export_excel': 'Export Excel',
    'export_csv': 'Export CSV',
    // Système
    'manual_test_log': 'Journal de test manuel',
    // Utilisateurs
    'create_user': 'Utilisateur créé',
    'update_user': 'Utilisateur mis à jour',
    'delete_user': 'Utilisateur supprimé',
    // Paramètres
    'update_settings': 'Paramètres mis à jour',
    // Bulletins
    'export_report_cards': 'Export bulletins (ZIP)',
    'export_report_card_pdf': 'Export bulletin PDF',
    'archive_report_card': 'Archivage du bulletin',
    // Emploi du temps
    'auto_generate_classes': 'Auto-génération (classes)',
    'auto_generate_teachers': 'Auto-génération (enseignants)',
  };

  String _displayAction(String? action) {
    if (action == null || action.isEmpty) return '';
    final mapped = _actionLabels[action];
    if (mapped != null) return mapped;
    // Fallback: transformer "insert_payment" -> "insert payment" puis remplacer quelques mots
    final base = action.replaceAll('_', ' ');
    final tokens = base.split(' ');
    final fr = tokens.map((t) {
      switch (t) {
        case 'insert':
          return 'ajout';
        case 'update':
          return 'mise à jour';
        case 'delete':
          return 'suppression';
        case 'cancel':
          return 'annulation';
        case 'payment':
          return 'paiement';
        case 'student':
          return 'élève';
        case 'staff':
          return 'personnel';
        case 'class':
          return 'classe';
        case 'course':
        case 'subject':
          return 'matière';
        case 'grade':
          return 'note';
        case 'success':
          return 'réussite';
        case 'failed':
          return 'échec';
        default:
          return t;
      }
    }).join(' ');
    // Capitaliser la première lettre
    return fr.isEmpty ? '' : fr[0].toUpperCase() + fr.substring(1);
  }

  String _frDetails(String? details, [String? category]) {
    if (details == null || details.isEmpty) return '';
    var d = details;
    d = d.replaceAll('student=', 'élève=');
    d = d.replaceAll('studentId=', 'élève=');
    d = d.replaceAll('username=', 'utilisateur=');
    d = d.replaceAll('classAcademicYear=', 'année_classe=');
    d = d.replaceAll('class=', 'classe=');
    d = d.replaceAll('name=', 'nom=');
    d = d.replaceAll('amount=', 'montant=');
    d = d.replaceAll('year=', 'année=');
    d = d.replaceAll('term=', 'trimestre=');
    d = d.replaceAll('subject=', 'matière=');
    d = d.replaceAll('course=', 'matière=');
    d = d.replaceAll('value_old=', 'note_avant=');
    d = d.replaceAll('value_new=', 'note_après=');
    d = d.replaceAll('value=', 'note=');
    d = d.replaceAll('qty=', 'qté=');
    d = d.replaceAll('label=', 'libellé=');
    d = d.replaceAll('by=', 'par=');
    d = d.replaceAll('reason=', 'motif=');
    d = d.replaceAll('role=', 'rôle=');
    d = d.replaceAll('file=', 'fichier=');
    d = d.replaceAll('count=', 'nombre=');
    d = d.replaceAll('old=', 'ancien=');
    d = d.replaceAll('new=', 'nouveau=');
    // Remplacer élève=<id> par élève=<Nom> si connu
    d = d.replaceAllMapped(RegExp(r'élève=([^,\s]+)'), (m) {
      final id = m.group(1)!;
      final name = _studentNameById[id];
      return 'élève=' + (name ?? id);
    });
    // Catégorie élève: tenter id=<id> -> élève=<Nom (id)>
    if (category == 'student') {
      d = d.replaceAllMapped(RegExp(r'id=([^,\s]+)'), (m) {
        final id = m.group(1)!;
        final name = _studentNameById[id];
        return name != null ? 'élève=' + name + ' (id=' + id + ')' : 'id=' + id;
      });
    }
    return d;
  }

  String _fmtTs(String? ts) {
    if (ts == null || ts.isEmpty) return '';
    final dt = DateTime.tryParse(ts);
    if (dt == null) return ts;
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _searchUser.addListener(() {
      setState(() {
        _searchQuery = _searchUser.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchUser.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cat = _selectedCategory; // null => toutes catégories
    // Charger avec filtre serveur sur l'utilisateur si sélectionné
    final logs = await _db.getAuditLogs(
      category: cat,
      username: (_selectedUser != null && _selectedUser!.isNotEmpty)
          ? _selectedUser
          : null,
      limit: 1000,
    );
    // Charger les élèves pour mapper ID -> Nom
    List<Student> students = [];
    try {
      students = await _db.getStudents();
    } catch (_) {}
    // Charger les utilisateurs pour dropdown
    List<Map<String, Object?>> users = [];
    try {
      users = await _db.getAllUserRows();
    } catch (_) {}
    final usernames = <String>{
      for (final r in users)
        if ((r['username'] as String?) != null) (r['username'] as String)
    }.toList()
      ..sort();
    final map = <String, String>{ for (final s in students) s.id: s.name };
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _studentNameById = map;
      _usernames = usernames;
      _loading = false;
    });
  }

  Future<void> _exportCsv() async {
    final filtered = _filteredLogs();
    if (filtered.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune donnée à exporter.')),
      );
      return;
    }
    final rows = [
      ['horodatage', 'utilisateur', 'catégorie', 'action', 'succès', 'détails']
    ];
    for (final l in filtered) {
      final String catKey = (l['category'] ?? '').toString();
      final String catDisplay = _categoryLabels[catKey] ?? catKey;
      final String actionDisplay = _displayAction((l['action'] ?? '').toString());
      final String successDisplay = ((l['success'] ?? 1) == 1) ? 'vrai' : 'faux';
      final String detailsDisplay = _frDetails((l['details'] ?? '').toString(), catKey).replaceAll('\n', ' ');
      rows.add([
        _fmtTs((l['timestamp'] ?? '').toString()),
        l['username'] ?? '',
        catDisplay,
        actionDisplay,
        successDisplay,
        detailsDisplay,
      ]);
    }
    final csv = rows
        .map((r) => r
            .map((c) => '"${c.toString().replaceAll('"', '""')}"')
            .join(','))
        .join('\n');
    try {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return; // annulé
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('$dir/audit_$ts.csv');
      await file.writeAsBytes(utf8.encode(csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exporté: ${file.path.split('/').last}')),
      );
      await OpenFile.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur export CSV: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final filtered = _filteredLogs();
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isDesktop),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                  // Raccourcis de période
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text("Aujourd'hui"),
                        selected: _quickRange == 'today',
                        onSelected: (v) {
                          setState(() {
                            _quickRange = v ? 'today' : null;
                            if (v) _selectedDate = null;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('7 derniers jours'),
                        selected: _quickRange == '7d',
                        onSelected: (v) {
                          setState(() {
                            _quickRange = v ? '7d' : null;
                            if (v) _selectedDate = null;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Cette semaine'),
                        selected: _quickRange == 'week',
                        onSelected: (v) {
                          setState(() {
                            _quickRange = v ? 'week' : null;
                            if (v) _selectedDate = null;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Ce mois'),
                        selected: _quickRange == 'month',
                        onSelected: (v) {
                          setState(() {
                            _quickRange = v ? 'month' : null;
                            if (v) _selectedDate = null;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Cette année'),
                        selected: _quickRange == 'year',
                        onSelected: (v) {
                          setState(() {
                            _quickRange = v ? 'year' : null;
                            if (v) _selectedDate = null;
                          });
                        },
                      ),
                    ],
                  ),
                  // Date
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event),
                    label: Text(
                      _selectedDate == null
                          ? 'Date'
                          : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                    ),
                  ),
                  if (_selectedDate != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _selectedDate = null),
                      icon: const Icon(Icons.clear),
                      label: const Text('Effacer la date'),
                    ),
                  // Catégorie
                  DropdownButton<String?>(
                    value: _selectedCategory,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Toutes les catégories'),
                      ),
                      ..._categoryOrder.map(
                        (key) => DropdownMenuItem<String?>(
                          value: key,
                          child: Text(_categoryLabels[key] ?? key),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCategory = v),
                  ),
                  // Utilisateur
                  DropdownButton<String?>(
                    value: _selectedUser,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tous les utilisateurs'),
                      ),
                      ..._usernames.map(
                        (u) => DropdownMenuItem<String?>(value: u, child: Text(u)),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedUser = v);
                      _load();
                    },
                  ),
                  // Statut
                  DropdownButton<String?>(
                    value: _statusFilter,
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('Tous les statuts')),
                      DropdownMenuItem<String?>(value: 'success', child: Text('Succès')),
                      DropdownMenuItem<String?>(value: 'failure', child: Text('Échec')),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                  ),
                  // Ordre
                  DropdownButton<String>(
                    value: _sortOrder,
                    items: const [
                      DropdownMenuItem<String>(value: 'desc', child: Text('Plus récent')),
                      DropdownMenuItem<String>(value: 'asc', child: Text('Plus ancien')),
                    ],
                    onChanged: (v) => setState(() => _sortOrder = v ?? 'desc'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.filter_alt),
                    label: const Text('Appliquer'),
                  ),
                  // Actions
                  ElevatedButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.table_chart, color: Colors.white),
                    label: const Text('Exporter CSV', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('Actualiser', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Builder(
                builder: (ctx) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_logs.isEmpty) {
                    return Center(
                      child: _buildEmptyState(
                        context,
                        icon: Icons.pending_actions,
                        title: 'Aucun journal d\'audit',
                        subtitle:
                            'Les actions de l\'application apparaîtront ici dès qu\'elles seront enregistrées.',
                      ),
                    );
                  }
                  if (filtered.isEmpty) {
                    return Center(
                      child: _buildEmptyState(
                        context,
                        icon: Icons.filter_alt_off,
                        title: 'Aucun résultat',
                        subtitle:
                            'Aucun journal ne correspond à votre recherche ou vos filtres.',
                        action: OutlinedButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réinitialiser les filtres'),
                        ),
                      ),
                    );
                  }
                  return _buildGroupedByDayList(context, filtered);
                },
              ),
            ),
          ],
        ),
      ),
      // FAB retiré sur demande
    );
  }

  Widget _buildHeader(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        padding: const EdgeInsets.all(24),
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.receipt_long,
                        color: Colors.white,
                        size: isDesktop ? 32 : 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Audit des actions',
                          style: TextStyle(
                            fontSize: isDesktop ? 32 : 24,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Consultez, filtrez et exportez les journaux d\'activité.',
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
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
              controller: _searchUser,
              decoration: InputDecoration(
                hintText: 'Recherche (utilisateur, action, détails)…',
                hintStyle: TextStyle(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
                prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
                filled: true,
                fillColor: theme.cardColor,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
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
              onSubmitted: (_) => _load(),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedUser = null;
      _statusFilter = null;
      _sortOrder = 'desc';
      _searchUser.clear();
      _searchQuery = '';
    });
    _load();
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 40, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 420,
            child: Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredLogs() {
    Iterable<Map<String, dynamic>> iter = _logs;
    if (_statusFilter != null) {
      final want = _statusFilter == 'success';
      iter = iter.where((l) => ((l['success'] ?? 1) == 1) == want);
    }
    if (_quickRange != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      DateTime start;
      DateTime end;
      if (_quickRange == 'today') {
        start = today;
        end = today.add(const Duration(days: 1));
      } else if (_quickRange == '7d') {
        end = today.add(const Duration(days: 1));
        start = today.subtract(const Duration(days: 6));
      } else if (_quickRange == 'week') {
        // Semaine commençant le lundi
        final weekday = today.weekday; // 1..7
        start = today.subtract(Duration(days: weekday - 1));
        end = start.add(const Duration(days: 7));
      } else if (_quickRange == 'month') {
        start = DateTime(today.year, today.month, 1);
        end = DateTime(today.year, today.month + 1, 1);
      } else {
        // year
        start = DateTime(today.year, 1, 1);
        end = DateTime(today.year + 1, 1, 1);
      }
      iter = iter.where((l) {
        final ts = (l['timestamp'] ?? '').toString();
        final dt = DateTime.tryParse(ts);
        if (dt == null) return false;
        return dt.isAfter(start.subtract(const Duration(milliseconds: 1))) && dt.isBefore(end);
      });
    }
    if (_selectedDate != null) {
      final target = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      iter = iter.where((l) {
        final ts = (l['timestamp'] ?? '').toString();
        final dt = DateTime.tryParse(ts);
        if (dt == null) return false;
        final d = DateTime(dt.year, dt.month, dt.day);
        return d == target;
      });
    }
    if (_searchQuery.isNotEmpty) {
      iter = iter.where((l) {
        final catKey = (l['category'] ?? '').toString();
        final action = (l['action'] ?? '').toString();
        final details = (l['details'] ?? '').toString();
        final user = (l['username'] ?? '').toString();
        final actionFr = _displayAction(action).toLowerCase();
        final detailsFr = _frDetails(details, catKey).toLowerCase();
        final catFr = (_categoryLabels[catKey] ?? catKey).toLowerCase();
        final u = user.toLowerCase();
        return actionFr.contains(_searchQuery) ||
            detailsFr.contains(_searchQuery) ||
            catFr.contains(_searchQuery) ||
            u.contains(_searchQuery);
      });
    }
    final list = iter.toList();
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      final sa = (a['timestamp'] ?? '').toString();
      final sb = (b['timestamp'] ?? '').toString();
      final da = DateTime.tryParse(sa);
      final db = DateTime.tryParse(sb);
      int c;
      if (da != null && db != null) {
        c = da.compareTo(db);
      } else {
        c = sa.compareTo(sb);
      }
      return _sortOrder == 'desc' ? -c : c;
    }
    list.sort(cmp);
    return list;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 5, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: first,
      lastDate: last,
      helpText: 'Sélectionnez une date',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Widget _buildGroupedByDayList(BuildContext context, List<Map<String, dynamic>> logs) {
    // Grouper par jour (date sans heure)
    final Map<DateTime, List<Map<String, dynamic>>> groups = {};
    for (final l in logs) {
      final ts = (l['timestamp'] ?? '').toString();
      final dt = DateTime.tryParse(ts);
      if (dt == null) continue;
      final key = DateTime(dt.year, dt.month, dt.day);
      groups.putIfAbsent(key, () => []).add(l);
    }
    final dates = groups.keys.toList()
      ..sort((a, b) => _sortOrder == 'desc' ? b.compareTo(a) : a.compareTo(b));

    String labelFor(DateTime d) {
      final today = DateTime.now();
      final t = DateTime(today.year, today.month, today.day);
      final y = t.subtract(const Duration(days: 1));
      final dd = DateTime(d.year, d.month, d.day);
      if (dd == t) return 'Aujourd\'hui';
      if (dd == y) return 'Hier';
      return DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(d);
    }

    final children = <Widget>[];
    for (final d in dates) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labelFor(d),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
      final items = groups[d]!;
      // Optionnel: re-trier dans le groupe
      items.sort((a, b) {
        final da = DateTime.tryParse((a['timestamp'] ?? '').toString());
        final db = DateTime.tryParse((b['timestamp'] ?? '').toString());
        int c = 0;
        if (da != null && db != null) c = da.compareTo(db);
        return _sortOrder == 'desc' ? -c : c;
      });
      for (final l in items) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _buildActionCard(context, l),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: children,
    );
  }

  Color _categoryColor(String key, ThemeData theme) {
    switch (key) {
      case 'auth':
        return const Color(0xFF6366F1);
      case 'timetable':
        return const Color(0xFFA78BFA);
      case 'report_card':
        return const Color(0xFF3B82F6);
      case 'user':
        return const Color(0xFF0EA5E9);
      case 'payment':
        return const Color(0xFFF59E0B);
      case 'student':
        return const Color(0xFF3B82F6);
      case 'staff':
        return const Color(0xFF10B981);
      case 'class':
        return const Color(0xFFA78BFA);
      case 'subjects':
        return const Color(0xFF8B5CF6);
      case 'grade':
        return const Color(0xFFEC4899);
      case 'inventory':
        return const Color(0xFF22C55E);
      case 'expense':
        return const Color(0xFFEF4444);
      case 'class_course':
        return const Color(0xFF38BDF8);
      case 'settings':
        return const Color(0xFF06B6D4);
      case 'export':
        return const Color(0xFF0EA5E9);
      case 'data':
        return const Color(0xFF64748B);
      case 'error':
        return const Color(0xFFDC2626);
      case 'system':
        return const Color(0xFF0EA5E9);
      default:
        return theme.colorScheme.primary;
    }
  }

  IconData _categoryIcon(String key) {
    switch (key) {
      case 'auth':
        return Icons.lock_outline;
      case 'timetable':
        return Icons.calendar_today;
      case 'report_card':
        return Icons.description_outlined;
      case 'user':
        return Icons.person_outline;
      case 'payment':
        return Icons.payment;
      case 'student':
        return Icons.school;
      case 'staff':
        return Icons.group;
      case 'class':
        return Icons.class_outlined;
      case 'subjects':
        return Icons.book_outlined;
      case 'grade':
        return Icons.grade_outlined;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'expense':
        return Icons.receipt_long_outlined;
      case 'class_course':
        return Icons.grid_view_rounded;
      case 'settings':
        return Icons.settings_outlined;
      case 'export':
        return Icons.file_upload_outlined;
      case 'data':
        return Icons.storage_outlined;
      case 'error':
        return Icons.error_outline;
      case 'system':
        return Icons.settings_outlined;
      default:
        return Icons.event_note_outlined;
    }
  }

  Widget _chip(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, Map<String, dynamic> l) {
    final theme = Theme.of(context);
    final ok = (l['success'] ?? 1) == 1;
    final String catKey = (l['category'] ?? '').toString();
    final String catDisplay = _categoryLabels[catKey] ?? catKey;
    final Color catColor = _categoryColor(catKey, theme);
    final String user = (l['username'] ?? '').toString();
    final String ts = _fmtTs((l['timestamp'] ?? '').toString());
    final String rawDetails = (l['details'] ?? '').toString();
    final String details = _frDetails(rawDetails, catKey);
    final String actionTitle = _displayAction((l['action'] ?? '').toString());
    final int? id = (l['id'] is int)
        ? (l['id'] as int)
        : int.tryParse((l['id'] ?? '').toString());
    final bool isExpanded = id != null && _expandedLogs.contains(id);

    final Color statusColor = ok ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final IconData statusIcon = ok ? Icons.check_circle : Icons.error;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_categoryIcon(catKey), color: catColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  actionTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _chip(
                context,
                icon: statusIcon,
                label: ok ? 'Réussi' : 'Échec',
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Affichage spécifique: mise à jour de note (avant -> après)
          Builder(builder: (context) {
            final actionKey = (l['action'] ?? '').toString();
            if (actionKey != 'update_grade') return const SizedBox.shrink();
            double? before;
            double? after;
            final ro = RegExp(r'value_old=([0-9]+(?:\.[0-9]+)?)').firstMatch(rawDetails);
            final rn = RegExp(r'value_new=([0-9]+(?:\.[0-9]+)?)').firstMatch(rawDetails);
            if (ro != null) before = double.tryParse(ro.group(1)!);
            if (rn != null) after = double.tryParse(rn.group(1)!);
            if (before == null && after == null) return const SizedBox.shrink();
            final bool improved = (before != null && after != null) ? after! > before! : false;
            final Color deltaColor = improved ? const Color(0xFF10B981) : const Color(0xFFEF4444);
            final IconData deltaIcon = improved ? Icons.trending_up : Icons.trending_down;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(deltaIcon, size: 18, color: deltaColor),
                  const SizedBox(width: 8),
                  Text(
                    'Note: ' +
                        (before != null ? before!.toStringAsFixed(2) : '-') +
                        ' → ' +
                        (after != null ? after!.toStringAsFixed(2) : '-'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: deltaColor,
                        ),
                  ),
                ],
              ),
            );
          }),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                context,
                icon: Icons.category_outlined,
                label: catDisplay,
                color: catColor,
              ),
              if (user.isNotEmpty)
                _chip(
                  context,
                  icon: Icons.person_outline,
                  label: user,
                  color: theme.colorScheme.primary,
                ),
              if (ts.isNotEmpty)
                _chip(
                  context,
                  icon: Icons.access_time,
                  label: ts,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8) ?? Colors.grey,
                ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final bool lengthy = details.length > 160 || details.contains('\n');
              final String shown = (!lengthy || isExpanded)
                  ? details
                  : (details.substring(0, 160) + '…');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shown,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.9),
                    ),
                  ),
                  if (lengthy)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: id == null
                            ? null
                            : () => setState(() {
                                  if (_expandedLogs.contains(id)) {
                                    _expandedLogs.remove(id);
                                  } else {
                                    _expandedLogs.add(id);
                                  }
                                }),
                        child: Text(
                          isExpanded ? 'Réduire' : 'Afficher plus',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: details));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Détails copiés')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_all, size: 16),
                        label: const Text('Copier les détails'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final buffer = StringBuffer()
                            ..writeln('Action: ' + actionTitle)
                            ..writeln('Catégorie: ' + catDisplay);
                          if (user.isNotEmpty) buffer.writeln('Utilisateur: ' + user);
                          if (ts.isNotEmpty) buffer.writeln('Date: ' + ts);
                          if (details.isNotEmpty) buffer.writeln('Détails: ' + details);
                          await Clipboard.setData(ClipboardData(text: buffer.toString()));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Informations copiées')),
                            );
                          }
                        },
                        icon: const Icon(Icons.content_copy, size: 16),
                        label: const Text('Copier tout'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }
}
