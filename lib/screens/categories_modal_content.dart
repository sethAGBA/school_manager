import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:uuid/uuid.dart';
import 'package:school_manager/models/category.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';

class CategoriesModalContent extends StatefulWidget {
  final VoidCallback onCategoriesChanged;

  const CategoriesModalContent({Key? key, required this.onCategoriesChanged})
    : super(key: key);

  @override
  State<CategoriesModalContent> createState() => _CategoriesModalContentState();
}

class _CategoriesModalContentState extends State<CategoriesModalContent> {
  final DatabaseService _db = DatabaseService();
  List<Category> _categories = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(
      () =>
          setState(() => _query = _searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getCategories();
    setState(() {
      _categories = list;
      _loading = false;
    });
  }

  Future<void> _showAddEditDialog({Category? category}) async {
    final isEdit = category != null;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: category?.name ?? '');
    final descController = TextEditingController(
      text: category?.description ?? '',
    );
    final orderController = TextEditingController(
      text: category?.order.toString() ?? '0',
    );
    Color selectedColor = category?.color != null
        ? Color(int.parse(category!.color.replaceFirst('#', '0xff')))
        : const Color(0xFF6366F1);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => CustomDialog(
          title: isEdit ? 'Modifier la catégorie' : 'Ajouter une catégorie',
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomFormField(
                  controller: nameController,
                  labelText: 'Nom de la catégorie',
                  hintText: 'Ex: Scientifiques',
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                CustomFormField(
                  controller: descController,
                  labelText: 'Description (optionnelle)',
                  hintText: 'Ex: Matières scientifiques et techniques',
                ),
                TextFormField(
                  controller: orderController,
                  decoration: const InputDecoration(
                    labelText: 'Ordre d\'affichage',
                    hintText: '0',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Champ requis';
                    if (int.tryParse(v) == null) return 'Nombre invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Couleur : '),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final color = await showDialog<Color>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Choisir une couleur'),
                            content: SingleChildScrollView(
                              child: ColorPicker(
                                pickerColor: selectedColor,
                                onColorChanged: (color) =>
                                    selectedColor = color,
                                pickerAreaHeightPercent: 0.8,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Annuler'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(selectedColor),
                                child: const Text('Valider'),
                              ),
                            ],
                          ),
                        );
                        if (color != null) {
                          setState(() => selectedColor = color);
                        }
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          onSubmit: () async {
            if (!formKey.currentState!.validate()) return;
            final name = nameController.text.trim();
            final desc = descController.text.trim();
            final order = int.parse(orderController.text.trim());
            final colorHex =
                '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}';

            if (isEdit) {
              final updated = Category(
                id: category.id,
                name: name,
                description: desc.isNotEmpty ? desc : null,
                color: colorHex,
                order: order,
              );
              await _db.updateCategory(category.id, updated);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Catégorie "${name}" modifiée avec succès'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } else {
              final exists = _categories.any(
                (c) => c.name.toLowerCase() == name.toLowerCase(),
              );
              if (exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cette catégorie existe déjà.')),
                );
                return;
              }
              final created = Category(
                id: const Uuid().v4(),
                name: name,
                description: desc.isNotEmpty ? desc : null,
                color: colorHex,
                order: order,
              );
              await _db.insertCategory(created);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Catégorie "${name}" ajoutée avec succès'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
            await _load();
            widget.onCategoriesChanged();
            if (mounted) Navigator.of(context).pop();
          },
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            if (isEdit)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Supprimer la catégorie ?'),
                      content: const Text(
                        'Cette action est irréversible. Les matières de cette catégorie seront déclassées.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(false),
                          child: const Text('Annuler'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(c).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Supprimer'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _db.deleteCategory(category.id);
                    await _load();
                    widget.onCategoriesChanged();
                    if (mounted) Navigator.of(context).pop();
                  }
                },
                child: const Text(
                  'Supprimer',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final name = nameController.text.trim();
                final desc = descController.text.trim();
                final order = int.parse(orderController.text.trim());
                final colorHex =
                    '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}';

                if (isEdit) {
                  final updated = Category(
                    id: category.id,
                    name: name,
                    description: desc.isNotEmpty ? desc : null,
                    color: colorHex,
                    order: order,
                  );
                  await _db.updateCategory(category.id, updated);
                } else {
                  final exists = _categories.any(
                    (c) => c.name.toLowerCase() == name.toLowerCase(),
                  );
                  if (exists) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cette catégorie existe déjà.'),
                      ),
                    );
                    return;
                  }
                  final created = Category(
                    id: const Uuid().v4(),
                    name: name,
                    description: desc.isNotEmpty ? desc : null,
                    color: colorHex,
                    order: order,
                  );
                  await _db.insertCategory(created);
                }
                await _load();
                widget.onCategoriesChanged();
                if (mounted) Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              child: Text(isEdit ? 'Modifier' : 'Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _categories
        .where((c) => _query.isEmpty || c.name.toLowerCase().contains(_query))
        .toList();

    return Column(
      children: [
        // En-tête avec titre et bouton fermer
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.category, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catégories de matières',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    Text(
                      'Gérez les catégories pour organiser vos matières',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              tooltip: 'Fermer',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Barre d'actions
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Ajouter une catégorie',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher une catégorie...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Liste des catégories
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.2),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _query.isNotEmpty
                              ? Icons.search_off
                              : Icons.category_outlined,
                          size: 64,
                          color: theme.iconTheme.color?.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _query.isNotEmpty
                              ? 'Aucune catégorie trouvée'
                              : 'Aucune catégorie enregistrée',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: theme.textTheme.bodyLarge?.color
                                ?.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _query.isNotEmpty
                              ? 'Essayez de modifier vos critères de recherche'
                              : 'Commencez par ajouter votre première catégorie',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _showAddEditDialog(),
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text(
                            'Ajouter une catégorie',
                            style: TextStyle(color: Colors.white),
                          ),
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
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.2),
                    ),
                  ),
                  child: ListView.separated(
                    itemBuilder: (ctx, i) {
                      final c = filtered[i];
                      final color = Color(
                        int.parse(c.color.replaceFirst('#', '0xff')),
                      );
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color,
                          child: const Icon(
                            Icons.category,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          c.name,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (c.description != null &&
                                c.description!.isNotEmpty)
                              Text(
                                c.description!,
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            Text(
                              'Ordre: ${c.order}',
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color
                                    ?.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Modifier',
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Color(0xFF6366F1),
                              ),
                              onPressed: () => _showAddEditDialog(category: c),
                            ),
                            IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (d) => AlertDialog(
                                    title: const Text(
                                      'Supprimer la catégorie ?',
                                    ),
                                    content: const Text(
                                      'Cette action est irréversible. Les matières de cette catégorie seront déclassées.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(d).pop(false),
                                        child: const Text('Annuler'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.of(d).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Supprimer'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await _db.deleteCategory(c.id);
                                  await _load();
                                  widget.onCategoriesChanged();
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => Divider(
                      color: theme.dividerColor.withOpacity(0.3),
                      height: 1,
                    ),
                    itemCount: filtered.length,
                  ),
                ),
        ),
      ],
    );
  }
}
