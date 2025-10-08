import 'package:flutter/material.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/models/inventory_item.dart';
import 'package:school_manager/models/expense.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/screens/students/widgets/form_field.dart';

import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:school_manager/screens/dashboard_home.dart';
import 'package:intl/intl.dart';

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
  String? _selectedGenderFilter;
  Map<String, Student> _studentsById = {};

  bool _loading = true;
  String _year = '';
  double _totalPayments = 0.0;
  double _totalExpenses = 0.0;
  List<InventoryItem> _inventoryItems = [];
  // Expenses state
  List<Expense> _expenses = [];
  String? _selectedExpenseCategory;
  String? _selectedExpenseSupplier;
  List<String> _expenseCategories = [];
  List<String> _expenseSuppliers = [];
  String? _selectedInvCategory;
  String? _selectedInvCondition;
  String? _selectedInvLocation;
  double _inventoryTotalValue = 0.0;
  List<String> _inventoryCategories = [];
  List<String> _inventoryConditions = [];
  List<String> _inventoryLocations = [];
  
  


  Future<List<Payment>> _loadFilteredPayments() async {
    final payments = await _db.getAllPayments();
    // Load students map if gender filter is used
    if (_selectedGenderFilter != null && _studentsById.isEmpty) {
      final sts = await _db.getStudents();
      _studentsById = {for (final s in sts) s.id: s};
    }
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();
    return payments.where((p) {
      if (p.classAcademicYear != selectedYear) return false;
      if (_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty) {
        if (p.className != _selectedClassFilter) return false;
      }
      if (_selectedGenderFilter != null) {
        final st = _studentsById[p.studentId];
        if (st == null || st.gender != _selectedGenderFilter) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportFinanceToExcel() async {
    final payments = await _loadFilteredPayments();
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();
    final expenses = await _db.getExpenses(
      className: _selectedClassFilter,
      academicYear: selectedYear,
      supplier: _selectedExpenseSupplier,
      category: _selectedExpenseCategory,
    );
    // Build student name map for display
    final students = await _db.getStudents();
    final Map<String, String> studentNames = {
      for (final s in students) s.id: s.name,
    };
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final excel = Excel.createExcel();
    final encSheet = excel['Encaissements'];
    encSheet.appendRow([
      TextCellValue('Année'),
      TextCellValue('Classe'),
      TextCellValue('Élève'),
      TextCellValue('Date'),
      TextCellValue('Montant'),
      TextCellValue('Commentaire'),
    ]);
    double totalEnc = 0.0;
    for (final p in payments) {
      totalEnc += p.amount;
      encSheet.appendRow([
        TextCellValue(p.classAcademicYear),
        TextCellValue(p.className),
        TextCellValue(studentNames[p.studentId] ?? p.studentId),
        TextCellValue(p.date.replaceFirst('T', ' ').substring(0, 16)),
        DoubleCellValue(p.amount),
        TextCellValue(p.comment ?? ''),
      ]);
    }
    // Totaux encaissements
    encSheet.appendRow([
       TextCellValue(''),
       TextCellValue(''),
       TextCellValue(''),
       TextCellValue('TOTAL'),
      DoubleCellValue(totalEnc),
       TextCellValue(''),
    ]);
    final depSheet = excel['Depenses'];
    depSheet.appendRow([
      TextCellValue('Année'),
      TextCellValue('Classe'),
      TextCellValue('Date'),
      TextCellValue('Libellé'),
      TextCellValue('Catégorie'),
      TextCellValue('Fournisseur'),
      TextCellValue('Montant'),
    ]);
    double totalDep = 0.0;
    for (final e in expenses) {
      totalDep += e.amount;
      depSheet.appendRow([
        TextCellValue(e.academicYear),
        TextCellValue(e.className ?? ''),
        TextCellValue(e.date.replaceFirst('T', ' ').substring(0, 16)),
        TextCellValue(e.label),
        TextCellValue(e.category ?? ''),
        TextCellValue(e.supplier ?? ''),
        DoubleCellValue(e.amount),
      ]);
    }
    // Totaux dépenses
    depSheet.appendRow([
       TextCellValue(''),
       TextCellValue(''),
       TextCellValue(''),
       TextCellValue(''),
       TextCellValue(''),
       TextCellValue('TOTAL'),
      DoubleCellValue(totalDep),
    ]);

    // Feuille Résumé
    final resume = excel['Résumé'];
    resume.appendRow([TextCellValue('Filtre Année'), TextCellValue(selectedYear)]);
    resume.appendRow([
      TextCellValue('Filtre Classe'),
      TextCellValue(_selectedClassFilter ?? '(Toutes)'),
    ]);
    resume.appendRow([TextCellValue('Total Encaissements'), DoubleCellValue(totalEnc)]);
    resume.appendRow([TextCellValue('Total Dépenses'), DoubleCellValue(totalDep)]);
    resume.appendRow([
      TextCellValue('Solde Net'),
      DoubleCellValue(totalEnc - totalDep),
    ]);
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
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();
    final expenses = await _db.getExpenses(
      className: _selectedClassFilter,
      academicYear: selectedYear,
      supplier: _selectedExpenseSupplier,
      category: _selectedExpenseCategory,
    );
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final pdf = pw.Document();
    final title = 'Rapport Financier - Année ${_selectedYearFilter ?? _year}${_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty ? ' - Classe ' + _selectedClassFilter! : ''}';
    final formatter = NumberFormat('#,##0 FCFA', 'fr_FR');
    final total = payments.fold<double>(0.0, (sum, p) => sum + p.amount);
    final depTotal = expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    // Student names for display
    final students = await _db.getStudents();
    final Map<String, String> studentNames = {
      for (final s in students) s.id: s.name,
    };
    // Load school info and fonts for consistent design
    final schoolInfo = await _db.getSchoolInfo();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) {
          return pw.Stack(children: [
            // Watermark
            if (schoolInfo?.logoPath != null && File(schoolInfo!.logoPath!).existsSync())
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.06,
                    child: pw.Image(
                      pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                      width: 400,
                    ),
                  ),
                ),
              ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // En-tête administratif (Ministère, République, etc.) pour harmonisation
                if (schoolInfo != null) ...[
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: ((schoolInfo!.ministry ?? '').isNotEmpty)
                            ? pw.Text(
                                (schoolInfo!.ministry ?? '').toUpperCase(),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              ((schoolInfo!.republic ?? 'RÉPUBLIQUE').toUpperCase()),
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 10,
                                color: primary,
                              ),
                            ),
                            if ((schoolInfo!.republicMotto ?? '').isNotEmpty)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Text(
                                  schoolInfo!.republicMotto!,
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 9,
                                    color: primary,
                                    fontStyle: pw.FontStyle.italic,
                                  ),
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: ((schoolInfo!.inspection ?? '').isNotEmpty)
                            ? pw.Text(
                                'Inspection: ${schoolInfo!.inspection}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 9,
                                  color: primary,
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: ((schoolInfo!.educationDirection ?? '').isNotEmpty)
                              ? pw.Text(
                                  "Direction de l'enseignement: ${schoolInfo!.educationDirection}",
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 9,
                                    color: primary,
                                  ),
                                )
                              : pw.SizedBox(),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                ],
                // Header with logo and school info
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: light,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: accent, width: 1),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (schoolInfo?.logoPath != null && File(schoolInfo!.logoPath!).existsSync())
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 16),
                          child: pw.Image(
                            pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                            width: 60,
                            height: 60,
                          ),
                        ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              schoolInfo?.name ?? 'Établissement',
                              style: pw.TextStyle(font: timesBold, fontSize: 16, color: accent),
                            ),
                            if ((schoolInfo?.address ?? '').isNotEmpty)
                              pw.Text(
                                schoolInfo!.address,
                                style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                              ),
                            if ((schoolInfo?.email ?? '').isNotEmpty)
                              pw.Text(
                                'Email : ${schoolInfo!.email}',
                                style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                              ),
                            if ((schoolInfo?.telephone ?? '').isNotEmpty)
                              pw.Text(
                                'Téléphone : ${schoolInfo!.telephone}',
                                style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                              ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'Année académique: $selectedYear  -  Généré le: $now',
                              style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                // Title bar
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(6)),
                  child: pw.Text(title, style: pw.TextStyle(font: timesBold, fontSize: 16, color: PdfColors.white)),
                ),
                pw.SizedBox(height: 10),
                // Summary row
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Column(children: [
                        pw.Text('Encaissements', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Text(formatter.format(total), style: pw.TextStyle(font: timesBold, fontSize: 12)),
                      ]),
                      pw.Column(children: [
                        pw.Text('Dépenses', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Text(formatter.format(depTotal), style: pw.TextStyle(font: timesBold, fontSize: 12)),
                      ]),
                      pw.Column(children: [
                        pw.Text('Solde net', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          formatter.format(total - depTotal),
                          style: pw.TextStyle(font: timesBold, fontSize: 12, color: (total - depTotal) >= 0 ? PdfColors.green800 : PdfColors.red800),
                        ),
                      ]),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(3),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(4)),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Date', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Classe', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Élève', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Montant', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Commentaire', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                    ],
                  ),
                  ...payments.map((p) => pw.TableRow(children: [
                        _pdfCell(DateFormat('dd/MM/yyyy').format(DateTime.parse(p.date))),
                        _pdfCell(p.className),
                        _pdfCell(studentNames[p.studentId] ?? p.studentId),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(formatter.format(p.amount), style: const pw.TextStyle(fontSize: 10)),
                          ),
                        ),
                        _pdfCell(p.comment ?? ''),
                      ])),
                  // Total row
                  pw.TableRow(children: [
                    _pdfCell(''),
                    _pdfCell(''),
                    _pdfCell('TOTAL'),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          formatter.format(total),
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ),
                    _pdfCell(''),
                  ]),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Text('Dépenses', style: pw.TextStyle(font: timesBold, fontSize: 14, color: PdfColors.white)),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(3),
                  4: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(4)),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Date', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Libellé', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Catégorie', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Fournisseur', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Montant', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                    ],
                  ),
                  ...expenses.map((e) => pw.TableRow(children: [
                        _pdfCell(DateFormat('dd/MM/yyyy').format(DateTime.parse(e.date))),
                        _pdfCell(e.label),
                        _pdfCell(e.category ?? ''),
                        _pdfCell(e.supplier ?? ''),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(formatter.format(e.amount), style: const pw.TextStyle(fontSize: 10)),
                          ),
                        ),
                      ])),
                  // Total row
                  pw.TableRow(children: [
                    _pdfCell(''),
                    _pdfCell(''),
                    _pdfCell(''),
                    _pdfCell('TOTAL'),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          formatter.format(depTotal),
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ),
                  ]),
                ],
              )
            ],
            )
          ]);
        },
      ),
    );
    final fileName = 'finances_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(await pdf.save());
    OpenFile.open(file.path);
  }

  Future<void> _exportInventoryToExcel() async {
    // ensure items are loaded with current filters
    await _loadInventoryItems();
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
      TextCellValue('Classe'),
      TextCellValue('Année'),
    ]);
    double totalVal = 0.0;
    double totalQty = 0.0;
    for (final it in _inventoryItems) {
      totalVal += (it.value ?? 0.0);
      totalQty += (it.quantity.toDouble());
      sheet.appendRow([
        TextCellValue(it.category),
        TextCellValue(it.name),
        DoubleCellValue(it.quantity.toDouble()),
        TextCellValue(it.location ?? ''),
        TextCellValue(it.itemCondition ?? ''),
        it.value != null ? DoubleCellValue(it.value!) :  TextCellValue(''),
        TextCellValue(it.className ?? ''),
        TextCellValue(it.academicYear),
      ]);
    }
    // Totaux
    sheet.appendRow([
       TextCellValue(''),
       TextCellValue('TOTALS'),
      DoubleCellValue(totalQty),
       TextCellValue(''),
       TextCellValue(''),
      DoubleCellValue(totalVal),
       TextCellValue(''),
       TextCellValue(''),
    ]);
    final fileName = 'inventaire_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.xlsx';
    final bytes = excel.encode();
    if (bytes != null) {
      final file = File('$directory/$fileName');
      await file.writeAsBytes(bytes);
      OpenFile.open(file.path);
    }
  }

  Future<void> _exportInventoryToPdf() async {
    await _loadInventoryItems();
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final pdf = pw.Document();
    final title = 'Inventaire - Année ${_selectedYearFilter ?? _year}${_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty ? ' - Classe ' + _selectedClassFilter! : ''}';
    final formatter = NumberFormat('#,##0 FCFA', 'fr_FR');
    final totalVal = _inventoryItems.fold<double>(0.0, (sum, it) => sum + (it.value ?? 0.0));
    final totalQty = _inventoryItems.fold<double>(0.0, (sum, it) => sum + it.quantity.toDouble());
    // Load school info and fonts
    final schoolInfo = await _db.getSchoolInfo();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) {
          return pw.Stack(children: [
            if (schoolInfo?.logoPath != null && File(schoolInfo!.logoPath!).existsSync())
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.06,
                    child: pw.Image(
                      pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                      width: 400,
                    ),
                  ),
                ),
              ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // En-tête administratif (Ministère, République, etc.) pour harmonisation
                if (schoolInfo != null) ...[
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: ((schoolInfo!.ministry ?? '').isNotEmpty)
                            ? pw.Text(
                                (schoolInfo!.ministry ?? '').toUpperCase(),
                                style: pw.TextStyle(
                                  font: timesBold,
                                  fontSize: 10,
                                  color: primary,
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              ((schoolInfo!.republic ?? 'RÉPUBLIQUE').toUpperCase()),
                              style: pw.TextStyle(
                                font: timesBold,
                                fontSize: 10,
                                color: primary,
                              ),
                            ),
                            if ((schoolInfo!.republicMotto ?? '').isNotEmpty)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Text(
                                  schoolInfo!.republicMotto!,
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 9,
                                    color: primary,
                                    fontStyle: pw.FontStyle.italic,
                                  ),
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: ((schoolInfo!.inspection ?? '').isNotEmpty)
                            ? pw.Text(
                                'Inspection: ${schoolInfo!.inspection}',
                                style: pw.TextStyle(
                                  font: times,
                                  fontSize: 9,
                                  color: primary,
                                ),
                              )
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: ((schoolInfo!.educationDirection ?? '').isNotEmpty)
                              ? pw.Text(
                                  "Direction de l'enseignement: ${schoolInfo!.educationDirection}",
                                  style: pw.TextStyle(
                                    font: times,
                                    fontSize: 9,
                                    color: primary,
                                  ),
                                )
                              : pw.SizedBox(),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                ],
                // Header with logo and info
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: light,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: accent, width: 1),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (schoolInfo?.logoPath != null && File(schoolInfo!.logoPath!).existsSync())
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 16),
                          child: pw.Image(
                            pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                            width: 60,
                            height: 60,
                          ),
                        ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              schoolInfo?.name ?? 'Établissement',
                              style: pw.TextStyle(font: timesBold, fontSize: 16, color: accent),
                            ),
                            if ((schoolInfo?.address ?? '').isNotEmpty)
                              pw.Text(
                                schoolInfo!.address,
                                style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                              ),
                            if ((schoolInfo?.email ?? '').isNotEmpty)
                              pw.Text(
                                'Email : ${schoolInfo!.email}',
                                style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                              ),
                            if ((schoolInfo?.telephone ?? '').isNotEmpty)
                              pw.Text(
                                'Téléphone : ${schoolInfo!.telephone}',
                                style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                // Title bar
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(6)),
                  child: pw.Text(title, style: pw.TextStyle(font: timesBold, fontSize: 16, color: PdfColors.white)),
                ),
                pw.SizedBox(height: 10),
                // Totals summary
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Column(children: [
                        pw.Text('Total valeur', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Text(formatter.format(totalVal), style: pw.TextStyle(font: timesBold, fontSize: 12)),
                      ]),
                      pw.Column(children: [
                        pw.Text('Total quantités', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Text(totalQty.toStringAsFixed(0), style: pw.TextStyle(font: timesBold, fontSize: 12)),
                      ]),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                if (_inventoryItems.isEmpty)
                  pw.Text('Aucune donnée d\'inventaire disponible.')
                else
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(3),
                      2: const pw.FlexColumnWidth(1),
                      3: const pw.FlexColumnWidth(2),
                      4: const pw.FlexColumnWidth(2),
                      5: const pw.FlexColumnWidth(2),
                      6: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(4)),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Catégorie', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Article', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Qté', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Localisation', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('État', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Valeur', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Classe/Année', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                        ],
                      ),
                      ..._inventoryItems.map((it) => pw.TableRow(children: [
                            _pdfCell(it.category),
                            _pdfCell(it.name),
                            _pdfCell(it.quantity.toString()),
                            _pdfCell(it.location ?? ''),
                            _pdfCell(it.itemCondition ?? ''),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Align(
                                alignment: pw.Alignment.centerRight,
                                child: pw.Text(
                                  it.value == null ? '' : formatter.format(it.value!),
                                  style: const pw.TextStyle(fontSize: 10),
                                ),
                              ),
                            ),
                            _pdfCell('${it.className ?? '-'} / ${it.academicYear}'),
                          ])),
                      // Totaux
                      pw.TableRow(children: [
                        _pdfCell(''),
                        _pdfCell('TOTALS'),
                        _pdfCell(totalQty.toStringAsFixed(0)),
                        _pdfCell(''),
                        _pdfCell(''),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(
                              formatter.format(totalVal),
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                        ),
                        _pdfCell(''),
                      ]),
                    ],
                ),
            ],
            )
          ]);
        },
      ),
    );
    final fileName = 'inventaire_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(await pdf.save());
    OpenFile.open(file.path);
  }

  Future<void> _openInventoryFiltersDialog() async {
    final theme = Theme.of(context);
    String? cat = _selectedInvCategory;
    String? cond = _selectedInvCondition;
    String? loc = _selectedInvLocation;
    final categories = ['(Toutes)', ..._inventoryCategories];
    final conditions = ['(Tous)', ..._inventoryConditions];
    final locations = ['(Toutes)', ..._inventoryLocations];

    await showDialog(
      context: context,
      builder: (_) => CustomDialog(
        title: 'Filtres inventaire',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomFormField(
              labelText: 'Catégorie',
              isDropdown: true,
              dropdownItems: categories,
              dropdownValue: cat ?? '(Toutes)',
              onDropdownChanged: (v) => cat = (v == '(Toutes)') ? null : v,
            ),
            const SizedBox(height: 10),
            CustomFormField(
              labelText: 'État',
              isDropdown: true,
              dropdownItems: conditions,
              dropdownValue: cond ?? '(Tous)',
              onDropdownChanged: (v) => cond = (v == '(Tous)') ? null : v,
            ),
            const SizedBox(height: 10),
            CustomFormField(
              labelText: 'Localisation',
              isDropdown: true,
              dropdownItems: locations,
              dropdownValue: loc ?? '(Toutes)',
              onDropdownChanged: (v) => loc = (v == '(Toutes)') ? null : v,
            ),
          ],
        ),
        fields: const [],
        onSubmit: () async {
          setState(() {
            _selectedInvCategory = cat;
            _selectedInvCondition = cond;
            _selectedInvLocation = loc;
          });
          Navigator.of(context).pop();
          await _loadInventoryItems();
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _selectedInvCategory = cat;
                _selectedInvCondition = cond;
                _selectedInvLocation = loc;
              });
              Navigator.of(context).pop();
              await _loadInventoryItems();
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    academicYearNotifier.addListener(_onAcademicYearChanged);
  }

  void _onAcademicYearChanged() {
    setState(() {
      _selectedYearFilter = academicYearNotifier.value;
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final currentYear = await getCurrentAcademicYear();
    final payments = await _db.getAllPayments();
    final classes = await _db.getClasses();
    // Prepare students if gender filter is active
    if (_selectedGenderFilter != null) {
      final sts = await _db.getStudents();
      _studentsById = {for (final s in sts) s.id: s};
    } else {
      _studentsById = {};
    }

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
      if (_selectedGenderFilter != null) {
        final st = _studentsById[p.studentId];
        if (st == null || st.gender != _selectedGenderFilter) continue;
      }
      sum += p.amount;
    }
    // Compute expenses total for selected filters
    final expensesTotal = await _db.getTotalExpenses(
      className: _selectedClassFilter,
      academicYear: selectedYear,
    );
    if (!mounted) return;
    setState(() {
      _classes = classes.where((c) => c.academicYear == selectedYear).toList();
      _years = yearList;
      _selectedYearFilter = selectedYear;
      _year = selectedYear;
      _totalPayments = sum;
      _totalExpenses = expensesTotal;
      _loading = false;
    });
    // Load inventory items after updating filters
    await _loadInventoryItems();
    await _loadExpenses();
  }

  Future<void> _loadInventoryItems() async {
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();
    final items = await _db.getInventoryItems(
      className: _selectedClassFilter,
      academicYear: selectedYear,
    );
    // Facets from unfiltered items
    final cats = items.map((e) => e.category).toSet().toList()..sort();
    final conds = items
        .map((e) => (e.itemCondition ?? ''))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final locs = items
        .map((e) => (e.location ?? ''))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    // Apply local filters
    final filtered = items.where((it) {
      if (_selectedInvCategory != null && _selectedInvCategory!.isNotEmpty) {
        if (it.category != _selectedInvCategory) return false;
      }
      if (_selectedInvCondition != null && _selectedInvCondition!.isNotEmpty) {
        if ((it.itemCondition ?? '') != _selectedInvCondition) return false;
      }
      if (_selectedInvLocation != null && _selectedInvLocation!.isNotEmpty) {
        if ((it.location ?? '') != _selectedInvLocation) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!it.name.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();
    final total = filtered.fold<double>(0.0, (sum, it) => sum + (it.value ?? 0) * (it.quantity));
    if (!mounted) return;
    setState(() {
      _inventoryItems = filtered;
      _inventoryTotalValue = total;
      _inventoryCategories = cats;
      _inventoryConditions = conds;
      _inventoryLocations = locs;
    });
  }

  Future<void> _loadExpenses() async {
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();
    final list = await _db.getExpenses(
      className: _selectedClassFilter,
      academicYear: selectedYear,
      category: _selectedExpenseCategory,
      supplier: _selectedExpenseSupplier,
    );
    final cats = list.map((e) => e.category ?? '').where((e) => e.isNotEmpty).toSet().toList()..sort();
    final sups = list.map((e) => e.supplier ?? '').where((e) => e.isNotEmpty).toSet().toList()..sort();
    final total = list.fold<double>(0.0, (sum, e) => sum + e.amount);
    if (!mounted) return;
    setState(() {
      _expenses = list;
      _expenseCategories = cats;
      _expenseSuppliers = sups;
      _totalExpenses = total; // keep card synced even if _loadData not called
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    academicYearNotifier.removeListener(_onAcademicYearChanged);
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
            onChanged: (v) async {
              setState(() => _searchQuery = v.trim());
              await _loadInventoryItems();
            },
            decoration: InputDecoration(
              hintText: 'Rechercher article',
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
    final genders = const ['M', 'F'];
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
            // Classe (comme dans la page Paiements)
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
                  DropdownMenuItem<String?>(value: null, child: Text('Toutes les classes', style: TextStyle(color: theme.textTheme.bodyMedium?.color))),
                  for (final name in classNames) DropdownMenuItem<String?>(value: name, child: Text(name)),
                ],
                onChanged: (v) => setState(() { _selectedClassFilter = v; _loadData(); }),
                underline: const SizedBox.shrink(),
                dropdownColor: theme.cardColor,
                iconEnabledColor: theme.iconTheme.color,
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
            const SizedBox(width: 8),
            // Année (ValueListenableBuilder + "Année courante")
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: academicYearNotifier,
                builder: (context, currentYear, _) {
                  final others = _years.where((y) => y != currentYear).toList()..sort();
                  return DropdownButton<String?>(
                    value: _selectedYearFilter,
                    hint: Text('Année', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('Toutes les années', style: TextStyle(color: theme.textTheme.bodyMedium?.color))),
                      DropdownMenuItem<String?>(value: currentYear, child: Text('Année courante ($currentYear)', style: TextStyle(color: theme.textTheme.bodyMedium?.color))),
                      for (final y in others) DropdownMenuItem<String?>(value: y, child: Text(y)),
                    ],
                    onChanged: (v) => setState(() { _selectedYearFilter = v; _loadData(); }),
                    underline: const SizedBox.shrink(),
                    dropdownColor: theme.cardColor,
                    iconEnabledColor: theme.iconTheme.color,
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            // Sexe (optionnel)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: DropdownButton<String?>(
                value: _selectedGenderFilter,
                hint: Text('Sexe', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('Tous', style: TextStyle(color: theme.textTheme.bodyMedium?.color))),
                  for (final g in genders) DropdownMenuItem<String?>(value: g, child: Text(g == 'M' ? 'Garçons' : 'Filles')),
                ],
                onChanged: (v) => setState(() { _selectedGenderFilter = v; _loadData(); }),
                underline: const SizedBox.shrink(),
                dropdownColor: theme.cardColor,
                iconEnabledColor: theme.iconTheme.color,
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _exportFinanceToPdf,
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text('Exporter PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _exportFinanceToExcel,
              icon: const Icon(Icons.grid_on, color: Colors.white),
              label: const Text('Exporter Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64748B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildInventoryFilters(BuildContext context) {
    final theme = Theme.of(context);
    final classNames = _classes.map((c) => c.name).toList()..sort();
    final categories = _inventoryCategories;
    final conditionsSet = _inventoryConditions;
    final locations = _inventoryLocations;
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
            // Classe (ordre calqué sur la page Paiements)
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
            const SizedBox(width: 8),
            // Année (ValueListenableBuilder + Année courante)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: academicYearNotifier,
                builder: (context, currentYear, _) {
                  final others = _years.where((y) => y != currentYear).toList()..sort();
                  return DropdownButton<String?>(
                    value: _selectedYearFilter,
                    hint: Text('Année', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('Toutes les années', style: TextStyle(color: theme.textTheme.bodyMedium?.color))),
                      DropdownMenuItem<String?>(value: currentYear, child: Text('Année courante ($currentYear)', style: TextStyle(color: theme.textTheme.bodyMedium?.color))),
                      for (final y in others) DropdownMenuItem<String?>(value: y, child: Text(y)),
                    ],
                    onChanged: (v) => setState(() { _selectedYearFilter = v; _loadData(); }),
                    underline: const SizedBox.shrink(),
                    dropdownColor: theme.cardColor,
                    iconEnabledColor: theme.iconTheme.color,
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            // Bouton Filtres (Catégorie/État/Localisation)
            OutlinedButton.icon(
              onPressed: _openInventoryFiltersDialog,
              icon: const Icon(Icons.tune),
              label: const Text('Filtres'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.textTheme.bodyMedium?.color,
                side: BorderSide(color: theme.dividerColor),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
            // Exports (même style que Finances)
            ElevatedButton.icon(
              onPressed: _exportInventoryToPdf,
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text('Exporter PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _exportInventoryToExcel,
              icon: const Icon(Icons.grid_on, color: Colors.white),
              label: const Text('Exporter Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64748B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            ],
          ),
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
          // Filtres en premier (au-dessus des cartes)
          _buildFinanceFilters(context),
          const SizedBox(height: 16),
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
                      value: _loading ? '...' : _formatCurrency(_totalExpenses),
                      color: const Color(0xFFEF4444))),
                  const SizedBox(width: 12),
                  Expanded(child: _infoCard(context,
                      title: 'Solde net',
                      value: _loading ? '...' : _formatCurrency((_totalPayments - _totalExpenses).clamp(-1e12, 1e12)),
                      color: const Color(0xFF3B82F6))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildExpensesCard(context),
        ],
      ),
    );
  }

  Widget _buildExpensesCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dépenses', style: theme.textTheme.titleMedium),
                Row(children: [
                  // Category filter (optional)
                  if (_expenseCategories.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: DropdownButton<String?>(
                        value: _selectedExpenseCategory,
                        hint: Text('Catégorie', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('Toutes', style: TextStyle(color: theme.textTheme.bodyMedium?.color))),
                          for (final c in _expenseCategories) DropdownMenuItem<String?>(value: c, child: Text(c)),
                        ],
                        onChanged: (v) async {
                          setState(() => _selectedExpenseCategory = v);
                          await _loadExpenses();
                        },
                        underline: const SizedBox.shrink(),
                        dropdownColor: theme.cardColor,
                        iconEnabledColor: theme.iconTheme.color,
                        style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Supplier filter (optional)
                  if (_expenseSuppliers.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: DropdownButton<String?>(
                        value: _selectedExpenseSupplier,
                        hint: Text('Fournisseur', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('Tous', style: TextStyle(color: theme.textTheme.bodyMedium?.color))),
                          for (final s in _expenseSuppliers) DropdownMenuItem<String?>(value: s, child: Text(s)),
                        ],
                        onChanged: (v) async {
                          setState(() => _selectedExpenseSupplier = v);
                          await _loadExpenses();
                        },
                        underline: const SizedBox.shrink(),
                        dropdownColor: theme.cardColor,
                        iconEnabledColor: theme.iconTheme.color,
                        style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ElevatedButton.icon(
                    onPressed: _showAddExpenseDialog,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Ajouter dépense'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 12),
            if (_expenses.isEmpty)
              Text('Aucune dépense pour les filtres sélectionnés.', style: theme.textTheme.bodyMedium)
            else
              _buildExpensesTable(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesTable(ThemeData theme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(children: [
            _sortableHeader('Date', 'date', theme),
            _sortableHeader('Libellé', 'label', theme, flex: 3),
            _invHeader('Catégorie', flex: 2, theme: theme),
            _sortableHeader('Montant', 'amount', theme),
            _invHeader('Classe', theme: theme),
            _invHeader('Fournisseur', flex: 2, theme: theme),
            _invHeader('Actions', theme: theme),
          ]),
        ),
        const SizedBox(height: 4),
        ..._sortedExpenses().map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
              ),
              child: Row(children: [
                _invCell(e.date.substring(0, 10), theme: theme),
                _invCell(e.label, flex: 3, theme: theme),
                _invCell(e.category ?? '-', flex: 2, theme: theme),
                _invCell(_formatCurrency(e.amount), theme: theme),
                _invCell(e.className ?? '-', theme: theme),
                _invCell(e.supplier ?? '-', flex: 2, theme: theme),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Modifier',
                        icon: const Icon(Icons.edit, color: Color(0xFF2563EB)),
                        onPressed: () => _showAddExpenseDialog(existing: e),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete, color: Color(0xFFE11D48)),
                        onPressed: () async {
                          final ok = await _confirmDeletion(
                            context,
                            title: 'Supprimer la dépense',
                            message: '“${e.label}” - ${_formatCurrency(e.amount)}\nVoulez-vous vraiment supprimer cette dépense ?',
                          );
                          if (ok && e.id != null) {
                            await _db.deleteExpense(e.id!);
                            await _loadExpenses();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ]),
            )),
      ],
    );
  }

  Future<bool> _confirmDeletion(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final theme = Theme.of(context);
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => CustomDialog(
        title: title,
        showCloseIcon: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFEF4444),
                size: 36,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            const SizedBox(height: 8),
            Text(
              'Cette action est irréversible.',
              style: TextStyle(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        fields: const [],
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.textTheme.bodyMedium?.color,
              side: BorderSide(color: theme.dividerColor),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _showAddExpenseDialog({Expense? existing}) async {
    final theme = Theme.of(context);
    final formKey = GlobalKey<FormState>();
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final amountCtrl = TextEditingController(text: existing?.amount.toStringAsFixed(0) ?? '');
    final dateCtrl = TextEditingController(text: existing?.date.substring(0, 10) ?? '');
    final supplierCtrl = TextEditingController(text: existing?.supplier ?? '');
    final categories = List<String>.from(_expenseCategories);
    if (existing?.category != null && existing!.category!.isNotEmpty && !categories.contains(existing.category)) {
      categories.add(existing.category!);
    }
    categories.add('Autre…');
    String? categoryValue = categories.contains(existing?.category) ? existing?.category : null;
    final newCategoryCtrl = TextEditingController(text: categoryValue == null ? (existing?.category ?? '') : '');
    final classNames = _classes.map((c) => c.name).toList()..sort();
    String? classValue = classNames.contains(existing?.className) ? existing?.className : _selectedClassFilter;
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();

    await showDialog(
      context: context,
      builder: (_) => CustomDialog(
        title: existing == null ? 'Ajouter une dépense' : 'Modifier la dépense',
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomFormField(
                controller: labelCtrl,
                labelText: 'Libellé',
                hintText: 'Ex: Fournitures scolaires',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Libellé requis' : null,
              ),
              const SizedBox(height: 10),
              CustomFormField(
                controller: amountCtrl,
                labelText: 'Montant (FCFA)',
                hintText: 'Ex: 50000',
                validator: (v) {
                  final d = double.tryParse((v ?? '').trim());
                  return (d == null || d <= 0) ? 'Montant invalide' : null;
                },
              ),
              const SizedBox(height: 10),
              CustomFormField(
                controller: supplierCtrl,
                labelText: 'Fournisseur (optionnel)',
                hintText: 'Ex: ABC SARL',
              ),
              const SizedBox(height: 10),
              CustomFormField(
                labelText: 'Catégorie',
                isDropdown: true,
                dropdownItems: categories,
                dropdownValue: categoryValue,
                onDropdownChanged: (val) => categoryValue = val,
              ),
              if (categoryValue == 'Autre…' || categoryValue == null) ...[
                const SizedBox(height: 10),
                CustomFormField(
                  controller: newCategoryCtrl,
                  labelText: 'Nouvelle catégorie',
                  hintText: 'Ex: Transport',
                ),
              ],
              const SizedBox(height: 10),
              CustomFormField(
                controller: dateCtrl,
                labelText: 'Date',
                hintText: 'AAAA-MM-JJ',
                readOnly: true,
                onTap: () async {
                  final now = DateTime.now();
                  final initial = dateCtrl.text.isNotEmpty ? DateTime.tryParse(dateCtrl.text) ?? now : now;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(now.year - 10),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (picked != null) dateCtrl.text = picked.toIso8601String().substring(0, 10);
                },
              ),
              const SizedBox(height: 10),
              CustomFormField(
                labelText: 'Classe (optionnel)',
                isDropdown: true,
                dropdownItems: ['Aucune', ...classNames],
                dropdownValue: classValue ?? 'Aucune',
                onDropdownChanged: (val) => classValue = (val == 'Aucune') ? null : val,
              ),
            ],
          ),
        ),
        fields: const [],
        onSubmit: () async {
          if (!(formKey.currentState?.validate() ?? false)) return;
          final amount = double.parse(amountCtrl.text.trim());
          final effectiveCategory = (categoryValue == 'Autre…' || categoryValue == null)
              ? (newCategoryCtrl.text.trim().isEmpty ? null : newCategoryCtrl.text.trim())
              : categoryValue;
          final expense = Expense(
            id: existing?.id,
            label: labelCtrl.text.trim(),
            category: effectiveCategory,
            supplier: supplierCtrl.text.trim().isEmpty ? null : supplierCtrl.text.trim(),
            amount: amount,
            date: (dateCtrl.text.trim().isEmpty ? DateTime.now().toIso8601String() : DateTime.parse(dateCtrl.text.trim()).toIso8601String()),
            className: classValue,
            academicYear: selectedYear,
          );
          if (existing == null) {
            await _db.insertExpense(expense);
          } else {
            await _db.updateExpense(expense);
          }
          Navigator.of(context).pop();
          await _loadExpenses();
        },
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
        // Summary card for inventory value (like total payments)
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
                Expanded(
                  child: _infoCard(
                    context,
                    title: 'Valeur inventaire ' + (_year.isEmpty ? '' : '($_year)'),
                    value: _loading ? '...' : _formatCurrency(_inventoryTotalValue),
                    color: const Color(0xFF22C55E),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildInventoryListCard(context, theme),
      ],
    );
  }

  Widget _buildInventoryListCard(BuildContext context, ThemeData theme) {
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Inventaire', style: theme.textTheme.titleMedium),
                ElevatedButton.icon(
                  onPressed: _showAddInventoryItemDialog,
                  icon: const Icon(Icons.add_box, color: Colors.white),
                  label: const Text('Ajouter un article'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_inventoryItems.isEmpty)
              Text('Aucun article trouvé pour les filtres sélectionnés.', style: theme.textTheme.bodyMedium)
            else
              _buildInventoryTable(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryTable(ThemeData theme) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              _invHeader('Nom', flex: 3, theme: theme),
              _invHeader('Catégorie', flex: 2, theme: theme),
              _invHeader('Qté', theme: theme),
              _invHeader('Localisation', flex: 2, theme: theme),
              _invHeader('État', theme: theme),
              _invHeader('Valeur', theme: theme),
              _invHeader('Classe', flex: 2, theme: theme),
              _invHeader('Année', theme: theme),
              _invHeader('Actions', flex: 2, theme: theme),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Rows
        ..._inventoryItems.map((it) => _buildInventoryRow(it, theme)).toList(),
      ],
    );
  }

  Widget _invHeader(String text, {int flex = 1, required ThemeData theme}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: theme.textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  // Sorting for expenses
  String _expenseSortBy = 'date';
  bool _expenseSortAsc = false;

  Widget _sortableHeader(String label, String key, ThemeData theme, {int flex = 1}) {
    final active = _expenseSortBy == key;
    final icon = active
        ? (_expenseSortAsc ? Icons.arrow_upward : Icons.arrow_downward)
        : Icons.swap_vert;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_expenseSortBy == key) {
              _expenseSortAsc = !_expenseSortAsc;
            } else {
              _expenseSortBy = key;
              _expenseSortAsc = true;
            }
          });
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: theme.iconTheme.color),
          ],
        ),
      ),
    );
  }

  List<Expense> _sortedExpenses() {
    final list = List<Expense>.from(_expenses);
    int cmp<T extends Comparable>(T a, T b) => a.compareTo(b);
    list.sort((a, b) {
      int c = 0;
      switch (_expenseSortBy) {
        case 'label':
          c = cmp(a.label.toLowerCase(), b.label.toLowerCase());
          break;
        case 'amount':
          c = cmp(a.amount, b.amount);
          break;
        case 'date':
        default:
          final ad = DateTime.tryParse(a.date) ?? DateTime(1900);
          final bd = DateTime.tryParse(b.date) ?? DateTime(1900);
          c = cmp(ad, bd);
      }
      return _expenseSortAsc ? c : -c;
    });
    return list;
  }

  Widget _invCell(String text, {int flex = 1, required ThemeData theme}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: theme.textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  Widget _buildInventoryRow(InventoryItem it, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          _invCell(it.name, flex: 3, theme: theme),
          _invCell(it.category, flex: 2, theme: theme),
          _invCell(it.quantity.toString(), theme: theme),
          _invCell(it.location ?? '-', flex: 2, theme: theme),
          _invCell(it.itemCondition ?? '-', theme: theme),
          _invCell(it.value == null ? '-' : '${it.value!.toStringAsFixed(0)} FCFA', theme: theme),
          _invCell(it.className ?? '-', flex: 2, theme: theme),
          _invCell(it.academicYear, theme: theme),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit, color: Color(0xFF2563EB)),
                  onPressed: () => _showEditInventoryItemDialog(it),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete, color: Color(0xFFE11D48)),
                  onPressed: () async {
                    final ok = await _confirmDeletion(
                      context,
                      title: 'Supprimer l\'article',
                      message: '“${it.name}” (x${it.quantity})\nVoulez-vous vraiment supprimer cet article ?',
                    );
                    if (ok) await _deleteInventoryItem(it);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddInventoryItemDialog() async {
    await _showInventoryItemDialog();
  }

  Future<void> _showEditInventoryItemDialog(InventoryItem it) async {
    await _showInventoryItemDialog(existing: it);
  }

  Future<void> _showInventoryItemDialog({InventoryItem? existing}) async {
    final theme = Theme.of(context);
    final formKey = GlobalKey<FormState>();
    // Controllers
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final quantityCtrl = TextEditingController(text: (existing?.quantity ?? 1).toString());
    final valueCtrl = TextEditingController(text: existing?.value?.toStringAsFixed(0) ?? '');
    final supplierCtrl = TextEditingController(text: existing?.supplier ?? '');
    final purchaseDateCtrl = TextEditingController(text: existing?.purchaseDate ?? '');

    // Dropdown sources
    final fixedConditions = ['Neuf', 'Bon', 'Usé', 'Réparé', 'Hors service'];
    final classNames = _classes.map((c) => c.name).toList()..sort();
    // Category dropdown + custom
    final categories = List<String>.from(_inventoryCategories);
    if (existing?.category != null && existing!.category.isNotEmpty && !categories.contains(existing.category)) {
      categories.add(existing.category);
    }
    categories.add('Autre…');
    String? categoryValue = categories.contains(existing?.category) ? existing?.category : null;
    final newCategoryCtrl = TextEditingController(text: categoryValue == null ? (existing?.category ?? '') : '');
    // Location dropdown + custom
    final locations = List<String>.from(_inventoryLocations);
    if (existing?.location != null && existing!.location!.isNotEmpty && !locations.contains(existing.location)) {
      locations.add(existing.location!);
    }
    locations.add('Autre…');
    String? locationValue = locations.contains(existing?.location) ? existing?.location : null;
    final newLocationCtrl = TextEditingController(text: locationValue == null ? (existing?.location ?? '') : '');
    // Condition dropdown
    String? conditionValue = fixedConditions.contains(existing?.itemCondition) ? existing?.itemCondition : null;
    // Class dropdown
    String? classValue = classNames.contains(existing?.className) ? existing?.className : _selectedClassFilter;
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocalState) => CustomDialog(
          title: existing == null ? 'Ajouter un article' : 'Modifier l\'article',
          content: Form(
            key: formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 640;
                final children = <Widget>[
                  // Nom (obligatoire)
                  CustomFormField(
                    controller: nameCtrl,
                    labelText: 'Nom',
                    hintText: 'Ex: Ordinateur portable',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                  ),
                  // Catégorie (dropdown + Autre)
                  CustomFormField(
                    labelText: 'Catégorie',
                    hintText: 'Sélectionner',
                    isDropdown: true,
                    dropdownItems: categories,
                    dropdownValue: categoryValue,
                    onDropdownChanged: (val) {
                      setLocalState(() {
                        categoryValue = val;
                      });
                    },
                    validator: (_) {
                      final effective = (categoryValue == 'Autre…' || categoryValue == null)
                          ? newCategoryCtrl.text.trim()
                          : (categoryValue ?? '');
                      return effective.isEmpty ? 'Catégorie requise' : null;
                    },
                  ),
                  if (categoryValue == 'Autre…' || categoryValue == null)
                    CustomFormField(
                      controller: newCategoryCtrl,
                      labelText: 'Nouvelle catégorie',
                      hintText: 'Ex: Informatique',
                      validator: (v) {
                        if (categoryValue == 'Autre…' || categoryValue == null) {
                          return (v == null || v.trim().isEmpty) ? 'Catégorie requise' : null;
                        }
                        return null;
                      },
                    ),
                  // Quantité (obligatoire, >0)
                  CustomFormField(
                    controller: quantityCtrl,
                    labelText: 'Quantité',
                    hintText: 'Ex: 10',
                    validator: (v) {
                      final qty = int.tryParse((v ?? '').trim());
                      if (qty == null || qty <= 0) return 'Quantité invalide';
                      return null;
                    },
                  ),
                  // Localisation (dropdown + Autre)
                  CustomFormField(
                    labelText: 'Localisation',
                    hintText: 'Sélectionner',
                    isDropdown: true,
                    dropdownItems: locations,
                    dropdownValue: locationValue,
                    onDropdownChanged: (val) => setLocalState(() => locationValue = val),
                  ),
                  if (locationValue == 'Autre…' || locationValue == null)
                    CustomFormField(
                      controller: newLocationCtrl,
                      labelText: 'Nouvelle localisation',
                      hintText: 'Ex: Salle A1',
                    ),
                  // État (dropdown)
                  CustomFormField(
                    labelText: 'État',
                    hintText: 'Sélectionner',
                    isDropdown: true,
                    dropdownItems: fixedConditions,
                    dropdownValue: conditionValue,
                    onDropdownChanged: (val) => setLocalState(() => conditionValue = val),
                  ),
                  // Valeur (optionnel)
                  CustomFormField(
                    controller: valueCtrl,
                    labelText: 'Valeur (FCFA)',
                    hintText: 'Ex: 150000',
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final d = double.tryParse(v.trim());
                      return d == null || d < 0 ? 'Valeur invalide' : null;
                    },
                  ),
                  // Fournisseur (optionnel)
                  CustomFormField(
                    controller: supplierCtrl,
                    labelText: 'Fournisseur',
                    hintText: 'Ex: ABC SARL',
                  ),
                  // Date d'achat avec date picker
                  CustomFormField(
                    controller: purchaseDateCtrl,
                    labelText: 'Date d\'achat',
                    hintText: 'AAAA-MM-JJ',
                    readOnly: true,
                    onTap: () async {
                      final now = DateTime.now();
                      final initial = purchaseDateCtrl.text.isNotEmpty
                          ? DateTime.tryParse(purchaseDateCtrl.text) ?? now
                          : now;
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: DateTime(now.year - 10),
                        lastDate: DateTime(now.year + 10),
                      );
                      if (picked != null) {
                        purchaseDateCtrl.text = picked.toIso8601String().substring(0, 10);
                      }
                    },
                  ),
                  // Classe (dropdown, optionnel)
                  CustomFormField(
                    labelText: 'Classe (optionnel)',
                    hintText: 'Sélectionner',
                    isDropdown: true,
                    dropdownItems: ['Aucune', ...classNames],
                    dropdownValue: classValue ?? 'Aucune',
                    onDropdownChanged: (val) => setLocalState(() {
                      classValue = (val == 'Aucune') ? null : val;
                    }),
                  ),
                ];

                if (!twoCols) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final w in children) ...[w, const SizedBox(height: 10)]],
                  );
                }
                // Two columns layout
                final left = <Widget>[];
                final right = <Widget>[];
                for (var i = 0; i < children.length; i++) {
                  (i % 2 == 0 ? left : right).add(children[i]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: [for (final w in left) ...[w, const SizedBox(height: 10)]])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(children: [for (final w in right) ...[w, const SizedBox(height: 10)]])),
                  ],
                );
              },
            ),
          ),
          fields: const [],
          onSubmit: () async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final qty = int.parse(quantityCtrl.text.trim());
            final val = valueCtrl.text.trim().isEmpty ? null : double.parse(valueCtrl.text.trim());
            final effectiveCategory = (categoryValue == 'Autre…' || categoryValue == null)
                ? newCategoryCtrl.text.trim()
                : categoryValue!;
            final effectiveLocation = (locationValue == 'Autre…' || locationValue == null)
                ? (newLocationCtrl.text.trim().isEmpty ? null : newLocationCtrl.text.trim())
                : locationValue;
            final newItem = InventoryItem(
              id: existing?.id,
              name: nameCtrl.text.trim(),
              category: effectiveCategory,
              quantity: qty,
              location: effectiveLocation,
              itemCondition: conditionValue,
              value: val,
              supplier: supplierCtrl.text.trim().isEmpty ? null : supplierCtrl.text.trim(),
              purchaseDate: purchaseDateCtrl.text.trim().isEmpty ? null : purchaseDateCtrl.text.trim(),
              className: classValue,
              academicYear: selectedYear,
            );
            if (existing == null) {
              await _db.insertInventoryItem(newItem);
            } else {
              await _db.updateInventoryItem(newItem);
            }
            Navigator.of(context).pop();
            await _loadInventoryItems();
          },
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final qty = int.parse(quantityCtrl.text.trim());
                final val = valueCtrl.text.trim().isEmpty ? null : double.parse(valueCtrl.text.trim());
                final effectiveCategory = (categoryValue == 'Autre…' || categoryValue == null)
                    ? newCategoryCtrl.text.trim()
                    : categoryValue!;
                final effectiveLocation = (locationValue == 'Autre…' || locationValue == null)
                    ? (newLocationCtrl.text.trim().isEmpty ? null : newLocationCtrl.text.trim())
                    : locationValue;
                final newItem = InventoryItem(
                  id: existing?.id,
                  name: nameCtrl.text.trim(),
                  category: effectiveCategory,
                  quantity: qty,
                  location: effectiveLocation,
                  itemCondition: conditionValue,
                  value: val,
                  supplier: supplierCtrl.text.trim().isEmpty ? null : supplierCtrl.text.trim(),
                  purchaseDate: purchaseDateCtrl.text.trim().isEmpty ? null : purchaseDateCtrl.text.trim(),
                  className: classValue,
                  academicYear: selectedYear,
                );
                if (existing == null) {
                  await _db.insertInventoryItem(newItem);
                } else {
                  await _db.updateInventoryItem(newItem);
                }
                Navigator.of(context).pop();
                await _loadInventoryItems();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteInventoryItem(InventoryItem it) async {
    await _db.deleteInventoryItem(it.id!);
    await _loadInventoryItems();
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
