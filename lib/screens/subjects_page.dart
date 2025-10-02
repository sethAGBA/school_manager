import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/category.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';
import 'package:school_manager/screens/categories_modal_content.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';

class SubjectsPage extends StatefulWidget {
  const SubjectsPage({Key? key}) : super(key: key);

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage> with TickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  List<Course> _courses = [];
  List<Category> _categories = [];
  bool _loading = true;
  late AnimationController _anim;
  late Animation<double> _fade;
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedCategoryId;
  // Gestion des sections repliées/dépliées
  final Set<String> _collapsedSections = <String>{};
  static const String _uncatKey = '_UNCAT_';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _load();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _anim.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Initialiser les catégories par défaut si nécessaire
    await _db.initializeDefaultCategories();
    final courses = await _db.getCourses();
    final categories = await _db.getCategories();
    setState(() {
      _courses = courses;
      _categories = categories;
      _loading = false;
    });
    _anim.forward();
  }

  Future<void> _showCategoriesModal() async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: CategoriesModalContent(
            onCategoriesChanged: () => _load(),
          ),
        ),
      ),
    );
  }

  Future<void> _exportSubjectsToPdf() async {
    try {
      // Demander le répertoire de sauvegarde
      String? directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export annulé'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Obtenir les informations de l'école
      final schoolInfo = await _db.getSchoolInfo();
      if (schoolInfo == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur: Informations de l\'école non trouvées'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      final currentAcademicYear = '2024-2025'; // Vous pouvez récupérer cela dynamiquement

      // Générer le PDF
      final bytes = await PdfService.generateSubjectsPdf(
        schoolInfo: schoolInfo,
        academicYear: currentAcademicYear,
        courses: _courses,
        categories: _categories,
        title: 'Liste des Matières',
      );

      // Sauvegarder le fichier
      final fileName = 'matieres_${currentAcademicYear.replaceAll('/', '_')}.pdf';
      final file = File('$directory/$fileName');
      await file.writeAsBytes(bytes);
      
      // Ouvrir le fichier
      OpenFile.open(file.path);
      
      // Notification de succès
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export PDF réussi ! Fichier sauvegardé : $fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Notification d'erreur
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'export PDF : $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _exportSubjectsToExcel() async {
    try {
      // Demander le répertoire de sauvegarde
      String? directory = await FilePicker.platform.getDirectoryPath();
      if (directory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export annulé'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final currentAcademicYear = '2024-2025';
      
      // Créer le fichier Excel
      final excel = Excel.createExcel();
      final sheet = excel['Matières'];
      
      // Supprimer la feuille par défaut
      excel.delete('Sheet1');
      
      // En-tête
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('N°');
      sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Matière');
      sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Catégorie');
      sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Description');
      
      // Style de l'en-tête
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.blue50,
        fontColorHex: ExcelColor.blue900,
      );
      
      sheet.cell(CellIndex.indexByString('A1')).cellStyle = headerStyle;
      sheet.cell(CellIndex.indexByString('B1')).cellStyle = headerStyle;
      sheet.cell(CellIndex.indexByString('C1')).cellStyle = headerStyle;
      sheet.cell(CellIndex.indexByString('D1')).cellStyle = headerStyle;
      
      // Données des matières
      int rowIndex = 2;
      for (final course in _courses) {
        final category = _categories.firstWhere(
          (cat) => cat.id == course.categoryId,
          orElse: () => Category.empty(),
        );
        
        sheet.cell(CellIndex.indexByString('A$rowIndex')).value = TextCellValue('${rowIndex - 1}');
        sheet.cell(CellIndex.indexByString('B$rowIndex')).value = TextCellValue(course.name);
        sheet.cell(CellIndex.indexByString('C$rowIndex')).value = TextCellValue(
          course.categoryId != null && category.id.isNotEmpty ? category.name : 'Non classée'
        );
        sheet.cell(CellIndex.indexByString('D$rowIndex')).value = TextCellValue(course.description ?? '');
        
        rowIndex++;
      }
      
      // Ajuster la largeur des colonnes
      sheet.setColumnWidth(0, 8); // N°
      sheet.setColumnWidth(1, 25); // Matière
      sheet.setColumnWidth(2, 20); // Catégorie
      sheet.setColumnWidth(3, 35); // Description
      
      // Sauvegarder le fichier
      final fileName = 'matieres_${currentAcademicYear.replaceAll('/', '_')}.xlsx';
      final file = File('$directory/$fileName');
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        OpenFile.open(file.path);
        
        // Notification de succès
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Export Excel réussi ! Fichier sauvegardé : $fileName'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('Erreur lors de la génération du fichier Excel');
      }
    } catch (e) {
      // Notification d'erreur
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'export Excel : $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _showAddEditDialog({Course? course}) async {
    final isEdit = course != null;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: course?.name ?? '');
    final descController = TextEditingController(text: course?.description ?? '');
    String? selectedCategoryId = course?.categoryId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => CustomDialog(
          title: isEdit ? 'Modifier la matière' : 'Ajouter une matière',
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomFormField(
                  controller: nameController,
                  labelText: 'Nom de la matière',
                  hintText: 'Ex: Mathématiques',
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                CustomFormField(
                  controller: descController,
                  labelText: 'Description (optionnelle)',
                  hintText: 'Ex: Tronc commun, avancé...',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Catégorie (optionnelle)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Aucune catégorie'),
                    ),
                    ..._categories.map((category) => DropdownMenuItem<String>(
                      value: category.id,
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Color(int.parse(category.color.replaceFirst('#', '0xff'))),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(category.name),
                        ],
                      ),
                    )),
                  ],
                  onChanged: (value) => setState(() => selectedCategoryId = value),
                ),
              ],
            ),
          ),
        onSubmit: null,
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          if (isEdit)
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Supprimer la matière ?'),
                    content: const Text('Cette action est irréversible.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
                      ElevatedButton(
                        onPressed: () => Navigator.of(c).pop(true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _db.deleteCourse(course.id);
                  await _load();
                  if (mounted) Navigator.of(context).pop();
                }
              },
              child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final name = nameController.text.trim();
              final desc = descController.text.trim();
              if (isEdit) {
                final updated = Course(
                  id: course.id, 
                  name: name, 
                  description: desc.isNotEmpty ? desc : null,
                  categoryId: selectedCategoryId,
                );
                await _db.updateCourse(course.id, updated);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Matière "${name}" modifiée avec succès'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                final exists = _courses.any((c) => c.name.toLowerCase() == name.toLowerCase());
                if (exists) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette matière existe déjà.')));
                  return;
                }
                final created = Course(
                  id: const Uuid().v4(), 
                  name: name, 
                  description: desc.isNotEmpty ? desc : null,
                  categoryId: selectedCategoryId,
                );
                await _db.insertCourse(created);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Matière "${name}" ajoutée avec succès'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
              await _load();
              if (mounted) Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
            child: Text(isEdit ? 'Modifier' : 'Ajouter'),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final filtered = _courses.where((c) {
      final matchesQuery = _query.isEmpty || c.name.toLowerCase().contains(_query);
      final matchesCategory = _selectedCategoryId == null || c.categoryId == _selectedCategoryId;
      return matchesQuery && matchesCategory;
    }).toList();
    // Group by catégorie (incluant "Non classée")
    final Map<String?, List<Course>> grouped = {};
    for (final c in filtered) {
      grouped.putIfAbsent(c.categoryId, () => []).add(c);
    }
    // Ordre des sections: catégories dans l'ordre, puis Non classée si présente
    final List<String?> orderedGroupKeys = [];
    if (_selectedCategoryId != null) {
      if (grouped.containsKey(_selectedCategoryId)) orderedGroupKeys.add(_selectedCategoryId);
    } else {
      for (final cat in _categories) {
        if (grouped.containsKey(cat.id)) orderedGroupKeys.add(cat.id);
      }
    }
    if (grouped.containsKey(null)) orderedGroupKeys.add(null);
    return FadeTransition(
      opacity: _fade,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme, isDesktop),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showAddEditDialog(),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Ajouter une matière', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Filtrer par catégorie',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Toutes les catégories'),
                      ),
                      ..._categories.map((category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(int.parse(category.color.replaceFirst('#', '0xff'))),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(category.name),
                          ],
                        ),
                      )),
                    ],
                    onChanged: (value) => setState(() => _selectedCategoryId = value),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    // Déplier toutes les sections visibles
                    setState(() => _collapsedSections.clear());
                  },
                  icon: const Icon(Icons.unfold_more),
                  label: const Text('Tout déplier'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    // Replier toutes les sections visibles (selon le filtre/recherche)
                    final keys = _courses
                        .where((c) {
                          final matchesQuery = _query.isEmpty || c.name.toLowerCase().contains(_query);
                          final matchesCategory = _selectedCategoryId == null || c.categoryId == _selectedCategoryId;
                          return matchesQuery && matchesCategory;
                        })
                        .map((c) => c.categoryId ?? _uncatKey)
                        .toSet();
                    setState(() {
                      _collapsedSections
                        ..clear()
                        ..addAll(keys);
                    });
                  },
                  icon: const Icon(Icons.unfold_less),
                  label: const Text('Tout replier'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Container(
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _query.isNotEmpty || _selectedCategoryId != null
                                      ? Icons.search_off
                                      : Icons.book_outlined,
                                  size: 64,
                                  color: theme.iconTheme.color?.withOpacity(0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _query.isNotEmpty || _selectedCategoryId != null
                                      ? 'Aucune matière trouvée'
                                      : 'Aucune matière enregistrée',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: theme.textTheme.bodyLarge?.color?.withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _query.isNotEmpty || _selectedCategoryId != null
                                      ? 'Essayez de modifier vos critères de recherche'
                                      : 'Commencez par ajouter votre première matière',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: () => _showAddEditDialog(),
                                  icon: const Icon(Icons.add, color: Colors.white),
                                  label: const Text('Ajouter une matière', style: TextStyle(color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                          ),
                          child: ListView.builder(
                            itemCount: orderedGroupKeys.length,
                            itemBuilder: (ctx, sidx) {
                              final key = orderedGroupKeys[sidx];
                              final List<Course> items = grouped[key] ?? [];
                              Category? cat;
                              bool hasCat = false;
                              if (key != null) {
                                cat = _categories.firstWhere((c) => c.id == key, orElse: () => Category.empty());
                                hasCat = cat.id.isNotEmpty;
                              }
                              final String sectionName = hasCat ? cat!.name : 'Non classée';
                              final Color sectionColor = hasCat
                                  ? Color(int.parse(cat!.color.replaceFirst('#', '0xff')))
                                  : Colors.blueGrey;
                              final String sectionKey = key ?? _uncatKey;
                              final bool isCollapsed = _collapsedSections.contains(sectionKey);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (isCollapsed) {
                                            _collapsedSections.remove(sectionKey);
                                          } else {
                                            _collapsedSections.add(sectionKey);
                                          }
                                        });
                                      },
                                      child: Row(
                                        children: [
                                          Container(width: 8, height: 24, decoration: BoxDecoration(color: sectionColor, borderRadius: BorderRadius.circular(4))),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '$sectionName (${items.length})',
                                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          Icon(isCollapsed ? Icons.expand_more : Icons.expand_less, color: theme.iconTheme.color),
                                        ],
                                      ),
                                    ),
                                    if (!isCollapsed) ...[
                                      const SizedBox(height: 8),
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: items.length,
                                        separatorBuilder: (_, __) => Divider(color: theme.dividerColor.withOpacity(0.3), height: 1),
                                        itemBuilder: (ctx2, i) {
                                          final c = items[i];
                                          final hasCategory = hasCat;
                                          return ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: hasCategory ? sectionColor : const Color(0xFF6366F1),
                                              child: const Icon(Icons.book, color: Colors.white),
                                            ),
                                            title: Text(c.name, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.w600)),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (c.description != null && c.description!.isNotEmpty)
                                                  Text(c.description!, style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                                                if (hasCategory)
                                                  Row(
                                                    children: [
                                                      Container(
                                                        width: 12,
                                                        height: 12,
                                                        decoration: BoxDecoration(
                                                          color: sectionColor,
                                                          borderRadius: BorderRadius.circular(2),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        sectionName,
                                                        style: TextStyle(
                                                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Modifier',
                                                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF6366F1)),
                                                  onPressed: () => _showAddEditDialog(course: c),
                                                ),
                                                IconButton(
                                                  tooltip: 'Supprimer',
                                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                                  onPressed: () async {
                                                    final confirm = await showDialog<bool>(
                                                      context: context,
                                                      builder: (d) => AlertDialog(
                                                        title: const Text('Supprimer la matière ?'),
                                                        content: const Text('Cette action est irréversible.'),
                                                        actions: [
                                                          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
                                                          ElevatedButton(
                                                            onPressed: () => Navigator.of(d).pop(true),
                                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                                            child: const Text('Supprimer'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirm == true) {
                                                      await _db.deleteCourse(c.id);
                                                      await _load();
                                                    }
                                                  },
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDesktop) {
    return Container(
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
                      Icons.book,
                      color: Colors.white,
                      size: isDesktop ? 32 : 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des Matières',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Créez et gérez les matières avec leurs catégories personnalisables.',
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
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _exportSubjectsToExcel(),
                    icon: const Icon(Icons.table_chart, color: Colors.white),
                    label: const Text('Exporter Excel', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981), 
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _exportSubjectsToPdf(),
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                    label: const Text('Exporter PDF', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444), 
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showCategoriesModal(),
                    icon: const Icon(Icons.category, color: Colors.white),
                    label: const Text('Catégories', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6), 
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Rechercher une matière...',
              hintStyle: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6)),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
              filled: true,
              fillColor: theme.cardColor,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
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
          ),
        ],
      ),
    );
  }
}
