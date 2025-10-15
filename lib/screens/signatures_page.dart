import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:school_manager/constants/colors.dart';
import 'package:school_manager/models/signature.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/services/signature_assignment_service.dart';

class SignaturesPage extends StatefulWidget {
  const SignaturesPage({Key? key}) : super(key: key);

  @override
  _SignaturesPageState createState() => _SignaturesPageState();
}

class _SignaturesPageState extends State<SignaturesPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _dbService = DatabaseService();
  final SignatureAssignmentService _assignmentService = SignatureAssignmentService();
  List<Signature> _signatures = [];
  List<Signature> _cachets = [];
  List<Signature> _adminSignatures = [];
  List<Class> _classes = [];
  List<Staff> _staff = [];
  bool _isLoading = true;

  Future<void> _audit(String action, String details) async {
    try {
      final u = await AuthService.instance.getCurrentUser();
      await _dbService.logAudit(
        category: 'signatures',
        action: action,
        username: u?.username,
        details: details,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final futures = await Future.wait([
        _dbService.getAllSignatures(),
        _dbService.getClasses(),
        _dbService.getStaff(),
      ]);
      
      setState(() {
        final allSignatures = futures[0] as List<Signature>;
        final adminRoles = {'directeur', 'proviseur', 'vice_directeur'};
        _adminSignatures = allSignatures.where((s) => s.type == 'signature' && adminRoles.contains(s.associatedRole)).toList();
        _signatures = allSignatures.where((s) => s.type == 'signature' && !adminRoles.contains(s.associatedRole)).toList();
        _cachets = allSignatures.where((s) => s.type == 'cachet').toList();
        _classes = futures[1] as List<Class>;
        _staff = futures[2] as List<Staff>;
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

  Future<void> _showAssignmentModal(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AssignmentModal(
        signatures: _signatures,
        cachets: _cachets,
        classes: _classes,
        staff: _staff,
      ),
    );

    if (result != null) {
      try {
        // Utiliser le service d'assignation pour garantir l'unicité du "par défaut"
        await _assignmentService.assignSignatureToClass(
          signatureId: result['signatureId']!,
          className: (result['associatedClass'] ?? '').toString(),
          role: (result['associatedRole'] ?? '').toString(),
          staffId: result['staffId'],
          setAsDefault: result['isDefault'] ?? false,
        );
        _showSuccessSnackBar('Assignation effectuée avec succès');
        await _audit(
          'assign_signature',
          'signatureId=${result['signatureId']} name=${result['signatureName']} type=${result['type']} class=${result['associatedClass'] ?? ''} role=${result['associatedRole'] ?? ''} default=${result['isDefault'] ?? false}',
        );
        _loadSignatures();
      } catch (e) {
        _showErrorSnackBar('Erreur lors de l\'assignation: $e');
      }
    }
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
          associatedClass: result['associatedClass'],
          associatedRole: result['associatedRole'],
          staffId: result['staffId'],
          isDefault: result['isDefault'] ?? false,
        );

        await _dbService.insertSignature(signature);
        await _audit(
          'create_signature',
          'id=${signature.id} name=${signature.name} type=${signature.type} role=${signature.associatedRole ?? ''} class=${signature.associatedClass ?? ''} default=${signature.isDefault}',
        );
        // Si défini par défaut avec rôle/Classe, propager via le service pour nettoyer les autres défauts
        if ((signature.isDefault) && (result['associatedRole'] != null)) {
          await _assignmentService.assignSignatureToClass(
            signatureId: signature.id,
            className: (result['associatedClass'] ?? '').toString(),
            role: (result['associatedRole'] ?? '').toString(),
            staffId: result['staffId'],
            setAsDefault: true,
          );
          await _audit(
            'assign_signature',
            'signatureId=${signature.id} name=${signature.name} type=${signature.type} class=${result['associatedClass'] ?? ''} role=${result['associatedRole'] ?? ''} default=true',
          );
        }
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
          associatedClass: result['associatedClass'],
          associatedRole: result['associatedRole'],
          staffId: result['staffId'],
          isDefault: result['isDefault'] ?? false,
        );

        await _dbService.updateSignature(updatedSignature);
        await _audit(
          'update_signature',
          'id=${updatedSignature.id} name=${updatedSignature.name} type=${updatedSignature.type} role=${updatedSignature.associatedRole ?? ''} class=${updatedSignature.associatedClass ?? ''} default=${updatedSignature.isDefault}',
        );
        if ((result['isDefault'] ?? false) && (result['associatedRole'] != null)) {
          await _assignmentService.assignSignatureToClass(
            signatureId: updatedSignature.id,
            className: (result['associatedClass'] ?? '').toString(),
            role: (result['associatedRole'] ?? '').toString(),
            staffId: result['staffId'],
            setAsDefault: true,
          );
          await _audit(
            'assign_signature',
            'signatureId=${updatedSignature.id} name=${updatedSignature.name} type=${updatedSignature.type} class=${result['associatedClass'] ?? ''} role=${result['associatedRole'] ?? ''} default=true',
          );
        }
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
        await _audit(
          'delete_signature',
          'id=${signature.id} name=${signature.name} type=${signature.type}',
        );
        _showSuccessSnackBar('${signature.type == 'signature' ? 'Signature' : 'Cachet'} supprimé avec succès');
        _loadSignatures();
      } catch (e) {
        _showErrorSnackBar('Erreur lors de la suppression: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
        body: Column(
          children: [
            _buildHeader(context, isDarkMode, isDesktop),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(
                        top: 16,
                        left: 16,
                        right: 16,
                        bottom: 0,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: theme.cardColor,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
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
                          Tab(
                            icon: Icon(Icons.draw_outlined),
                            text: 'Signatures',
                          ),
                          Tab(
                            icon: Icon(Icons.verified),
                            text: 'Cachets',
                          ),
                          Tab(
                            icon: Icon(Icons.admin_panel_settings),
                            text: 'Administration',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSignaturesList(theme),
                          _buildCachetsList(theme),
                          _buildAdminList(theme),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildSignaturesList(ThemeData theme) {
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
                  color: theme.textTheme.bodyLarge?.color,
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
                        Icons.draw_outlined,
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

  Widget _buildCachetsList(ThemeData theme) {
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
                  color: theme.textTheme.bodyLarge?.color,
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

  Widget _buildAdminList(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final adminSignatures = _adminSignatures;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Administration (${adminSignatures.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addAdminSignature,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une signature admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: adminSignatures.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune signature administration',
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
                  itemCount: adminSignatures.length,
                  itemBuilder: (context, index) {
                    final signature = adminSignatures[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
                          child: const Icon(
                            Icons.admin_panel_settings,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                        title: Text(
                          signature.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rôle: ${signature.associatedRole ?? '-'}'),
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
                              tooltip: 'Modifier',
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Color(0xFF6366F1),
                              ),
                              onPressed: () => _editAdminSignature(signature),
                            ),
                            IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => _deleteSignature(signature),
                            ),
                          ],
                        ),
                        onTap: () => _editAdminSignature(signature),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addAdminSignature() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _AdminSignatureDialog(),
    );

    if (result != null) {
      try {
        final signature = Signature(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: result['name'] as String,
          type: 'signature',
          imagePath: result['imagePath'] as String?,
          description: result['description'] as String?,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          associatedClass: null,
          associatedRole: result['role'] as String?,
          staffId: null,
          isDefault: (result['isDefault'] as bool?) ?? false,
        );
        await _dbService.insertSignature(signature);
        await _audit(
          'create_signature',
          'id=${signature.id} name=${signature.name} type=${signature.type} role=${signature.associatedRole ?? ''} class= default=${signature.isDefault}',
        );
        if (signature.isDefault && signature.associatedRole != null) {
          await _assignmentService.assignSignatureToClass(
            signatureId: signature.id,
            className: '',
            role: signature.associatedRole!,
            setAsDefault: true,
          );
          await _audit(
            'assign_signature',
            'signatureId=${signature.id} name=${signature.name} type=${signature.type} class= role=${signature.associatedRole ?? ''} default=true',
          );
        }
        _showSuccessSnackBar('Signature administration ajoutée');
        _loadSignatures();
      } catch (e) {
        _showErrorSnackBar('Erreur lors de l\'ajout: $e');
      }
    }
  }

  Future<void> _editAdminSignature(Signature signature) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AdminSignatureDialog(initialSignature: signature),
    );

    if (result != null) {
      try {
        final updated = signature.copyWith(
          name: result['name'] as String?,
          imagePath: result['imagePath'] as String?,
          description: result['description'] as String?,
          associatedRole: result['role'] as String?,
          associatedClass: null,
          isDefault: (result['isDefault'] as bool?) ?? false,
          updatedAt: DateTime.now(),
        );
        await _dbService.updateSignature(updated);
        await _audit(
          'update_signature',
          'id=${updated.id} name=${updated.name} type=${updated.type} role=${updated.associatedRole ?? ''} class= default=${updated.isDefault}',
        );
        if (updated.isDefault && updated.associatedRole != null) {
          await _assignmentService.assignSignatureToClass(
            signatureId: updated.id,
            className: '',
            role: updated.associatedRole!,
            setAsDefault: true,
          );
          await _audit(
            'assign_signature',
            'signatureId=${updated.id} name=${updated.name} type=${updated.type} class= role=${updated.associatedRole ?? ''} default=true',
          );
        }
        _showSuccessSnackBar('Signature administration modifiée');
        _loadSignatures();
      } catch (e) {
        _showErrorSnackBar('Erreur lors de la modification: $e');
      }
    }
  }

  Widget _buildSignatureCard(Signature signature) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
          child: Icon(
            signature.type == 'signature' ? Icons.draw_outlined : Icons.verified,
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
              tooltip: 'Modifier',
              icon: const Icon(
                Icons.edit_outlined,
                color: Color(0xFF6366F1),
              ),
              onPressed: () => _editSignature(signature),
            ),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.red,
              ),
              onPressed: () => _deleteSignature(signature),
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
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.draw_outlined,
                        color: Colors.white,
                        size: isDesktop ? 32 : 24,
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
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showAssignmentModal(context),
                    icon: const Icon(Icons.assignment_ind, size: 16),
                    label: const Text('Assigner'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 16),
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
            ],
          ),
        ],
      ),
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

class _AdminSignatureDialog extends StatefulWidget {
  final Signature? initialSignature;

  const _AdminSignatureDialog({this.initialSignature});

  @override
  State<_AdminSignatureDialog> createState() => _AdminSignatureDialogState();
}

class _AdminSignatureDialogState extends State<_AdminSignatureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  String? _role = 'directeur';
  bool _isDefault = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialSignature != null) {
      final s = widget.initialSignature!;
      _nameController.text = s.name;
      _descriptionController.text = s.description ?? '';
      _imagePath = s.imagePath;
      _role = s.associatedRole ?? 'directeur';
      _isDefault = s.isDefault;
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 600,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() => _imagePath = image.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Signature Administration'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Le nom est requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optionnel)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
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
                  child: Image.file(File(_imagePath!), fit: BoxFit.contain),
                ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: Text(_imagePath == null ? 'Sélectionner une image' : 'Changer l\'image'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _role,
                items: const [
                  DropdownMenuItem(value: 'directeur', child: Text('Directeur')),
                  DropdownMenuItem(value: 'proviseur', child: Text('Proviseur')),
                  DropdownMenuItem(value: 'vice_directeur', child: Text('Vice-Directeur')),
                ],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Rôle administratif',
                ),
                onChanged: (v) => setState(() => _role = v),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('Définir comme signature par défaut'),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v ?? false),
                contentPadding: EdgeInsets.zero,
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
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop({
                'name': _nameController.text,
                'description': _descriptionController.text.isEmpty ? null : _descriptionController.text,
                'imagePath': _imagePath,
                'role': _role,
                'isDefault': _isDefault,
              });
            }
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _imagePath;
  final ImagePicker _picker = ImagePicker();
  
  // Nouveaux champs
  String? _selectedClass;
  String? _selectedRole;
  String? _selectedStaffId;
  bool _isDefault = false;
  List<Class> _classes = [];
  List<Staff> _staff = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialSignature != null) {
      _nameController.text = widget.initialSignature!.name;
      _descriptionController.text = widget.initialSignature!.description ?? '';
      _imagePath = widget.initialSignature!.imagePath;
      _selectedRole = widget.initialSignature!.associatedRole;
      _selectedStaffId = widget.initialSignature!.staffId;
      _isDefault = widget.initialSignature!.isDefault;
    }
    _loadClassesAndStaff();
  }

  Future<void> _loadClassesAndStaff() async {
    try {
      final dbService = DatabaseService();
      final futures = await Future.wait([
        dbService.getClasses(),
        dbService.getStaff(),
      ]);
      setState(() {
        _classes = futures[0] as List<Class>;
        _staff = futures[1] as List<Staff>;
        
        // Définir la classe sélectionnée après le chargement des données
        if (widget.initialSignature != null && widget.initialSignature!.associatedClass != null) {
          final matchingClass = _classes.firstWhere(
            (c) => c.name == widget.initialSignature!.associatedClass,
            orElse: () => Class.empty(),
          );
          if (matchingClass.name.isNotEmpty) {
            _selectedClass = '${matchingClass.name}_${matchingClass.academicYear}';
          }
        }
      });
    } catch (e) {
      // Gérer l'erreur silencieusement
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
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedClass,
                decoration: const InputDecoration(
                  labelText: 'Classe associée (optionnel)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Aucune classe')),
                  ..._classes.map((classItem) {
                    final uniqueValue = '${classItem.name}_${classItem.academicYear}';
                    return DropdownMenuItem(
                      value: uniqueValue,
                      child: Text('${classItem.name} (${classItem.academicYear})'),
                    );
                  }).toList(),
                ],
                onChanged: (value) => setState(() => _selectedClass = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Rôle associé (optionnel)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Aucun rôle')),
                  DropdownMenuItem(value: 'titulaire', child: Text('Titulaire')),
                  DropdownMenuItem(value: 'directeur', child: Text('Directeur')),
                  DropdownMenuItem(value: 'proviseur', child: Text('Proviseur')),
                  DropdownMenuItem(value: 'vice_directeur', child: Text('Vice-Directeur')),
                ],
                onChanged: (value) => setState(() => _selectedRole = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedStaffId,
                decoration: const InputDecoration(
                  labelText: 'Membre du personnel (optionnel)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Aucun')),
                  ..._staff.map((staff) {
                    return DropdownMenuItem(
                      value: staff.id,
                      child: Text(staff.name),
                    );
                  }).toList(),
                ],
                onChanged: (value) => setState(() => _selectedStaffId = value),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Définir comme signature par défaut'),
                value: _isDefault,
                onChanged: (value) => setState(() => _isDefault = value ?? false),
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
              // Extraire le nom de la classe depuis la valeur unique
              String? associatedClass;
              if (_selectedClass != null && _selectedClass!.contains('_')) {
                associatedClass = _selectedClass!.split('_')[0];
              } else if (_selectedClass != null) {
                associatedClass = _selectedClass;
              }
              
              Navigator.of(context).pop({
                'name': _nameController.text,
                'description': _descriptionController.text.isEmpty ? null : _descriptionController.text,
                'imagePath': _imagePath,
                'associatedClass': associatedClass,
                'associatedRole': _selectedRole,
                'staffId': _selectedStaffId,
                'isDefault': _isDefault,
              });
            }
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _AssignmentModal extends StatefulWidget {
  final List<Signature> signatures;
  final List<Signature> cachets;
  final List<Class> classes;
  final List<Staff> staff;

  const _AssignmentModal({
    required this.signatures,
    required this.cachets,
    required this.classes,
    required this.staff,
  });

  @override
  _AssignmentModalState createState() => _AssignmentModalState();
}

