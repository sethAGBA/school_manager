import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/models/student.dart';
import 'package:intl/intl.dart';
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
  String _sortOrder = 'desc'; // 'desc' (Plus récent) ou 'asc' (Plus ancien)
  String? _statusFilter; // null: tous, 'success', 'failure'
  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];
  Map<String, String> _studentNameById = {};
  final Set<int> _expandedLogs = <int>{};
  String _searchQuery = '';

  // Libellés FR pour les catégories et actions d'audit
  final Map<String, String> _categoryLabels = const {
    'auth': 'Authentification',
    'payment': 'Paiement',
    'student': 'Élève',
    'staff': 'Personnel',
    'class': 'Classe',
    'subjects': 'Matières',
    'grade': 'Note',
    'inventory': 'Inventaire',
    'expense': 'Dépense',
    'class_course': 'Cours de classe',
    'export': 'Export',
    'data': 'Données',
    'error': 'Erreur',
    'system': 'Système',
  };
  final List<String> _categoryOrder = const [
    'auth',
    'payment',
    'student',
    'staff',
    'class',
    'subjects',
    'grade',
    'inventory',
    'expense',
    'class_course',
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
    d = d.replaceAll('qty=', 'qté=');
    d = d.replaceAll('label=', 'libellé=');
    d = d.replaceAll('by=', 'par=');
    d = d.replaceAll('reason=', 'motif=');
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
    // Charger sans filtre par utilisateur, la recherche est appliquée côté client
    final logs = await _db.getAuditLogs(category: cat, limit: 1000);
    // Charger les élèves pour mapper ID -> Nom
    List<Student> students = [];
    try {
      students = await _db.getStudents();
    } catch (_) {}
    final map = <String, String>{ for (final s in students) s.id: s.name };
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _studentNameById = map;
      _loading = false;
    });
  }

  Future<void> _exportCsv() async {
    final filtered = _filteredLogs();
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
    final csv = rows.map((r) => r.map((c) => '"${c.toString().replaceAll('"', '""')}"').join(',')).join('\n');
    debugPrint('[Audit] CSV bytes: ${utf8.encode(csv).length}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export CSV simulé (sauvegarde à implémenter).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
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
                  // Statut
                  DropdownButton<String?>(
                    value: _statusFilter,
                    items: const [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tous les statuts'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'success',
                        child: Text('Réussi'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'failure',
                        child: Text('Échec'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                  ),
                  // Tri
                  DropdownButton<String>(
                    value: _sortOrder,
                    items: const [
                      DropdownMenuItem<String>(
                        value: 'desc',
                        child: Text('Plus récent'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'asc',
                        child: Text('Plus ancien'),
                      ),
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _logs.isEmpty
                      ? const Center(child: Text('Aucun audit trouvé'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _filteredLogs().length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final l = _filteredLogs()[i];
                            return _buildActionCard(context, l);
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
                        Icons.security,
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

  List<Map<String, dynamic>> _filteredLogs() {
    Iterable<Map<String, dynamic>> iter = _logs;
    if (_statusFilter != null) {
      final want = _statusFilter == 'success';
      iter = iter.where((l) => ((l['success'] ?? 1) == 1) == want);
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

  Color _categoryColor(String key, ThemeData theme) {
    switch (key) {
      case 'auth':
        return const Color(0xFF6366F1);
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
    final String details = _frDetails((l['details'] ?? '').toString(), catKey);
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
