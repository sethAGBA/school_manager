import 'package:flutter/material.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/utils/academic_year.dart';

import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class FinanceAndInventoryPage extends StatefulWidget {
  const FinanceAndInventoryPage({super.key});

  @override
  State<FinanceAndInventoryPage> createState() => _FinanceAndInventoryPageState();
}

class _FinanceAndInventoryPageState extends State<FinanceAndInventoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final DatabaseService _db = DatabaseService();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Class> _classes = [];
  List<String> _years = [];
  String? _selectedClassFilter;
  String? _selectedYearFilter;

  bool _loading = true;
  String _year = '';
  double _totalPayments = 0.0;


  Future<List<Payment>> _loadFilteredPayments() async {
    final payments = await _db.getAllPayments();
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();
    return payments.where((p) =>
      p.classAcademicYear == selectedYear &&
      (_selectedClassFilter == null || _selectedClassFilter!.isEmpty || p.className == _selectedClassFilter)
    ).toList();
  }

  Future<void> _exportFinanceToExcel() async {
    final payments = await _loadFilteredPayments();
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final excel = Excel.createExcel();
    final sheet = excel['Finances'];
    sheet.appendRow([
      TextCellValue('Année'),
      TextCellValue('Classe'),
      TextCellValue('Étudiant ID'),
      TextCellValue('Date'),
      TextCellValue('Montant'),
      TextCellValue('Commentaire'),
    ]);
    for (final p in payments) {
      sheet.appendRow([
        TextCellValue(p.classAcademicYear),
        TextCellValue(p.className),
        TextCellValue(p.studentId),
        TextCellValue(p.date),
        TextCellValue(p.amount.toStringAsFixed(2)),
        TextCellValue(p.comment ?? ''),
      ]);
    }
    final fileName = 'finances_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.xlsx';
    final bytes = excel.encode();
    if (bytes != null) {
      final file = File('$directory/$fileName');
      await file.writeAsBytes(bytes);
      OpenFile.open(file.path);
    }
  }

  Future<void> _exportFinanceToPdf() async {
    final payments = await _loadFilteredPayments();
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final pdf = pw.Document();
    final title = 'Rapport Financier - Année ${_selectedYearFilter ?? _year}${_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty ? ' - Classe ' + _selectedClassFilter! : ''}';
    final total = payments.fold<double>(0.0, (sum, p) => sum + p.amount);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Total: ' + total.toStringAsFixed(2) + ' FCFA', style: pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Date', style: pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Classe', style: pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Élève (ID)', style: pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Montant', style: pw.TextStyle(fontSize: 10))),
                    ],
                  ),
                  ...payments.map((p) => pw.TableRow(children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p.date, style: const pw.TextStyle(fontSize: 10))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p.className, style: const pw.TextStyle(fontSize: 10))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p.studentId, style: const pw.TextStyle(fontSize: 10))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(p.amount.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10))),
                      ]))
                ],
              )
            ],
          );
        },
      ),
    );
    final fileName = 'finances_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(await pdf.save());
    OpenFile.open(file.path);
  }

  Future<void> _exportInventoryToExcel() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final excel = Excel.createExcel();
    final sheet = excel['Inventaire'];
    sheet.appendRow([
      TextCellValue('Catégorie'),
      TextCellValue('Article'),
      TextCellValue('Quantité'),
      TextCellValue('Localisation'),
      TextCellValue('État'),
      TextCellValue('Valeur'),
    ]);
    // Placeholder: no data yet
    final fileName = 'inventaire_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.xlsx';
    final bytes = excel.encode();
    if (bytes != null) {
      final file = File('$directory/$fileName');
      await file.writeAsBytes(bytes);
      OpenFile.open(file.path);
    }
  }

  Future<void> _exportInventoryToPdf() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final pdf = pw.Document();
    final title = 'Inventaire - Année ${_selectedYearFilter ?? _year}${_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty ? ' - Classe ' + _selectedClassFilter! : ''}';
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Aucune donnée d\'inventaire disponible.'),
          ],
        ),
      ),
    );
    final fileName = 'inventaire_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(await pdf.save());
    OpenFile.open(file.path);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final currentYear = await getCurrentAcademicYear();
    final payments = await _db.getAllPayments();
    final classes = await _db.getClasses();

    // Build year list
    final yearSet = <String>{};
    for (final c in classes) {
      if (c.academicYear.isNotEmpty) yearSet.add(c.academicYear);
    }
    final yearList = yearSet.toList()..sort();

    final selectedYear = _selectedYearFilter ?? currentYear;
    double sum = 0.0;
    for (final Payment p in payments) {
      if (p.classAcademicYear != selectedYear) continue;
      if (_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty) {
        if (p.className != _selectedClassFilter) continue;
      }
      sum += p.amount;
    }
    if (!mounted) return;
    setState(() {
      _classes = classes.where((c) => c.academicYear == selectedYear).toList();
      _years = yearList;
      _selectedYearFilter = selectedYear;
      _year = selectedYear;
      _totalPayments = sum;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
            // Header (like Payments)
            _buildHeaderFinance(context, isDesktop),
            const SizedBox(height: 16),
            // Tabs placed BELOW the header
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: theme.cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withOpacity(0.1),
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
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.3),
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
                    Tab(icon: Icon(Icons.payments), text: 'Finances'),
                    Tab(icon: Icon(Icons.inventory_2), text: 'Matériel'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Tab contents
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFinanceTab(context),
                  _buildInventoryTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildHeaderFinance(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.payment_rounded, color: Colors.white, size: isDesktop ? 32 : 24),
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Gestion Financière & Matériel',
                    style: TextStyle(
                      fontSize: isDesktop ? 32 : 24,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Suivez les encaissements, préparez des rapports et gérez l\'inventaire.',
                    style: TextStyle(
                      fontSize: isDesktop ? 16 : 14,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      height: 1.5,
                    ),
                  ),
                ]),
              ]),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: Icon(Icons.notifications_outlined, color: theme.iconTheme.color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Rechercher (à venir)',
              hintStyle: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6)),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ],
      ),
    );
  }
  Widget _buildFinanceFilters(BuildContext context) {
    final theme = Theme.of(context);
    final classNames = _classes.map((c) => c.name).toList()..sort();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
        ),
        child: Row(
          children: [
            // Year filter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: DropdownButton<String?>(
                value: _selectedYearFilter,
                hint: Text('Année', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                items: [for (final y in _years) DropdownMenuItem<String?>(value: y, child: Text(y))],
                onChanged: (v) => setState(() { _selectedYearFilter = v; _selectedClassFilter = null; _loadData(); }),
                underline: const SizedBox.shrink(),
                dropdownColor: theme.cardColor,
                iconEnabledColor: theme.iconTheme.color,
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
            const SizedBox(width: 8),
            // Class filter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: DropdownButton<String?>(
                value: _selectedClassFilter,
                hint: Text('Classe', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Toutes')),
                  for (final name in classNames) DropdownMenuItem<String?>(value: name, child: Text(name)),
                ],
                onChanged: (v) => setState(() { _selectedClassFilter = v; _loadData(); }),
                underline: const SizedBox.shrink(),
                dropdownColor: theme.cardColor,
                iconEnabledColor: theme.iconTheme.color,
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildInventoryFilters(BuildContext context) {
    final theme = Theme.of(context);
    final classNames = _classes.map((c) => c.name).toList()..sort();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
        ),
        child: Row(
          children: [
            // Year filter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: DropdownButton<String?>(
                value: _selectedYearFilter,
                hint: Text('Année', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                items: [for (final y in _years) DropdownMenuItem<String?>(value: y, child: Text(y))],
                onChanged: (v) => setState(() { _selectedYearFilter = v; _selectedClassFilter = null; _loadData(); }),
                underline: const SizedBox.shrink(),
                dropdownColor: theme.cardColor,
                iconEnabledColor: theme.iconTheme.color,
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
            const SizedBox(width: 8),
            // Class filter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: DropdownButton<String?>(
                value: _selectedClassFilter,
                hint: Text('Classe', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Toutes')),
                  for (final name in classNames) DropdownMenuItem<String?>(value: name, child: Text(name)),
                ],
                onChanged: (v) => setState(() { _selectedClassFilter = v; _loadData(); }),
                underline: const SizedBox.shrink(),
                dropdownColor: theme.cardColor,
                iconEnabledColor: theme.iconTheme.color,
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildFinanceTab(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: _infoCard(context,
                      title: 'Total paiements (' + (_year.isEmpty ? '-' : _year) + ')',
                      value: _loading ? '...' : _formatCurrency(_totalPayments),
                      color: const Color(0xFF22C55E))),
                  const SizedBox(width: 12),
                  Expanded(child: _infoCard(context,
                      title: 'Dépenses (' + (_year.isEmpty ? '-' : _year) + ')',
                      value: _formatCurrency(0),
                      color: const Color(0xFFEF4444))),
                  const SizedBox(width: 12),
                  Expanded(child: _infoCard(context,
                      title: 'Solde net',
                      value: _loading ? '...' : _formatCurrency(_totalPayments - 0),
                      color: const Color(0xFF3B82F6))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildFinanceFilters(context),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInventoryTab(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInventoryFilters(context),
        const SizedBox(height: 16),
        Card(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gestion du matériel (inventaire)', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Aucun inventaire stocké pour l\'instant.'
                  'Je peux ajouter une table "inventory_items" (id, nom, catégorie, quantité, localisation, état, valeur, fournisseur, date) et les vues associées si vous le souhaitez.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.add_box),
                      label: const Text('Ajouter un article (à venir)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.import_export),
                      label: const Text('Importer/Exporter (à venir)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoCard(BuildContext context,
      {required String title, required String value, required Color color}) {
    final theme = Theme.of(context);
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double v) {
    return '${v.toStringAsFixed(0)} FCFA';
  }
}