class _AssignmentModalState extends State<_AssignmentModal>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedSignatureId;
  String? _selectedCachetId;
  String? _selectedClass;
  String? _selectedRole;
  String? _selectedStaffId;
  bool _setAsDefault = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          minHeight: 400,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: theme.cardColor,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.assignment_ind,
                    color: AppColors.primaryBlue,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Assignation des Signatures',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ],
              ),
            ),
            // Tabs
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.draw_outlined),
                    text: 'Signatures',
                  ),
                  Tab(
                    icon: Icon(Icons.verified),
                    text: 'Cachets',
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  SingleChildScrollView(
                    child: _buildSignaturesTab(),
                  ),
                  SingleChildScrollView(
                    child: _buildCachetsTab(),
                  ),
                ],
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _canAssign() ? _assign : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Assigner'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignaturesTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Assigner une signature',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedClass,
            decoration: const InputDecoration(
              labelText: 'Classe',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sélectionner une classe')),
              const DropdownMenuItem(value: 'GLOBAL', child: Text('Aucune classe (global)')),
              ...widget.classes.map((classItem) {
                final uniqueValue = '${classItem.name}_${classItem.academicYear}';
                return DropdownMenuItem(
                  value: uniqueValue,
                  child: Text('${classItem.name} (${classItem.academicYear})'),
                );
              }).toList(),
            ],
            onChanged: (value) => setState(() => _selectedClass = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedRole,
            decoration: const InputDecoration(
              labelText: 'Rôle',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'titulaire', child: Text('Titulaire')),
              DropdownMenuItem(value: 'directeur', child: Text('Directeur')),
              DropdownMenuItem(value: 'vice_directeur', child: Text('Vice-Directeur')),
            ],
            onChanged: (value) => setState(() => _selectedRole = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedSignatureId,
            decoration: const InputDecoration(
              labelText: 'Signature',
              border: OutlineInputBorder(),
            ),
            items: widget.signatures.map((signature) {
              return DropdownMenuItem(
                value: signature.id,
                child: Text(signature.name),
              );
            }).toList(),
            onChanged: (value) => setState(() => _selectedSignatureId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedStaffId,
            decoration: const InputDecoration(
              labelText: 'Membre du personnel (optionnel)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Aucun')),
              ...widget.staff.map((staff) {
                return DropdownMenuItem(
                  value: staff.id,
                  child: Text(staff.name),
                );
              }).toList(),
            ],
            onChanged: (value) => setState(() => _selectedStaffId = value),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            title: const Text('Définir comme signature par défaut'),
            value: _setAsDefault,
            onChanged: (value) => setState(() => _setAsDefault = value ?? false),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildCachetsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Assigner un cachet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Le cachet de l\'établissement est global et s\'applique à tous les documents.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedCachetId,
            decoration: const InputDecoration(
              labelText: 'Cachet',
              border: OutlineInputBorder(),
            ),
            items: widget.cachets.map((cachet) {
              return DropdownMenuItem(
                value: cachet.id,
                child: Text(cachet.name),
              );
            }).toList(),
            onChanged: (value) => setState(() => _selectedCachetId = value),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            title: const Text('Définir comme cachet par défaut'),
            value: _setAsDefault,
            onChanged: (value) => setState(() => _setAsDefault = value ?? false),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  bool _canAssign() {
    if (_tabController.index == 0) {
      // Signatures tab
      return _selectedClass != null && 
             _selectedRole != null && 
             _selectedSignatureId != null;
    } else {
      // Cachets tab
      return _selectedCachetId != null; // cachet global, pas de classe
    }
  }

  void _assign() {
    if (_tabController.index == 0) {
      // Assigner signature
      final signature = widget.signatures.firstWhere(
        (s) => s.id == _selectedSignatureId,
      );
      
      String? associatedClass;
      if (_selectedClass == 'GLOBAL') {
        associatedClass = null;
      } else if (_selectedClass != null && _selectedClass!.contains('_')) {
        associatedClass = _selectedClass!.split('_')[0];
      } else if (_selectedClass != null) {
        associatedClass = _selectedClass;
      }

      Navigator.of(context).pop({
        'signatureId': signature.id,
        'signatureName': signature.name,
        'type': signature.type,
        'imagePath': signature.imagePath,
        'description': signature.description,
        'createdAt': signature.createdAt,
        'associatedClass': associatedClass,
        'associatedRole': _selectedRole,
        'staffId': _selectedStaffId,
        'isDefault': _setAsDefault,
      });
    } else {
      // Assigner cachet
      final cachet = widget.cachets.firstWhere(
        (c) => c.id == _selectedCachetId,
      );
      
      Navigator.of(context).pop({
        'signatureId': cachet.id,
        'signatureName': cachet.name,
        'type': cachet.type,
        'imagePath': cachet.imagePath,
        'description': cachet.description,
        'createdAt': cachet.createdAt,
        'associatedClass': null, // global
        'associatedRole': 'directeur',
        'staffId': null,
        'isDefault': _setAsDefault,
      });
    }
  }
}
