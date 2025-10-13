import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:school_manager/constants/colors.dart';
import 'package:school_manager/models/signature.dart';
import 'package:school_manager/services/database_service.dart';

class SignaturesPage extends StatefulWidget {
  const SignaturesPage({Key? key}) : super(key: key);

  @override
  _SignaturesPageState createState() => _SignaturesPageState();
}

class _SignaturesPageState extends State<SignaturesPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _dbService = DatabaseService();
  List<Signature> _signatures = [];
  List<Signature> _cachets = [];
  bool _isLoading = true;
  bool _isDarkMode = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSignatures();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSignatures() async {
    setState(() => _isLoading = true);
    try {
      final allSignatures = await _dbService.getAllSignatures();
      setState(() {
        _signatures = allSignatures.where((s) => s.type == 'signature').toList();
        _cachets = allSignatures.where((s) => s.type == 'cachet').toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Erreur lors du chargement: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _addSignature(String type) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SignatureDialog(type: type),
    );

    if (result != null) {
      try {
        final signature = Signature(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: result['name']!,
          type: type,
          imagePath: result['imagePath'],
          description: result['description'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await _dbService.insertSignature(signature);
        _showSuccessSnackBar('${type == 'signature' ? 'Signature' : 'Cachet'} ajouté avec succès');
        _loadSignatures();
      } catch (e) {
        _showErrorSnackBar('Erreur lors de l\'ajout: $e');
      }
    }
  }

  Future<void> _editSignature(Signature signature) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SignatureDialog(
        type: signature.type,
        initialSignature: signature,
      ),
    );

    if (result != null) {
      try {
        final updatedSignature = signature.copyWith(
          name: result['name'],
          imagePath: result['imagePath'],
          description: result['description'],
          updatedAt: DateTime.now(),
        );

        await _dbService.updateSignature(updatedSignature);
        _showSuccessSnackBar('${signature.type == 'signature' ? 'Signature' : 'Cachet'} modifié avec succès');
        _loadSignatures();
      } catch (e) {
        _showErrorSnackBar('Erreur lors de la modification: $e');
      }
    }
  }

  Future<void> _deleteSignature(Signature signature) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmer la suppression'),
        content: Text('Voulez-vous vraiment supprimer ce ${signature.type == 'signature' ? 'signature' : 'cachet'} ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dbService.deleteSignature(signature.id);
        _showSuccessSnackBar('${signature.type == 'signature' ? 'Signature' : 'Cachet'} supprimé avec succès');
        _loadSignatures();
      } catch (e) {
        _showErrorSnackBar('Erreur lors de la suppression: $e');
      }
    }
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
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: _isDarkMode ? Colors.grey[900] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: _isDarkMode ? Colors.grey[800] : Colors.grey[50],
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: AppColors.primaryBlue,
                        unselectedLabelColor: _isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        indicatorColor: AppColors.primaryBlue,
                        tabs: const [
                          Tab(
                            icon: Icon(Icons.edit),
                            text: 'Signatures',
                          ),
                          Tab(
                            icon: Icon(Icons.verified),
                            text: 'Cachets',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSignaturesList(),
                          _buildCachetsList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignaturesList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Signatures (${_signatures.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _addSignature('signature'),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une signature'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _signatures.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.edit,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune signature trouvée',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _signatures.length,
                  itemBuilder: (context, index) {
                    final signature = _signatures[index];
                    return _buildSignatureCard(signature);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCachetsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cachets (${_cachets.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _addSignature('cachet'),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un cachet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cachets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun cachet trouvé',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cachets.length,
                  itemBuilder: (context, index) {
                    final cachet = _cachets[index];
                    return _buildSignatureCard(cachet);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSignatureCard(Signature signature) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
          child: Icon(
            signature.type == 'signature' ? Icons.edit : Icons.verified,
            color: AppColors.primaryBlue,
          ),
        ),
        title: Text(
          signature.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (signature.description != null)
              Text(signature.description!),
            Text(
              'Créé le ${_formatDate(signature.createdAt)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _editSignature(signature),
              icon: const Icon(Icons.edit),
              color: AppColors.primaryBlue,
            ),
            IconButton(
              onPressed: () => _deleteSignature(signature),
              icon: const Icon(Icons.delete),
              color: Colors.red,
            ),
          ],
        ),
        onTap: () => _editSignature(signature),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildHeader(BuildContext context, bool isDarkMode, bool isDesktop) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 28,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signatures et Cachets',
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 24,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Gérez les signatures et cachets pour vos documents',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit,
                          size: 16,
                          color: theme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_signatures.length} Signatures',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_cachets.length} Cachets',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isDarkMode = !_isDarkMode;
                      });
                    },
                    icon: Icon(
                      _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                    tooltip: _isDarkMode ? 'Mode clair' : 'Mode sombre',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData.dark().copyWith(
      primaryColor: AppColors.primaryBlue,
      scaffoldBackgroundColor: Colors.black,
      cardColor: Colors.grey[900],
      dividerColor: Colors.grey[700],
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData.light().copyWith(
      primaryColor: AppColors.primaryBlue,
      scaffoldBackgroundColor: Colors.grey[100],
      cardColor: Colors.white,
      dividerColor: Colors.grey[300],
    );
  }
}

class _SignatureDialog extends StatefulWidget {
  final String type;
  final Signature? initialSignature;

  const _SignatureDialog({
    required this.type,
    this.initialSignature,
  });

  @override
  _SignatureDialogState createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _imagePath;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.initialSignature != null) {
      _nameController.text = widget.initialSignature!.name;
      _descriptionController.text = widget.initialSignature!.description ?? '';
      _imagePath = widget.initialSignature!.imagePath;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 600,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _imagePath = image.path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.type == 'signature' ? 'Signature' : 'Cachet'}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nom',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Le nom est requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optionnel)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              if (_imagePath != null)
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.file(
                    File(_imagePath!),
                    fit: BoxFit.contain,
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: Text(_imagePath == null ? 'Sélectionner une image' : 'Changer l\'image'),
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
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop({
                'name': _nameController.text,
                'description': _descriptionController.text.isEmpty ? null : _descriptionController.text,
                'imagePath': _imagePath,
              });
            }
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}