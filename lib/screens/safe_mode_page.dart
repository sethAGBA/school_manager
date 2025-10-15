import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/utils/snackbar.dart';

class SafeModePage extends StatefulWidget {
  const SafeModePage({Key? key}) : super(key: key);

  @override
  State<SafeModePage> createState() => _SafeModePageState();
}

class _SafeModePageState extends State<SafeModePage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _currentPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isCurrentPasswordVisible = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeSafeMode();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  void _initializeSafeMode() {
    SafeModeService.instance.initialize();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
  }

  Future<void> _enableSafeMode() async {
    if (_passwordController.text.isEmpty) {
      showSnackBar(context, 'Veuillez entrer un mot de passe', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await SafeModeService.instance.enableSafeMode(
        _passwordController.text,
      );

      if (success) {
        showSnackBar(context, 'Mode coffre fort activé avec succès');
        _passwordController.clear();
        setState(() {});
        try {
          final u = await AuthService.instance.getCurrentUser();
          await DatabaseService().logAudit(
            category: 'safe_mode',
            action: 'enable',
            username: u?.username,
          );
        } catch (_) {}
      } else {
        showSnackBar(context, 'Erreur lors de l\'activation du mode coffre fort', isError: true);
        try {
          final u = await AuthService.instance.getCurrentUser();
          await DatabaseService().logAudit(
            category: 'safe_mode',
            action: 'enable',
            username: u?.username,
            success: false,
          );
        } catch (_) {}
      }
    } catch (e) {
      showSnackBar(context, 'Erreur: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _disableSafeMode() async {
    if (_currentPasswordController.text.isEmpty) {
      showSnackBar(context, 'Veuillez entrer le mot de passe actuel', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await SafeModeService.instance.disableSafeMode(
        _currentPasswordController.text,
      );

      if (success) {
        showSnackBar(context, 'Mode coffre fort désactivé avec succès');
        _currentPasswordController.clear();
        setState(() {});
        try {
          final u = await AuthService.instance.getCurrentUser();
          await DatabaseService().logAudit(
            category: 'safe_mode',
            action: 'disable',
            username: u?.username,
          );
        } catch (_) {}
      } else {
        showSnackBar(context, 'Mot de passe incorrect', isError: true);
        try {
          final u = await AuthService.instance.getCurrentUser();
          await DatabaseService().logAudit(
            category: 'safe_mode',
            action: 'disable',
            username: u?.username,
            success: false,
          );
        } catch (_) {}
      }
    } catch (e) {
      showSnackBar(context, 'Erreur: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    if (_currentPasswordController.text.isEmpty ||
        _newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      showSnackBar(context, 'Veuillez remplir tous les champs', isError: true);
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      showSnackBar(context, 'Les nouveaux mots de passe ne correspondent pas', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await SafeModeService.instance.changePassword(
        _currentPasswordController.text,
        _newPasswordController.text,
      );

      if (success) {
        showSnackBar(context, 'Mot de passe modifié avec succès');
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() {});
        try {
          final u = await AuthService.instance.getCurrentUser();
          await DatabaseService().logAudit(
            category: 'safe_mode',
            action: 'change_password',
            username: u?.username,
          );
        } catch (_) {}
      } else {
        showSnackBar(context, 'Mot de passe actuel incorrect', isError: true);
        try {
          final u = await AuthService.instance.getCurrentUser();
          await DatabaseService().logAudit(
            category: 'safe_mode',
            action: 'change_password',
            username: u?.username,
            success: false,
          );
        } catch (_) {}
      }
    } catch (e) {
      showSnackBar(context, 'Erreur: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool isVisible,
    required VoidCallback onToggleVisibility,
    String? hintText,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !isVisible,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(isVisible ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggleVisibility,
        ),
        border: const OutlineInputBorder(),
        filled: true,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Ce champ est requis';
        }
        return null;
      },
    );
  }

  Widget _buildSafeModeStatus() {
    return ValueListenableBuilder<bool>(
      valueListenable: SafeModeService.instance.isEnabledNotifier,
      builder: (context, isEnabled, child) {
        return Card(
          color: Theme.of(context).cardColor,
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  isEnabled ? Icons.security : Icons.security_outlined,
                  size: 48,
                  color: isEnabled ? Colors.red : Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  isEnabled ? 'Mode coffre fort activé' : 'Mode coffre fort désactivé',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isEnabled ? Colors.red : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEnabled
                      ? 'Les exports et modifications des bulletins sont bloqués'
                      : 'Toutes les fonctionnalités sont disponibles',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnableSection() {
    return ValueListenableBuilder<bool>(
      valueListenable: SafeModeService.instance.isEnabledNotifier,
      builder: (context, isEnabled, child) {
        if (isEnabled) return const SizedBox.shrink();

        return Card(
          color: Theme.of(context).cardColor,
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activer le mode coffre fort',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Le mode coffre fort bloquera toutes les exports et modifications des bulletins. Seul un administrateur pourra le désactiver.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                _buildPasswordField(
                  controller: _passwordController,
                  label: 'Mot de passe',
                  isVisible: _isPasswordVisible,
                  onToggleVisibility: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                  hintText: 'Entrez un mot de passe sécurisé',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _enableSafeMode,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.security),
                    label: Text(_isLoading ? 'Activation...' : 'Activer le mode coffre fort'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildDisableSection() {
    return ValueListenableBuilder<bool>(
      valueListenable: SafeModeService.instance.isEnabledNotifier,
      builder: (context, isEnabled, child) {
        if (!isEnabled) return const SizedBox.shrink();

        return Card(
          color: Theme.of(context).cardColor,
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Désactiver le mode coffre fort',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Entrez le mot de passe pour désactiver le mode coffre fort et restaurer toutes les fonctionnalités.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                _buildPasswordField(
                  controller: _currentPasswordController,
                  label: 'Mot de passe actuel',
                  isVisible: _isCurrentPasswordVisible,
                  onToggleVisibility: () {
                    setState(() {
                      _isCurrentPasswordVisible = !_isCurrentPasswordVisible;
                    });
                  },
                  hintText: 'Entrez le mot de passe du mode coffre fort',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _disableSafeMode,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.security_outlined),
                    label: Text(_isLoading ? 'Désactivation...' : 'Désactiver le mode coffre fort'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildChangePasswordSection() {
    return ValueListenableBuilder<bool>(
      valueListenable: SafeModeService.instance.isEnabledNotifier,
      builder: (context, isEnabled, child) {
        if (!isEnabled) return const SizedBox.shrink();

        return Card(
          color: Theme.of(context).cardColor,
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Changer le mot de passe',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Modifiez le mot de passe du mode coffre fort.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),
                _buildPasswordField(
                  controller: _currentPasswordController,
                  label: 'Mot de passe actuel',
                  isVisible: _isCurrentPasswordVisible,
                  onToggleVisibility: () {
                    setState(() {
                      _isCurrentPasswordVisible = !_isCurrentPasswordVisible;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildPasswordField(
                  controller: _newPasswordController,
                  label: 'Nouveau mot de passe',
                  isVisible: _isNewPasswordVisible,
                  onToggleVisibility: () {
                    setState(() {
                      _isNewPasswordVisible = !_isNewPasswordVisible;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  label: 'Confirmer le nouveau mot de passe',
                  isVisible: _isConfirmPasswordVisible,
                  onToggleVisibility: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _changePassword,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_reset),
                    label: Text(_isLoading ? 'Modification...' : 'Changer le mot de passe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
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
              size: isDesktop ? 32 : 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mode Coffre-Fort',
                  style: TextStyle(
                    fontSize: isDesktop ? 28 : 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Protégez les données sensibles en restreignant l\'accès et les modifications.',
                  style: TextStyle(
                    fontSize: isDesktop ? 15 : 13,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    height: 1.4,
                  ),
                ),
              ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _buildHeader(context),
            ),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSafeModeStatus(),
                        const SizedBox(height: 24),
                        _buildEnableSection(),
                        const SizedBox(height: 24),
                        _buildDisableSection(),
                        const SizedBox(height: 24),
                        _buildChangePasswordSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
