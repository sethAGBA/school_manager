import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:school_manager/screens/staff_page.dart';
import 'package:school_manager/screens/timetable_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/dashboard_home.dart';
import 'screens/students_page.dart';
import 'screens/grades_page.dart';
import 'screens/payments_page.dart';
import 'screens/settings_page.dart';
import 'widgets/sidebar.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/permission_service.dart';
import 'screens/auth/login_page.dart';
import 'utils/snackbar.dart';
import 'screens/auth/users_management_page.dart';
import 'package:school_manager/models/user.dart';
import 'screens/license_page.dart' as app_license;
import 'services/license_service.dart';
import 'screens/subjects_page.dart';
import 'screens/finance_and_inventory_page.dart';
import 'screens/audit_page.dart';
import 'package:intl/date_symbol_data_local.dart';

const List<String> kFontFallback = [
  // Common system fonts with broad glyph coverage
  'Helvetica Neue', 'Helvetica', 'Arial', 'Times New Roman', 'Georgia',
  // Symbols/emoji fallbacks
  'Apple Symbols', 'Apple Color Emoji', 'Noto Color Emoji', 'Segoe UI Emoji',
  // Noto families if present
  'Noto Sans Symbols', 'Noto Sans Symbols 2', 'Noto Sans',
  // Broad legacy unicode fonts
  'Symbola', 'Arial Unicode MS',
];

TextTheme _textThemeWithFallback(TextTheme base) {
  return TextTheme(
    displayLarge: base.displayLarge?.copyWith(fontFamilyFallback: kFontFallback),
    displayMedium: base.displayMedium?.copyWith(fontFamilyFallback: kFontFallback),
    displaySmall: base.displaySmall?.copyWith(fontFamilyFallback: kFontFallback),
    headlineLarge: base.headlineLarge?.copyWith(fontFamilyFallback: kFontFallback),
    headlineMedium: base.headlineMedium?.copyWith(fontFamilyFallback: kFontFallback),
    headlineSmall: base.headlineSmall?.copyWith(fontFamilyFallback: kFontFallback),
    titleLarge: base.titleLarge?.copyWith(fontFamilyFallback: kFontFallback),
    titleMedium: base.titleMedium?.copyWith(fontFamilyFallback: kFontFallback),
    titleSmall: base.titleSmall?.copyWith(fontFamilyFallback: kFontFallback),
    bodyLarge: base.bodyLarge?.copyWith(fontFamilyFallback: kFontFallback),
    bodyMedium: base.bodyMedium?.copyWith(fontFamilyFallback: kFontFallback),
    bodySmall: base.bodySmall?.copyWith(fontFamilyFallback: kFontFallback),
    labelLarge: base.labelLarge?.copyWith(fontFamilyFallback: kFontFallback),
    labelMedium: base.labelMedium?.copyWith(fontFamilyFallback: kFontFallback),
    labelSmall: base.labelSmall?.copyWith(fontFamilyFallback: kFontFallback),
  );
}


// Global navigator key to allow navigation from anywhere (e.g., logout)
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<_MyAppState> myAppKey = GlobalKey<_MyAppState>();
ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  // Initialize sqflite for desktop (Windows/Linux/macOS) using FFI
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(MyApp(key: myAppKey));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialTheme();
    _ensureAdminExists();
    // Always start on Login: do not auto-load persisted session here
  }

  Future<void> _loadCurrentUser() async {
    final user = await AuthService.instance.getCurrentUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
      });
    }
  }

  void _onLoginSuccess() async {
    // After successful login (and 2FA if any), always navigate to dashboard
    // The "remember_me" preference only affects future app launches, not immediate navigation.
    appNavigatorKey.currentState?.pushReplacement(
      MaterialPageRoute(
        builder: (_) => SchoolDashboard(
          onThemeToggle: _toggleTheme,
          isDarkMode: themeModeNotifier.value == ThemeMode.dark,
        ),
      ),
    );
  }

  void _onLogout() {
    // Always force back to login screen
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage(onSuccess: _onLoginSuccess)),
      (route) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadInitialTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool('isDarkMode') ?? true;
    themeModeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  void _toggleTheme(bool isDark) async {
    themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', isDark);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentThemeMode, child) {
        return MaterialApp(
          title: 'École Manager',
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          theme: ThemeData(
            fontFamily: 'Roboto',
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.white,
            textTheme: (() {
              final base = _textThemeWithFallback(ThemeData.light().textTheme);
              return base.copyWith(
                bodyLarge: base.bodyLarge?.copyWith(color: Colors.grey[800]),
                bodyMedium: base.bodyMedium?.copyWith(color: Colors.grey[600]),
              );
            })(),
            cardColor: Colors.white,
            dividerColor: Colors.grey[300],
            iconTheme: IconThemeData(color: Colors.grey[800]),
          ),
          darkTheme: ThemeData(
            fontFamily: 'Roboto',
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[900],
            textTheme: (() {
              final base = _textThemeWithFallback(ThemeData.dark().textTheme);
              return base.copyWith(
                bodyLarge: base.bodyLarge?.copyWith(color: Colors.white),
                bodyMedium: base.bodyMedium?.copyWith(color: Colors.white70),
              );
            })(),
            cardColor: Colors.grey[850],
            dividerColor: Colors.white24,
            iconTheme: IconThemeData(color: Colors.white),
          ),
          themeMode: currentThemeMode,
          // Always start on Login page
          home: LoginPage(onSuccess: _onLoginSuccess),
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Previously we were forcing logout on background/resume, which caused unintended logouts.
    // This behavior is now disabled to allow normal login persistence.
  }
}

