import 'package:flutter/material.dart';
// import 'dart:typed_data';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/class.dart';
// import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:school_manager/utils/snackbar.dart';
import 'package:intl/intl.dart';
import 'package:school_manager/services/auth_service.dart';

class StudentProfilePage extends StatefulWidget {
  final Student student;

  const StudentProfilePage({Key? key, required this.student}) : super(key: key);

  @override
  _StudentProfilePageState createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _dbService = DatabaseService();
  List<Payment> _payments = [];
  List<Map<String, dynamic>> _reportCards = [];
  bool _isLoading = true;

  String _fmtArchivedDate(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.trim().isEmpty) return '';
    try {
      DateTime? d;
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
        d = DateTime.tryParse(s);
      } else if (RegExp(r'^\d{2}/\d{2}/\d{4}').hasMatch(s)) {
        final parts = s.split('/');
        d = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
      if (d != null) return DateFormat('dd/MM/yyyy').format(d);
      return s;
    } catch (_) {
      return s;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final payments = await _dbService.getPaymentsForStudent(widget.student.id);
    final reportCards = await _dbService.getArchivedReportCardsForStudent(
      widget.student.id,
    );
    setState(() {
      _payments = payments;
      _reportCards = reportCards;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme, // Ensure the dialog inherits the current theme
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.1),
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Custom AppBar-like header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Profil de ${widget.student.name}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: theme.iconTheme.color),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // TabBar
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                  indicatorColor: Colors.transparent,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  tabs: [
                    Tab(
                      icon: Icon(
                        Icons.person,
                        color: _tabController.index == 0
                            ? Colors.white
                            : theme.textTheme.bodyMedium?.color,
                      ),
                      text: 'Infos',
                    ),
                    Tab(
                      icon: Icon(
                        Icons.payment,
                        color: _tabController.index == 1
                            ? Colors.white
                            : theme.textTheme.bodyMedium?.color,
                      ),
                      text: 'Paiements',
                    ),
                    Tab(
                      icon: Icon(
                        Icons.article,
                        color: _tabController.index == 2
                            ? Colors.white
                            : theme.textTheme.bodyMedium?.color,
                      ),
                      text: 'Bulletins',
                    ),
                  ],
                ),
              ),
              // TabBarView
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildInfoTab(),
                          _buildPaymentsTab(),
                          _buildReportCardsTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.withOpacity(0.02),
            Colors.blue.withOpacity(0.05),
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enhanced Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.1),
                    theme.colorScheme.secondary.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  // Enhanced Avatar with Status
                  Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.secondary,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: theme.scaffoldBackgroundColor,
                          child: Text(
                            widget.student.name.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.student.name,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'ID: ${widget.student.id}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.student.matricule != null &&
                          widget.student.matricule!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: theme.colorScheme.secondary.withOpacity(
                                0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            'Matricule: ${widget.student.matricule}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Né(e) le ${_formatDate(widget.student.dateOfBirth)} • ${_calculateAge(widget.student.dateOfBirth)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(
                        0.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatusChip(
                        '${widget.student.className}',
                        Icons.class_,
                        theme,
                      ),
                      const SizedBox(width: 12),
                      _buildStatusChip(
                        widget.student.gender == 'M' ? 'Garçon' : 'Fille',
                        widget.student.gender == 'M'
                            ? Icons.male
                            : Icons.female,
                        theme,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Enhanced Information Sections
            _buildInfoSection('Informations Personnelles', [
              _buildInfoCard(
                'Numéro de Matricule',
                widget.student.matricule ?? 'Non attribué',
                Icons.badge,
                theme,
              ),
              _buildInfoCard(
                'Date de Naissance',
                _formatDate(widget.student.dateOfBirth),
                Icons.cake,
                theme,
              ),
              _buildInfoCard(
                'Lieu de Naissance',
                widget.student.placeOfBirth ?? 'Non renseigné',
                Icons.location_city,
                theme,
              ),
              _buildInfoCard(
                'Âge',
                _calculateAge(widget.student.dateOfBirth),
                Icons.calendar_today,
                theme,
              ),
              _buildInfoCard(
                'Genre',
                widget.student.gender == 'M' ? 'Garçon' : 'Fille',
                widget.student.gender == 'M' ? Icons.male : Icons.female,
                theme,
              ),
              _buildInfoCard(
                'Statut',
                widget.student.status,
                Icons.person_pin,
                theme,
              ),
              _buildInfoCard(
                'Adresse',
                widget.student.address,
                Icons.location_on,
                theme,
              ),
            ], theme),

            const SizedBox(height: 24),

            _buildInfoSection('Informations de Contact', [
              _buildInfoCard(
                'Téléphone',
                widget.student.contactNumber,
                Icons.phone,
                theme,
              ),
              _buildInfoCard('Email', widget.student.email, Icons.email, theme),
              _buildInfoCard(
                'Contact d\'urgence',
                widget.student.emergencyContact,
                Icons.emergency,
                theme,
              ),
            ], theme),

            const SizedBox(height: 24),

            _buildInfoSection('Informations Familiales', [
              _buildInfoCard(
                'Nom du Tuteur',
                widget.student.guardianName,
                Icons.person,
                theme,
              ),
              _buildInfoCard(
                'Contact du Tuteur',
                widget.student.guardianContact,
                Icons.phone,
                theme,
              ),
            ], theme),

            const SizedBox(height: 24),

            _buildInfoSection('Informations Académiques', [
              _buildInfoCard(
                'Classe Actuelle',
                widget.student.className,
                Icons.school,
                theme,
              ),
              _buildInfoCard(
                'Année d\'inscription',
                _getEnrollmentYear(),
                Icons.calendar_month,
                theme,
              ),
              if (widget.student.medicalInfo != null &&
                  widget.student.medicalInfo!.isNotEmpty)
                _buildInfoCard(
                  'Informations Médicales',
                  widget.student.medicalInfo!,
                  Icons.medical_services,
                  theme,
                ),
            ], theme),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
    if (dateString.isEmpty) return 'Non renseigné';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateString; // Retourner la chaîne originale si le parsing échoue
    }
  }

  String _calculateAge(String dateString) {
    if (dateString.isEmpty) return 'Non renseigné';
    try {
      final birthDate = DateTime.parse(dateString);
      final now = DateTime.now();
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      return '$age ans';
    } catch (e) {
      return 'Non renseigné';
    }
  }

  String _getEnrollmentYear() {
    // Supposons que l'année d'inscription soit l'année courante ou l'année académique
    final now = DateTime.now();
    return '${now.year}-${now.year + 1}';
  }

  Widget _buildStatusChip(String text, IconData icon, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.secondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> cards, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: cards),
      ],
    );
  }

  Widget _buildInfoCard(
    String label,
    String value,
    IconData icon,
    ThemeData theme,
  ) {
    return Container(
      width: (MediaQuery.of(context).size.width - 72) / 2, // Responsive width
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value.isNotEmpty ? value : 'Non renseigné',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: value.isNotEmpty
                  ? theme.textTheme.bodyMedium?.color
                  : theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsTab() {
    final theme = Theme.of(context);
    if (_payments.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.green.withOpacity(0.02),
              Colors.green.withOpacity(0.05),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.payment_outlined,
                size: 64,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Aucun paiement trouvé',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Les paiements de cet élève apparaîtront ici',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Calculate total paid
    final totalPaid = _payments
        .where((p) => !p.isCancelled)
        .fold(0.0, (sum, item) => sum + item.amount);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.green.withOpacity(0.02),
            Colors.green.withOpacity(0.05),
          ],
        ),
      ),
      child: Column(
        children: [
          // Summary Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withOpacity(0.1),
                  theme.colorScheme.secondary.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total des Paiements',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.7,
                          ),
                        ),
                      ),
                      Text(
                        '${totalPaid.toStringAsFixed(0)} FCFA',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${_payments.where((p) => !p.isCancelled).length} paiements',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Payments List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _payments.length,
              itemBuilder: (context, index) {
                final payment = _payments[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: payment.isCancelled
                          ? Colors.red.withOpacity(0.3)
                          : theme.dividerColor.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: payment.isCancelled
                                    ? Colors.red.withOpacity(0.1)
                                    : theme.colorScheme.primary.withOpacity(
                                        0.1,
                                      ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                payment.isCancelled
                                    ? Icons.cancel
                                    : Icons.receipt_long,
                                color: payment.isCancelled
                                    ? Colors.red
                                    : theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Paiement du ${payment.date.substring(0, 10)}',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${payment.amount} FCFA',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (payment.isCancelled)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.red.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  'Annulé',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (payment.comment != null &&
                            payment.comment!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary.withOpacity(
                                0.05,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.secondary.withOpacity(
                                  0.2,
                                ),
                              ),
                            ),
                            child: Text(
                              'Commentaire: ${payment.comment}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                        ],
                        if (payment.isCancelled &&
                            payment.cancelledAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Annulé le: ${payment.cancelledAt!.substring(0, 10)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                final studentClass = await _dbService
                                    .getClassByName(widget.student.className);
                                if (studentClass != null) {
                                  final allPayments = await _dbService
                                      .getPaymentsForStudent(widget.student.id);
                                  final totalPaid = allPayments
                                      .where((p) => !p.isCancelled)
                                      .fold(
                                        0.0,
                                        (sum, item) => sum + item.amount,
                                      );
                                  final totalDue =
                                      (studentClass.fraisEcole ?? 0) +
                                      (studentClass.fraisCotisationParallele ??
                                          0);
                                  final schoolInfo = await loadSchoolInfo();
                                  final pdfBytes =
                                      await PdfService.generatePaymentReceiptPdf(
                                        currentPayment: payment,
                                        allPayments: allPayments,
                                        student: widget.student,
                                        schoolInfo: schoolInfo,
                                        studentClass: studentClass,
                                        totalPaid: totalPaid,
                                        totalDue: totalDue,
                                      );

                                  String? directoryPath = await FilePicker
                                      .platform
                                      .getDirectoryPath(
                                        dialogTitle:
                                            'Choisir le dossier de sauvegarde',
                                      );
                                  if (directoryPath != null) {
                                    final fileName =
                                        'Recu_Paiement_${widget.student.name.replaceAll(' ', '_')}_${payment.date.substring(0, 10)}.pdf';
                                    final file = File(
                                      '$directoryPath/$fileName',
                                    );
                                    await file.writeAsBytes(pdfBytes);
                                    showRootSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Reçu enregistré dans $directoryPath',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: Icon(Icons.picture_as_pdf, size: 18),
                              label: Text('Télécharger PDF'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCardsTab() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.orange.withOpacity(0.02),
            Colors.orange.withOpacity(0.05),
          ],
        ),
      ),
      child: _reportCards.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 64,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucun bulletin archivé',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(
                        0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Les bulletins archivés de cet élève apparaîtront ici',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(
                        0.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reportCards.length,
              itemBuilder: (context, index) {
                final reportCard = _reportCards[index];
                // Decode moyennes_par_periode and all_terms from JSON string
                final List<double?> moyennesParPeriode =
                    (reportCard['moyennes_par_periode'] as String)
                        .replaceAll('[', '')
                        .replaceAll(']', '')
                        .split(',')
                        .map((e) => double.tryParse(e.trim()))
                        .toList();
                final List<String> allTerms =
                    (reportCard['all_terms'] as String)
                        .replaceAll('[', '')
                        .replaceAll(']', '')
                        .split(',')
                        .map((e) => e.trim())
                        .toList();

                final moyenneGenerale =
                    reportCard['moyenne_generale']?.toDouble() ?? 0.0;
                final mention = reportCard['mention'] ?? '';

                // Determine color based on grade
                Color gradeColor = Colors.grey;
                if (moyenneGenerale >= 16) {
                  gradeColor = Colors.green;
                } else if (moyenneGenerale >= 14) {
                  gradeColor = Colors.blue;
                } else if (moyenneGenerale >= 12) {
                  gradeColor = Colors.orange;
                } else if (moyenneGenerale >= 10) {
                  gradeColor = Colors.red;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: gradeColor.withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // En-tête administratif (snapshot depuis l'archive)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((reportCard['school_ministry'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      (reportCard['school_ministry'] as String)
                                          .toUpperCase(),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  if ((reportCard['school_inspection'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      'Inspection: ${reportCard['school_inspection']}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    ((reportCard['school_republic'] ??
                                                'RÉPUBLIQUE')
                                            as String)
                                        .toUpperCase(),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if ((reportCard['school_republic_motto'] ??
                                          '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      reportCard['school_republic_motto'],
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                  if ((reportCard['school_education_direction'] ??
                                          '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      "Direction de l'enseignement: ${reportCard['school_education_direction']}",
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Bloc élève snapshot
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Nom: ${widget.student.name}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Date de naissance: ${_fmtArchivedDate(reportCard['student_dob'])}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Statut: ${reportCard['student_status'] ?? ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (((reportCard['student_photo_path'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty) &&
                            File(
                              (reportCard['student_photo_path'] as String),
                            ).existsSync())
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.dividerColor.withOpacity(0.3),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.file(
                                File(
                                  reportCard['student_photo_path'] as String,
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: gradeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.school,
                                color: gradeColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bulletin ${reportCard['term']} - ${reportCard['academicYear']}',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color:
                                              theme.textTheme.bodyLarge?.color,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Classe: ${reportCard['className']}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.textTheme.bodyMedium?.color
                                          ?.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: gradeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: gradeColor.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                mention.isNotEmpty ? mention : 'Sans mention',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: gradeColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (((reportCard['exaequo'] is int) &&
                                    (reportCard['exaequo'] as int) == 1) ||
                                reportCard['exaequo'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.amber.withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  'ex æquo',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.amber.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Grade Summary (fallback compute if archive values are 0)
                        FutureBuilder<Map<String, dynamic>>(
                          future: () async {
                            num avg =
                                (reportCard['moyenne_generale'] as num?) ?? 0;
                            num rank = (reportCard['rang'] as num?) ?? 0;
                            num nb = (reportCard['nb_eleves'] as num?) ?? 0;
                            bool isExAequo = (reportCard['exaequo'] is int)
                                ? (reportCard['exaequo'] as int) == 1
                                : (reportCard['exaequo'] == true);
                            // Fallback: use stored per-period averages if available
                            if (avg == 0) {
                              try {
                                final term =
                                    reportCard['term'] as String? ?? '';
                                final all = allTerms;
                                final idx = all.indexOf(term);
                                if (idx >= 0 &&
                                    idx < moyennesParPeriode.length &&
                                    moyennesParPeriode[idx] != null) {
                                  avg = (moyennesParPeriode[idx] as double);
                                }
                              } catch (_) {}
                            }
                            // Fallback: compute rank/nb from archived grades for this class/year/term
                            if (rank == 0 ||
                                nb == 0 ||
                                avg == 0 ||
                                !isExAequo) {
                              try {
                                final archived = await _dbService
                                    .getArchivedGrades(
                                      academicYear: reportCard['academicYear'],
                                      className: reportCard['className'],
                                    );
                                final term =
                                    (reportCard['term'] as String?) ?? '';
                                // group by student for the same term
                                final Map<String, Map<String, double>> sums =
                                    {};
                                for (final g in archived.where(
                                  (g) => g.term == term,
                                )) {
                                  final s = sums.putIfAbsent(
                                    g.studentId,
                                    () => {'n': 0.0, 'c': 0.0},
                                  );
                                  if (g.maxValue > 0 && g.coefficient > 0) {
                                    s['n'] =
                                        (s['n'] ?? 0) +
                                        ((g.value / g.maxValue) * 20) *
                                            g.coefficient;
                                    s['c'] = (s['c'] ?? 0) + g.coefficient;
                                  }
                                }
                                final List<MapEntry<String, double>> avgs = sums
                                    .entries
                                    .map(
                                      (e) => MapEntry(
                                        e.key,
                                        (e.value['c'] ?? 0) > 0
                                            ? (e.value['n']! / e.value['c']!)
                                            : 0.0,
                                      ),
                                    )
                                    .toList();
                                avgs.sort((a, b) => b.value.compareTo(a.value));
                                nb = avgs.length;
                                final sid = reportCard['studentId'] as String?;
                                final self = avgs.firstWhere(
                                  (e) => e.key == sid,
                                  orElse: () => const MapEntry('', 0.0),
                                );
                                final double myAvg = self.value;
                                const double eps = 0.001;
                                // Rang ex æquo: 1 + nombre d'élèves avec une moyenne strictement supérieure
                                rank =
                                    1 +
                                    avgs
                                        .where((e) => (e.value - myAvg) > eps)
                                        .length;
                                // Ex æquo si d'autres élèves ont la même moyenne (tolérance eps)
                                isExAequo =
                                    avgs
                                        .where(
                                          (e) => (e.value - myAvg).abs() < eps,
                                        )
                                        .length >
                                    1;
                                if (avg == 0 && myAvg > 0) avg = myAvg;
                              } catch (_) {}
                            }
                            return {
                              'avg': avg,
                              'rank': rank,
                              'nb': nb,
                              'exaequo': isExAequo,
                            };
                          }(),
                          builder: (context, snap) {
                            final num avg =
                                snap.data?['avg'] ??
                                (reportCard['moyenne_generale'] as num? ?? 0);
                            final num rank =
                                snap.data?['rank'] ??
                                (reportCard['rang'] as num? ?? 0);
                            final num nb =
                                snap.data?['nb'] ??
                                (reportCard['nb_eleves'] as num? ?? 0);
                            final bool exaequo =
                                (snap.data?['exaequo'] as bool?) ??
                                ((reportCard['exaequo'] is int)
                                    ? (reportCard['exaequo'] as int) == 1
                                    : (reportCard['exaequo'] == true));
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    gradeColor.withOpacity(0.1),
                                    gradeColor.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: gradeColor.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          'Moyenne Générale',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                                    ?.withOpacity(0.7),
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          avg.toStringAsFixed(2),
                                          style: theme.textTheme.headlineMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: gradeColor,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 40,
                                    color: gradeColor.withOpacity(0.3),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          'Rang',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                                    ?.withOpacity(0.7),
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          exaequo
                                              ? '${rank.toInt()} (ex æquo) / ${nb.toInt()}'
                                              : '${rank.toInt()} / ${nb.toInt()}',
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: theme
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // Statistics Grid
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildStatCard(
                              'Moyenne Classe',
                              '${reportCard['moyenne_generale_classe']?.toStringAsFixed(2) ?? '-'}',
                              Icons.group,
                              theme,
                            ),
                            _buildStatCard(
                              'Plus Forte',
                              '${reportCard['moyenne_la_plus_forte']?.toStringAsFixed(2) ?? '-'}',
                              Icons.trending_up,
                              theme,
                            ),
                            _buildStatCard(
                              'Plus Faible',
                              '${reportCard['moyenne_la_plus_faible']?.toStringAsFixed(2) ?? '-'}',
                              Icons.trending_down,
                              theme,
                            ),
                            _buildStatCard(
                              'Moyenne Annuelle',
                              '${reportCard['moyenne_annuelle']?.toStringAsFixed(2) ?? '-'}',
                              Icons.calendar_today,
                              theme,
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Download Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                final info = await loadSchoolInfo();
                                final studentClass = await _dbService
                                    .getClassByName(widget.student.className);
                                if (studentClass == null) return;

                                // Fetch grades and appreciations for this specific archived report card
                                final archivedGrades = await _dbService
                                    .getArchivedGrades(
                                      academicYear: reportCard['academicYear'],
                                      className: reportCard['className'],
                                      studentId: reportCard['studentId'],
                                    );

                                final subjectApps = await _dbService.database
                                    .then(
                                      (db) => db.query(
                                        'subject_appreciation_archive',
                                        where: 'report_card_id = ?',
                                        whereArgs: [reportCard['id']],
                                      ),
                                    );

                                final Map<String, String> professeurs = {};
                                final Map<String, String> appreciations = {};
                                final Map<String, String> moyennesClasse = {};

                                for (final app in subjectApps) {
                                  professeurs[app['subject'] as String] =
                                      (app['professeur'] ?? '-').toString();
                                  appreciations[app['subject'] as String] =
                                      (app['appreciation'] ?? '-').toString();
                                  moyennesClasse[app['subject'] as String] =
                                      (app['moyenne_classe'] ?? '-').toString();
                                }

                                // Détermine si l'élève est ex æquo (préfère la valeur archivée si disponible)
                                bool isExAequo = (reportCard['exaequo'] is int)
                                    ? (reportCard['exaequo'] as int) == 1
                                    : (reportCard['exaequo'] == true);
                                try {
                                  if (!isExAequo) {
                                    final allArchived = await _dbService
                                        .getArchivedGrades(
                                          academicYear:
                                              reportCard['academicYear'],
                                          className: reportCard['className'],
                                        );
                                    final term =
                                        (reportCard['term'] as String?) ?? '';
                                    final Map<String, Map<String, double>>
                                    sums = {};
                                    for (final g in allArchived.where(
                                      (g) => g.term == term,
                                    )) {
                                      final s = sums.putIfAbsent(
                                        g.studentId,
                                        () => {'n': 0.0, 'c': 0.0},
                                      );
                                      if (g.maxValue > 0 && g.coefficient > 0) {
                                        s['n'] =
                                            (s['n'] ?? 0) +
                                            ((g.value / g.maxValue) * 20) *
                                                g.coefficient;
                                        s['c'] = (s['c'] ?? 0) + g.coefficient;
                                      }
                                    }
                                    final List<double> avgs = sums.entries
                                        .map(
                                          (e) => (e.value['c'] ?? 0) > 0
                                              ? (e.value['n']! / e.value['c']!)
                                              : 0.0,
                                        )
                                        .toList();
                                    final double myAvg =
                                        reportCard['moyenne_generale']
                                            ?.toDouble() ??
                                        0.0;
                                    const double eps = 0.001;
                                    final int ties = avgs
                                        .where((m) => (m - myAvg).abs() < eps)
                                        .length;
                                    isExAequo = ties > 1;
                                  }
                                } catch (_) {}

                                final pdfBytes = await PdfService.generateReportCardPdf(
                                  student: widget.student,
                                  schoolInfo: info,
                                  grades: archivedGrades,
                                  professeurs: professeurs,
                                  appreciations: appreciations,
                                  moyennesClasse: moyennesClasse,
                                  appreciationGenerale:
                                      reportCard['appreciation_generale'] ?? '',
                                  decision: reportCard['decision'] ?? '',
                                  recommandations:
                                      reportCard['recommandations'] ?? '',
                                  forces: reportCard['forces'] ?? '',
                                  pointsADevelopper:
                                      reportCard['points_a_developper'] ?? '',
                                  sanctions: reportCard['sanctions'] ?? '',
                                  attendanceJustifiee:
                                      (reportCard['attendance_justifiee'] ?? 0)
                                          as int,
                                  attendanceInjustifiee:
                                      (reportCard['attendance_injustifiee'] ??
                                              0)
                                          as int,
                                  retards: (reportCard['retards'] ?? 0) as int,
                                  presencePercent:
                                      (reportCard['presence_percent'] ?? 0.0)
                                          is int
                                      ? (reportCard['presence_percent'] as int)
                                            .toDouble()
                                      : (reportCard['presence_percent'] ?? 0.0)
                                            as double,
                                  conduite: reportCard['conduite'] ?? '',
                                  telEtab: info.telephone ?? '',
                                  mailEtab: info.email ?? '',
                                  webEtab: info.website ?? '',
                                  titulaire: studentClass.titulaire ?? '',
                                  subjects: archivedGrades
                                      .map((e) => e.subject)
                                      .toSet()
                                      .toList(), // Extract subjects from grades
                                  moyennesParPeriode: moyennesParPeriode,
                                  moyenneGenerale:
                                      reportCard['moyenne_generale']
                                          ?.toDouble() ??
                                      0.0,
                                  rang: reportCard['rang'] ?? 0,
                                  exaequo: isExAequo,
                                  nbEleves: reportCard['nb_eleves'] ?? 0,
                                  mention: reportCard['mention'] ?? '',
                                  allTerms: allTerms,
                                  periodLabel:
                                      reportCard['term']?.toString().contains(
                                            'Semestre',
                                          ) ==
                                          true
                                      ? 'Semestre'
                                      : 'Trimestre',
                                  selectedTerm: reportCard['term'] ?? '',
                                  academicYear:
                                      reportCard['academicYear'] ?? '',
                                  faitA: reportCard['fait_a'] ?? '',
                                  leDate: reportCard['le_date'] ?? '',
                                  isLandscape:
                                      false, // You might want to store this in the archive or make it selectable
                                  niveau:
                                      '', // You might want to store this in the archive or fetch it
                                  moyenneGeneraleDeLaClasse:
                                      reportCard['moyenne_generale_classe']
                                          ?.toDouble() ??
                                      0.0,
                                  moyenneLaPlusForte:
                                      reportCard['moyenne_la_plus_forte']
                                          ?.toDouble() ??
                                      0.0,
                                  moyenneLaPlusFaible:
                                      reportCard['moyenne_la_plus_faible']
                                          ?.toDouble() ??
                                      0.0,
                                  moyenneAnnuelle:
                                      reportCard['moyenne_annuelle']
                                          ?.toDouble() ??
                                      0.0,
                                  duplicata: true,
                                );

                                String? directoryPath = await FilePicker
                                    .platform
                                    .getDirectoryPath(
                                      dialogTitle:
                                          'Choisir le dossier de sauvegarde',
                                    );
                                if (directoryPath != null) {
                                  final fileName =
                                      'Bulletin_${widget.student.name.replaceAll(' ', '_')}_${reportCard['term'] ?? ''}_${reportCard['academicYear'] ?? ''}.pdf';
                                  final file = File('$directoryPath/$fileName');
                                  await file.writeAsBytes(pdfBytes);
                                  showRootSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Bulletin enregistré dans $directoryPath',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  try {
                                    final u = await AuthService.instance.getCurrentUser();
                                    await _dbService.logAudit(
                                      category: 'report_card',
                                      action: 'export_report_card_pdf',
                                      username: u?.username,
                                      details:
                                          'student=${widget.student.id} class=${reportCard['className'] ?? ''} year=${reportCard['academicYear'] ?? ''} term=${reportCard['term'] ?? ''} file=$fileName',
                                    );
                                  } catch (_) {}
                                }
                              },
                              icon: Icon(Icons.picture_as_pdf, size: 18),
                              label: Text('Télécharger PDF'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    ThemeData theme,
  ) {
    return Container(
      width: (MediaQuery.of(context).size.width - 100) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
