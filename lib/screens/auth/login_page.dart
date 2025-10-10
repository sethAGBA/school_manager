import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_manager/services/auth_service.dart';
import 'package:school_manager/screens/auth/two_factor_page.dart';
import 'package:school_manager/services/database_service.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onSuccess;
  const LoginPage({super.key, required this.onSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _obscure = true;
  bool _rememberMe = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
          ),
        );

    _animationController.forward();

    // Prefill remember me and username if previously saved
    SharedPreferences.getInstance().then((prefs) {
      final remembered = prefs.getBool('remember_me') ?? false;
      final username = prefs.getString('remember_username') ?? '';
      if (mounted) {
        setState(() {
          _rememberMe = remembered;
          if (remembered && username.isNotEmpty) {
            _usernameController.text = username;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final res = await AuthService.instance.authenticatePassword(
      _usernameController.text.trim(),
      _passwordController.text,
    );
    setState(() {
      _isLoading = false;
    });
    if (!mounted) return;
    if (!res.ok) {
      try {
        await DatabaseService().logAudit(
          category: 'auth',
          action: 'login_failed',
          details: 'username=${_usernameController.text.trim()}',
          username: _usernameController.text.trim(),
          success: false,
        );
      } catch (_) {}
      setState(() {
        _error = 'Identifiants invalides';
      });
      return;
    }
    if (res.requires2FA) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TwoFactorPage(
            username: _usernameController.text.trim(),
            onSuccess: () async {
              try {
                await DatabaseService().logAudit(
                  category: 'auth',
                  action: 'login_success',
                  details: '2FA',
                  username: _usernameController.text.trim(),
                );
              } catch (_) {}
              await AuthService.instance.finalizeLogin(
                _usernameController.text.trim(),
              );
              // Save remember preference after successful full login (incl. 2FA)
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('remember_me', _rememberMe);
                if (_rememberMe) {
                  await prefs.setString(
                    'remember_username',
                    _usernameController.text.trim(),
                  );
                } else {
                  await prefs.remove('remember_username');
                }
              } catch (_) {}
              if (!mounted) return;
              Navigator.of(context).pop();
              widget.onSuccess();
            },
          ),
        ),
      );
    } else {
      try {
        await DatabaseService().logAudit(
          category: 'auth',
          action: 'login_success',
          username: _usernameController.text.trim(),
        );
      } catch (_) {}
      await AuthService.instance.finalizeLogin(_usernameController.text.trim());
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_me', _rememberMe);
        if (_rememberMe) {
          await prefs.setString(
            'remember_username',
            _usernameController.text.trim(),
          );
        } else {
          await prefs.remove('remember_username');
        }
      } catch (_) {}
      widget.onSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF1E293B),
                    const Color(0xFF334155),
                    const Color(0xFF475569),
                  ]
                : [
                    const Color(0xFF6366F1),
                    const Color(0xFF8B5CF6),
                    const Color(0xFFEC4899),
                  ],
          ),
        ),
        child: Stack(
          children: [
            // Animated background elements
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            // Main content
            Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Card(
                      elevation: 24,
                      shadowColor: Colors.black.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.cardColor,
                              theme.cardColor.withOpacity(0.9),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Shortcuts(
                            shortcuts: <LogicalKeySet, Intent>{
                              LogicalKeySet(LogicalKeyboardKey.enter):
                                  const ActivateIntent(),
                              LogicalKeySet(LogicalKeyboardKey.numpadEnter):
                                  const ActivateIntent(),
                            },
                            child: Actions(
                              actions: <Type, Action<Intent>>{
                                ActivateIntent: CallbackAction<ActivateIntent>(
                                  onInvoke: (intent) {
                                    if (!_isLoading) _login();
                                    return null;
                                  },
                                ),
                              },
                              child: Focus(
                                autofocus: true,
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Logo and title
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF6366F1),
                                              Color(0xFF8B5CF6),
                                            ],
                                          ),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFF6366F1,
                                              ).withOpacity(0.3),
                                              blurRadius: 20,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.school,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        'École Manager',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              theme.textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Connexion',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: theme
                                              .textTheme
                                              .headlineMedium
                                              ?.color,
                                        ),
                                      ),
                                      const SizedBox(height: 32),

                                      // Username field
                                      TextFormField(
                                        controller: _usernameController,
                                        decoration: InputDecoration(
                                          labelText: 'Nom d\'utilisateur',
                                          prefixIcon: const Icon(
                                            Icons.person_outline,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: const BorderSide(
                                              color: Color(0xFF6366F1),
                                              width: 2,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: theme
                                              .inputDecorationTheme
                                              .fillColor,
                                        ),
                                        textInputAction: TextInputAction.next,
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
                                            ? 'Requis'
                                            : null,
                                      ),
                                      const SizedBox(height: 20),

                                      // Password field
                                      TextFormField(
                                        controller: _passwordController,
                                        decoration: InputDecoration(
                                          labelText: 'Mot de passe',
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                          ),
                                          suffixIcon: IconButton(
                                            onPressed: () => setState(
                                              () => _obscure = !_obscure,
                                            ),
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                              color: theme.iconTheme.color,
                                            ),
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: const BorderSide(
                                              color: Color(0xFF6366F1),
                                              width: 2,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: theme
                                              .inputDecorationTheme
                                              .fillColor,
                                        ),
                                        obscureText: _obscure,
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) {
                                          if (!_isLoading) _login();
                                        },
                                        validator: (v) =>
                                            (v == null || v.isEmpty)
                                            ? 'Requis'
                                            : null,
                                      ),

                                      // Error message
                                      if (_error != null) ...[
                                        const SizedBox(height: 16),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.red.withOpacity(
                                                0.3,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.error_outline,
                                                color: Colors.red,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _error!,
                                                  style: const TextStyle(
                                                    color: Colors.red,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],

                                      const SizedBox(height: 32),
                                      // Remember me
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: _rememberMe,
                                            onChanged: (v) => setState(
                                              () => _rememberMe = v ?? false,
                                            ),
                                          ),
                                          const Text('Se souvenir de moi'),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Login button
                                      SizedBox(
                                        width: double.infinity,
                                        height: 56,
                                        child: ElevatedButton(
                                          onPressed: _isLoading ? null : _login,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF6366F1,
                                            ),
                                            foregroundColor: Colors.white,
                                            elevation: 8,
                                            shadowColor: const Color(
                                              0xFF6366F1,
                                            ).withOpacity(0.3),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(
                                                      Icons.login,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text(
                                                      'Se connecter',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton.icon(
                                        onPressed: _isLoading
                                            ? null
                                            : () async {
                                                setState(() {
                                                  _error = null;
                                                  _isLoading = true;
                                                });
                                                try {
                                                  await AuthService.instance
                                                      .createOrUpdateUser(
                                                        username: 'admin',
                                                        displayName:
                                                            'Administrateur',
                                                        role: 'admin',
                                                        password: 'admin',
                                                        enable2FA: false,
                                                      );
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        "Compte admin réinitialisé ",
                                                      ),
                                                      backgroundColor:
                                                          Colors.green,
                                                    ),
                                                  );
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Erreur: $e',
                                                      ),
                                                    ),
                                                  );
                                                } finally {
                                                  if (mounted)
                                                    setState(() {
                                                      _isLoading = false;
                                                    });
                                                }
                                              },
                                        icon: const Icon(Icons.manage_accounts),
                                        label: const Text(
                                          'Réinitialiser admin ',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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