Future<void> _ensureAdminExists() async {
  try {
    final users = await DatabaseService().getAllUserRows();
    if (users.isEmpty) {
      await AuthService.instance.createOrUpdateUser(
        username: 'admin',
        displayName: 'Administrateur',
        role: 'admin',
        password: 'admin',
        enable2FA: false,
      );
    }
  } catch (_) {}
}

class SchoolDashboard extends StatefulWidget {
  final ValueChanged<bool> onThemeToggle;
  final bool isDarkMode;

  SchoolDashboard({required this.onThemeToggle, required this.isDarkMode});

  @override
  _SchoolDashboardState createState() => _SchoolDashboardState();
}

// Helper accessible from widgets without importing services
Future<void> performGlobalLogout(BuildContext context) async {
  await AuthService.instance.logout();
  // Return to root and rebuild MyApp so home shows LoginPage
  appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  myAppKey.currentState?._onLogout();
}

class _SchoolDashboardState extends State<SchoolDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  late final List<Widget> _pages;
  late final List<String> _pagePermissions;
  String? _role;
  Set<String>? _permissions;
  bool _licenseActive = false;
  bool _allLicensesConsumed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();

    _pages = [
      DashboardHome(onNavigate: _onMenuItemSelected),
      StudentsPage(),
      StaffPage(),
      GradesPage(),
      PaymentsPage(),
      SettingsPage(),
      const UsersManagementPage(),
      const TimetablePage(),
      const app_license.LicensePage(),
      const SubjectsPage(),
      const FinanceAndInventoryPage(),
      const AuditPage(),
    ];
    _pagePermissions = [
      'view_dashboard',
      'view_students',
      'view_staff',
      'view_grades',
      'view_payments',
      'view_settings',
      'view_users',
      'view_timetables',
      'view_license',
      'view_subjects',
      'view_finance_inventory',
      'view_audits',
    ];
    _loadCurrentRole();
    _initLicenseListener();
  }

  Future<void> _loadCurrentRole() async {
    final user = await AuthService.instance.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _role = user?.role;
      _permissions = user == null
          ? null
          : PermissionService.decodePermissions(
              user.permissions,
              role: user.role,
            );
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onMenuItemSelected(int index) {
    setState(() {
      _selectedIndex = index;
      _animationController.forward(from: 0);
    });
  }

  void _initLicenseListener() async {
    _licenseActive = await LicenseService.instance.hasActive();
    _allLicensesConsumed = await LicenseService.instance.allKeysUsed();
    if (mounted) {
      setState(() {
        if (!(_licenseActive || _allLicensesConsumed)) _selectedIndex = 5;
      });
    }
    LicenseService.instance.activeNotifier.addListener(() async {
      final active = await LicenseService.instance.hasActive();
      final allUsed = await LicenseService.instance.allKeysUsed();
      if (mounted) {
        setState(() {
          _licenseActive = active;
          _allLicensesConsumed = allUsed;
          if (!(active || allUsed)) _selectedIndex = 5;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Compute allowed indices for current user
    final Set<int> allowedIndices = {};
    final Set<String> perms = _permissions ?? {};
    final bool isAdmin = (_role == 'admin');
    for (int i = 0; i < _pagePermissions.length; i++) {
      if (isAdmin || perms.contains(_pagePermissions[i])) {
        allowedIndices.add(i);
      }
    }
    // Gate by license: without active license, only Settings (index 5)
    if (!(_licenseActive || _allLicensesConsumed)) {
      allowedIndices
        ..clear()
        ..add(5);
    }
    final bool hasAnyAccess = allowedIndices.isNotEmpty;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              Sidebar(
                selectedIndex: _selectedIndex,
                onItemSelected: _onMenuItemSelected,
                isDarkMode: widget.isDarkMode,
                onThemeToggle: widget.onThemeToggle,
                animationController: _animationController,
                currentRole: _role,
                currentPermissions: _permissions,
                allowedIndices: allowedIndices,
              ),
              Expanded(
                child: hasAnyAccess
                    ? FadeTransition(
                        opacity: _fadeAnimation,
                        child: allowedIndices.contains(_selectedIndex)
                            ? _pages[_selectedIndex]
                            : _buildAccessDenied(context),
                      )
                    : _buildNoAccessScreen(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _buildAccessDenied(BuildContext context) {
  final theme = Theme.of(context);
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline,
          size: 64,
          color: theme.textTheme.bodyLarge?.color?.withOpacity(0.5),
        ),
        const SizedBox(height: 12),
        Text(
          'Accès refusé',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Vous n\'avez pas la permission d\'accéder à cet écran.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

Widget _buildNoAccessScreen(BuildContext context) {
  final theme = Theme.of(context);
  return Container(
    color: theme.scaffoldBackgroundColor,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.report_gmailerrorred_outlined,
            size: 72,
            color: theme.textTheme.bodyLarge?.color?.withOpacity(0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Aucun accès',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Votre compte n\'a accès à aucun écran. Veuillez contacter un administrateur.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
