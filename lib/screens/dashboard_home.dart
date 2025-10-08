import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/services/database_service.dart';
import '../widgets/stats_card.dart';
import '../widgets/activity_item.dart';
import '../widgets/quick_action.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/utils/date_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_manager/services/license_service.dart';

ValueNotifier<String> academicYearNotifier = ValueNotifier<String>('2024-2025');

Future<void> refreshAcademicYear() async {
  final prefs = await SharedPreferences.getInstance();
  academicYearNotifier.value = prefs.getString('academic_year') ?? '2024-2025';
}

class DashboardHome extends StatefulWidget {
  final Function(int) onNavigate;

  const DashboardHome({required this.onNavigate, Key? key}) : super(key: key);

  @override
  _DashboardHomeState createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  final DatabaseService _dbService = DatabaseService();
  int _studentCount = 0;
  int _staffCount = 0;
  int _classCount = 0;
  double _totalRevenue = 0.0;
  List<ActivityItem> _recentActivities = [];
  List<FlSpot> _enrollmentSpots = [];
  List<String> _enrollmentMonths = []; // New: to store month labels
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    refreshAcademicYear();
    academicYearNotifier.addListener(_onYearChanged);
    _loadDashboardData();
  }

  void _onYearChanged() {
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final String currentYear = academicYearNotifier.value;
      final students = await _dbService.getStudents(academicYear: currentYear);
      final staff = await _dbService.getStaff();
      final allClasses = await _dbService.getClasses();
      final classes = allClasses
          .where((c) => c.academicYear == currentYear)
          .toList();
      final payments = await _dbService.getAllPayments();

      // Compter uniquement les paiements d'élèves de l'année en cours
      final studentIdsThisYear = students.map((s) => s.id).toSet();
      final totalRevenue = payments
          .where((p) => studentIdsThisYear.contains(p.studentId))
          .fold<double>(0, (sum, item) => sum + item.amount);

      // Fetch recent activities
      final recentPayments = (await _dbService.getRecentPayments(
        3,
      )).where((p) => studentIdsThisYear.contains(p.studentId)).toList();

      // Filter staff by current academic year (hire date within academic year)
      final allRecentStaff = await _dbService.getRecentStaff(
        10,
      ); // Get more to filter
      final recentStaff = allRecentStaff
          .where((staff) {
            final hireYear = staff.hireDate.year;
            final academicYearStart = int.parse(currentYear.split('-')[0]);
            final academicYearEnd = int.parse(currentYear.split('-')[1]);
            return hireYear >= academicYearStart && hireYear <= academicYearEnd;
          })
          .take(3)
          .toList();

      final recentStudents = (await _dbService.getRecentStudents(
        3,
      )).where((s) => s.academicYear == currentYear).toList();

      List<ActivityItem> activities = [];
      for (var p in recentPayments) {
        final student = await _dbService.getStudentById(p.studentId);
        activities.add(
          ActivityItem(
            title: 'Paiement reçu',
            subtitle: 'Frais scolarité - ${student?.name ?? 'Inconnu'}',
            time: DateFormat('dd/MM/yyyy').format(DateTime.parse(p.date)),
            icon: Icons.payment,
            color: Color(0xFFF59E0B),
          ),
        );
      }
      for (var s in recentStaff) {
        activities.add(
          ActivityItem(
            title: 'Nouveau membre du personnel',
            subtitle: '${s.name} - ${s.role}',
            time: formatDdMmYyyy(
              s.hireDate,
            ), // Assuming hireDate is already DateTime
            icon: Icons.person_add,
            color: Color(0xFF10B981),
          ),
        );
      }
      for (var s in recentStudents) {
        activities.add(
          ActivityItem(
            title: 'Nouvel élève inscrit',
            subtitle: '${s.name} - ${s.className}',
            time: DateFormat(
              'dd/MM/yyyy',
            ).format(DateTime.parse(s.enrollmentDate)), // Use enrollmentDate
            icon: Icons.person_add,
            color: Color(0xFF3B82F6),
          ),
        );
      }

      // Sort activities by date (most recent first)
      activities.sort((a, b) {
        DateTime dateA = DateFormat('dd/MM/yyyy').parse(a.time);
        DateTime dateB = DateFormat('dd/MM/yyyy').parse(b.time);
        return dateB.compareTo(dateA);
      });

      // Fetch enrollment data for chart (année en cours uniquement)
      final Map<String, int> monthlyMap = {};
      for (final s in students) {
        if (s.enrollmentDate.trim().isEmpty) continue;
        final dt = DateTime.tryParse(s.enrollmentDate);
        if (dt == null) continue;
        final key = DateFormat('yyyy-MM').format(dt);
        monthlyMap[key] = (monthlyMap[key] ?? 0) + 1;
      }
      final monthlyEnrollment = monthlyMap.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      print("Monthly Enrollment Data ($currentYear): $monthlyEnrollment");
      List<FlSpot> spots = [];
      List<String> months = [];
      if (monthlyEnrollment.isNotEmpty) {
        for (int i = 0; i < monthlyEnrollment.length; i++) {
          spots.add(
            FlSpot(i.toDouble(), monthlyEnrollment[i].value.toDouble()),
          );
          months.add(monthlyEnrollment[i].key);
        }
      } else {
        // Fallback to static data if no real data is available
        spots = [
          FlSpot(0, 300),
          FlSpot(1, 320),
          FlSpot(2, 350),
          FlSpot(3, 400),
          FlSpot(4, 420),
          FlSpot(5, 450),
          FlSpot(6, 480),
          FlSpot(7, 500),
          FlSpot(8, 520),
          FlSpot(9, 540),
          FlSpot(10, 580),
          FlSpot(11, 600),
        ];
        months = [
          'Jan',
          'Fév',
          'Mar',
          'Avr',
          'Mai',
          'Juin',
          'Juil',
          'Août',
          'Sep',
          'Oct',
          'Nov',
          'Déc',
        ];
      }

      setState(() {
        _studentCount = students.length;
        _staffCount = staff.length;
        _classCount = classes.length;
        _totalRevenue = totalRevenue;
        _recentActivities = activities
            .take(5)
            .toList(); // Take top 5 recent activities
        _enrollmentSpots = spots;
        _enrollmentMonths = months;
        _isLoading = false;
      });
    } catch (e) {
      // Handle error appropriately
      print("Error loading dashboard data: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    academicYearNotifier.removeListener(_onYearChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: 'FCFA',
      decimalDigits: 0,
    );
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
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
                                  colors: [
                                    Color(0xFF6366F1),
                                    Color(0xFF8B5CF6),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.dashboard,
                                color: Colors.white,
                                size: isDesktop ? 32 : 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tableau de Bord',
                                  style: TextStyle(
                                    fontSize: isDesktop ? 32 : 24,
                                    fontWeight: FontWeight.bold,
                                    color: theme.textTheme.bodyLarge?.color,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Gérez votre école avec style et efficacité',
                                  style: TextStyle(
                                    fontSize: isDesktop ? 16 : 14,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withOpacity(0.7),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // License status, Academic Year and Notification Icon
                        Row(
                          children: [
                            _buildLicenseStatusPill(theme),
                            SizedBox(width: 12),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF10B981),
                                    Color(0xFF34D399),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                  SizedBox(width: 8),
                                  ValueListenableBuilder<String>(
                                    valueListenable: academicYearNotifier,
                                    builder: (context, year, _) => Text(
                                      'Année $year',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 16),
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
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 32),

              // Stats Cards
              _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : ScaleTransition(
                      scale: _scaleAnimation,
                      child: constraints.maxWidth > 800
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Expanded(
                                  child: StatsCard(
                                    title: 'Total Élèves',
                                    value: '$_studentCount',
                                    icon: Icons.people,
                                    color: Color(0xFF3B82F6),
                                    subtitle: '',
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: StatsCard(
                                    title: 'Personnel',
                                    value: '$_staffCount',
                                    icon: Icons.person,
                                    color: Color(0xFF10B981),
                                    subtitle: '',
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: StatsCard(
                                    title: 'Classes',
                                    value: '$_classCount',
                                    icon: Icons.class_,
                                    color: Color(0xFFF59E0B),
                                    subtitle: '',
                                  ),
                                ),
                                SizedBox(width: 20),
                                Expanded(
                                  child: StatsCard(
                                    title: 'Revenus',
                                    value: currencyFormatter.format(
                                      _totalRevenue,
                                    ),
                                    icon: Icons.account_balance_wallet,
                                    color: Color(0xFFEF4444),
                                    subtitle: '',
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                StatsCard(
                                  title: 'Total Élèves',
                                  value: '$_studentCount',
                                  icon: Icons.people,
                                  color: Color(0xFF3B82F6),
                                  subtitle: '',
                                ),
                                SizedBox(height: 20),
                                StatsCard(
                                  title: 'Personnel',
                                  value: '$_staffCount',
                                  icon: Icons.person,
                                  color: Color(0xFF10B981),
                                  subtitle: '',
                                ),
                                SizedBox(height: 20),
                                StatsCard(
                                  title: 'Classes',
                                  value: '$_classCount',
                                  icon: Icons.class_,
                                  color: Color(0xFFF59E0B),
                                  subtitle: '',
                                ),
                                SizedBox(height: 20),
                                StatsCard(
                                  title: 'Revenus',
                                  value: currencyFormatter.format(
                                    _totalRevenue,
                                  ),
                                  icon: Icons.account_balance_wallet,
                                  color: Color(0xFFEF4444),
                                  subtitle: '',
                                ),
                              ],
                            ),
                    ),
              SizedBox(height: 32),

              // Charts and Recent Activity
              Expanded(
                child: SingleChildScrollView(
                  child: constraints.maxWidth > 600
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Chart
                            Expanded(flex: 2, child: _buildChartCard(context)),
                            SizedBox(width: 20),
                            // Activities & Quick Actions
                            Expanded(
                              child: Column(
                                children: [
                                  _buildActivitiesCard(context),
                                  SizedBox(height: 20),
                                  _buildQuickActionsCard(context),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildChartCard(context),
                            SizedBox(height: 20),
                            _buildActivitiesCard(context),
                            SizedBox(height: 20),
                            _buildQuickActionsCard(context),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLicenseStatusPill(ThemeData theme) {
    return FutureBuilder<bool>(
      future: LicenseService.instance.allKeysUsed(),
      builder: (context, allSnap) {
        final allUsed = allSnap.data == true;
        return FutureBuilder<LicenseStatus>(
          future: LicenseService.instance.getStatus(),
          builder: (context, stSnap) {
            final st = stSnap.data;
            String text;
            Color start;
            Color end;
            if (allUsed) {
              text = 'Application débloquée';
              start = const Color(0xFF10B981);
              end = const Color(0xFF34D399);
            } else if (st?.isActive == true) {
              final days = st!.daysRemaining;
              text = 'Licence active • ${days}j restants';
              start = const Color(0xFF3B82F6);
              end = const Color(0xFF60A5FA);
            } else {
              text = 'Licence requise';
              start = const Color(0xFFF59E0B);
              end = const Color(0xFFFBBF24);
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [start, end]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: start.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.vpn_key_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChartCard(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Évolution des Inscriptions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1.6,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context).dividerColor!.withOpacity(0.5),
                    strokeWidth: 0.5,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Theme.of(context).dividerColor!.withOpacity(0.5),
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium!.color,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 &&
                            value.toInt() < _enrollmentMonths.length) {
                          return Text(
                            _enrollmentMonths[value.toInt()],
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium!.color,
                              fontSize: 12,
                            ),
                          );
                        }
                        return Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Theme.of(context).dividerColor!),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _enrollmentSpots,
                    isCurved: true,
                    color: Color(0xFF3B82F6),
                    barWidth: 4,
                    dotData: FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesCard(BuildContext context) {
    return Container(
      height: 320,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activités Récentes',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: _recentActivities.isEmpty
                    ? [Text('Aucune activité récente.')]
                    : _recentActivities,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actions Rapides',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: QuickAction(
                  title: 'Nouvel Élève',
                  icon: Icons.person_add,
                  color: Color(0xFF10B981),
                  onTap: () =>
                      widget.onNavigate(1), // Navigates to StudentsPage
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  title: 'Saisir Notes',
                  icon: Icons.edit,
                  color: Color(0xFF3B82F6),
                  onTap: () => widget.onNavigate(3), // Navigates to GradesPage
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: QuickAction(
                  title: 'Générer Bulletin',
                  icon: Icons.description,
                  color: Color(0xFFF59E0B),
                  onTap: () => widget.onNavigate(3), // Navigates to GradesPage
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  title: 'Emploi du Temps',
                  icon: Icons.schedule,
                  color: Color(0xFF8B5CF6),
                  onTap: () =>
                      widget.onNavigate(7), // Navigates to TimetablePage
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: QuickAction(
                  title: 'Paiements',
                  icon: Icons.payment,
                  color: Color(0xFF4CAF50),
                  onTap: () =>
                      widget.onNavigate(4), // Navigates to PaymentsPage
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  title: 'Ajouter Personnel',
                  icon: Icons.person_add_alt_1,
                  color: Color(0xFF60A5FA),
                  onTap: () => widget.onNavigate(2), // Navigates to StaffPage
                ),
              ),
            ],
          ),
        ], // Closing the Column
      ), // Closing the Container
    ); // Closing the Container
  }
}
