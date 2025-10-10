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
  double _expectedTotal = 0.0;
  double _remainingTotal = 0.0;
  // Per-class finance summary (for selected year + current filters)
  List<_ClassFinance> _perClassFinance = [];
  String _classSearchQuery = '';
  String _classSortKey = 'classe'; // 'classe' | 'reste' | 'solde' | 'encaissements' | 'depenses' | 'attendu'
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel exporté: $fileName')),
        );
      }
      await OpenFile.open(file.path);
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
    // Expected & remaining global
    final classes = await _db.getClasses();
    double expectedTotal = 0.0;
    for (final c in classes.where((c) => c.academicYear == selectedYear)) {
      if (_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty) {
        if (c.name != _selectedClassFilter) continue;
      }
      final double unitFee = (c.fraisEcole ?? 0) + (c.fraisCotisationParallele ?? 0);
      if (unitFee <= 0) continue;
      final students = await _db.getStudentsByClassAndClassYear(c.name, selectedYear);
      expectedTotal += unitFee * (students.length);
    }
    final remainingTotal = (expectedTotal - total) < 0 ? 0 : (expectedTotal - total);
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
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(now, style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('Page ${context.pageNumber} / ${context.pagesCount}', style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          );
        },
        build: (ctx) {
          return [
            pw.Stack(children: [
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
                // Bandeau administratif léger
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if ((schoolInfo?.ministry ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.ministry!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                          if ((schoolInfo?.educationDirection ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.educationDirection!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                          if ((schoolInfo?.inspection ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.inspection!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          if ((schoolInfo?.republic ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.republic!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                          if ((schoolInfo?.republicMotto ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.republicMotto!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8, fontStyle: pw.FontStyle.italic)),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                // Header centré (logo + nom)
                pw.Center(
                  child: pw.Column(
                    children: [
                      if (schoolInfo?.logoPath != null && File(schoolInfo!.logoPath!).existsSync())
                        pw.Container(
                          height: 46,
                          width: 46,
                          margin: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.Image(
                            pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                            fit: pw.BoxFit.contain,
                          ),
                        ),
                      pw.Text(
                        (schoolInfo?.name ?? 'Établissement').toUpperCase(),
                        style: pw.TextStyle(font: timesBold, fontSize: 14),
                      ),
                      if ((schoolInfo?.address ?? '').isNotEmpty)
                        pw.Text(
                          schoolInfo!.address,
                          style: pw.TextStyle(font: times, fontSize: 9, color: primary),
                        ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Année académique: $selectedYear  -  Généré le: $now',
                        style: pw.TextStyle(font: times, fontSize: 9, color: primary),
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
                      pw.Column(children: [
                        pw.Text('Attendu', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Text(formatter.format(expectedTotal), style: pw.TextStyle(font: timesBold, fontSize: 12)),
                      ]),
                      pw.Column(children: [
                        pw.Text('Reste', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          formatter.format(remainingTotal),
                          style: pw.TextStyle(font: timesBold, fontSize: 12, color: remainingTotal > 0 ? PdfColors.orange800 : PdfColors.green800),
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
              ),
              pw.SizedBox(height: 14),
              // Signature & cachet
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(children: [
                          pw.Text('Fait à : ', style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                          pw.Text((schoolInfo?.address ?? '').isNotEmpty ? schoolInfo!.address : '__________________________', style: pw.TextStyle(font: times, fontSize: 10)),
                        ]),
                        pw.SizedBox(height: 2),
                        pw.Row(children: [
                          pw.Text('Le : ', style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                          pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now()), style: pw.TextStyle(font: times, fontSize: 10)),
                        ]),
                        pw.SizedBox(height: 18),
                        pw.Text('Signature du responsable', style: pw.TextStyle(font: times, fontSize: 10)),
                        pw.SizedBox(height: 28),
                        pw.Container(width: 160, height: 0.8, color: PdfColors.grey400),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 24),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Cachet et signature de l'établissement", style: pw.TextStyle(font: times, fontSize: 10)),
                        pw.SizedBox(height: 56),
                        pw.Container(width: 200, height: 0.8, color: PdfColors.grey400),
                      ],
                    ),
                  ),
                ],
              )
            ],
            )
          ])];
        },
      ),
    );
    final fileName = 'finances_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(await pdf.save());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF exporté: $fileName')),
      );
    }
    await OpenFile.open(file.path);
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
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now()), style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('Page ${context.pageNumber} / ${context.pagesCount}', style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          );
        },
        build: (ctx) {
          return [
            pw.Stack(children: [
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
                // Bandeau administratif (ministère / direction / inspection) & (république / devise)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if ((schoolInfo?.ministry ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.ministry!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                          if ((schoolInfo?.educationDirection ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.educationDirection!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                          if ((schoolInfo?.inspection ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.inspection!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          if ((schoolInfo?.republic ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.republic!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                          if ((schoolInfo?.republicMotto ?? '').isNotEmpty)
                            pw.Text((schoolInfo!.republicMotto!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8, fontStyle: pw.FontStyle.italic)),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                // En-tête centré (logo + nom + adresse + date)
                pw.Center(
                  child: pw.Column(children: [
                    if (schoolInfo?.logoPath != null && File(schoolInfo!.logoPath!).existsSync())
                      pw.Container(
                        height: 46,
                        width: 46,
                        margin: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Image(
                          pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    pw.Text(
                      (schoolInfo?.name ?? 'Établissement').toUpperCase(),
                      style: pw.TextStyle(font: timesBold, fontSize: 14),
                    ),
                    if ((schoolInfo?.address ?? '').isNotEmpty)
                      pw.Text(
                        schoolInfo!.address,
                        style: pw.TextStyle(font: times, fontSize: 9, color: primary),
                      ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Année académique: ${_selectedYearFilter ?? _year}  -  Généré le: ' + DateFormat('dd/MM/yyyy').format(DateTime.now()),
                      style: pw.TextStyle(font: times, fontSize: 9, color: primary),
                    ),
                  ]),
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
                pw.SizedBox(height: 14),
                // Signature & cachet
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(children: [
                            pw.Text('Fait à : ', style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                            pw.Text((schoolInfo?.address ?? '').isNotEmpty ? schoolInfo!.address : '__________________________', style: pw.TextStyle(font: times, fontSize: 10)),
                          ]),
                          pw.SizedBox(height: 2),
                          pw.Row(children: [
                            pw.Text('Le : ', style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                            pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now()), style: pw.TextStyle(font: times, fontSize: 10)),
                          ]),
                          pw.SizedBox(height: 18),
                          pw.Text('Signature du responsable', style: pw.TextStyle(font: times, fontSize: 10)),
                          pw.SizedBox(height: 28),
                          pw.Container(width: 160, height: 0.8, color: PdfColors.grey400),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 24),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("Cachet et signature de l'établissement", style: pw.TextStyle(font: times, fontSize: 10)),
                          pw.SizedBox(height: 56),
                          pw.Container(width: 200, height: 0.8, color: PdfColors.grey400),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
            )
          ])];
        },
      ),
    );
    final fileName = 'inventaire_${(_selectedYearFilter ?? _year).replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(await pdf.save());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF exporté: $fileName')),
      );
    }
    await OpenFile.open(file.path);
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
    final Map<String, double> payByClass = {};
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
      payByClass[p.className] = (payByClass[p.className] ?? 0) + p.amount;
    }
    // Compute expenses total for selected filters
    final expensesTotal = await _db.getTotalExpenses(
      className: _selectedClassFilter,
      academicYear: selectedYear,
    );
    // Build per-class expenses map using same filters (but grouped by class)
    final allExpenses = await _db.getExpenses(
      academicYear: selectedYear,
      category: _selectedExpenseCategory,
      supplier: _selectedExpenseSupplier,
    );
    final Map<String, double> depByClass = {};
    for (final e in allExpenses) {
      final cls = (e.className ?? '').trim();
      if (_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty) {
        if (cls != _selectedClassFilter) continue;
      }
      depByClass[cls] = (depByClass[cls] ?? 0) + e.amount;
    }
    // Compute expected amount per class = (fraisEcole + fraisCotisationParallele) * nb élèves de la classe (année sélectionnée)
    final Map<String, double> expectedByClass = {};
    final Map<String, int> countByClass = {};
    final Map<String, double> unitFeeByClass = {};
    double expectedTotal = 0.0;
    for (final c in classes.where((c) => c.academicYear == selectedYear)) {
      if (_selectedClassFilter != null && _selectedClassFilter!.isNotEmpty) {
        if (c.name != _selectedClassFilter) continue;
      }
      final double unitFee = (c.fraisEcole ?? 0) + (c.fraisCotisationParallele ?? 0);
      if (unitFee <= 0) {
        expectedByClass[c.name] = 0.0;
        countByClass[c.name] = 0;
        unitFeeByClass[c.name] = unitFee;
        continue;
      }
      final students = await _db.getStudentsByClassAndClassYear(c.name, selectedYear);
      final double exp = unitFee * (students.length);
      expectedByClass[c.name] = exp;
      countByClass[c.name] = students.length;
      unitFeeByClass[c.name] = unitFee;
      expectedTotal += exp;
    }
    if (!mounted) return;
    setState(() {
      _classes = classes.where((c) => c.academicYear == selectedYear).toList();
      _years = yearList;
      _selectedYearFilter = selectedYear;
      _year = selectedYear;
      _totalPayments = sum;
      _totalExpenses = expensesTotal;
      // Compose per-class list (for all classes of the selected year)
      _perClassFinance = _classes
          .map((c) {
            final pay = payByClass[c.name] ?? 0.0;
            final dep = depByClass[c.name] ?? 0.0;
            final exp = expectedByClass[c.name] ?? 0.0;
            final cnt = countByClass[c.name] ?? 0;
            final uf = unitFeeByClass[c.name] ?? 0.0;
            return _ClassFinance(className: c.name, payments: pay, expenses: dep, expected: exp, count: cnt, unitFee: uf);
          })
          .toList()
        ..sort((a, b) => a.className.compareTo(b.className));
      _expectedTotal = expectedTotal;
      final paidTotal = sum;
      _remainingTotal = (expectedTotal - paidTotal).clamp(0, 1e15);
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
          const SizedBox(height: 12),
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
                      title: 'Montant attendu (' + (_year.isEmpty ? '-' : _year) + ')',
                      value: _loading ? '...' : _formatCurrency(_expectedTotal),
                      color: const Color(0xFF0EA5E9))),
                  const SizedBox(width: 12),
                  Expanded(child: _infoCard(context,
                      title: 'Reste à payer',
                      value: _loading ? '...' : _formatCurrency(_remainingTotal),
                      color: const Color(0xFFF59E0B))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildPerClassSection(context),
          const SizedBox(height: 16),
          _buildExpensesCard(context),
        ],
      ),
    );
  }

  Widget _buildPerClassSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
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
                Text(
                  'Par classe (${_year.isEmpty ? '-' : _year})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: 'Rechercher une classe...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _classSearchQuery = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _classSortKey,
                    items: const [
                      DropdownMenuItem(value: 'classe', child: Text('Tri: Classe')),
                      DropdownMenuItem(value: 'reste', child: Text('Tri: Reste')),
                      DropdownMenuItem(value: 'solde', child: Text('Tri: Solde net')),
                      DropdownMenuItem(value: 'encaissements', child: Text('Tri: Encaissements')),
                      DropdownMenuItem(value: 'depenses', child: Text('Tri: Dépenses')),
                      DropdownMenuItem(value: 'attendu', child: Text('Tri: Attendu')),
                    ],
                    onChanged: (v) => setState(() => _classSortKey = v ?? 'classe'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _exportPerClassToPdf,
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                    label: const Text('Exporter PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _exportPerClassToExcel,
                    icon: const Icon(Icons.grid_on, color: Colors.white, size: 18),
                    label: const Text('Exporter Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 12),
            if (isDesktop)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _filteredSortedPerClass().isEmpty
                    ? [Text('Aucune donnée pour cette année.', style: theme.textTheme.bodyMedium)]
                    : _filteredSortedPerClass().map((s) => _classFinanceCard(context, s)).toList(),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Classe')),
                    DataColumn(label: Text('Encaissements')),
                    DataColumn(label: Text('Dépenses')),
                    DataColumn(label: Text('Solde net')),
                    DataColumn(label: Text('Effectif')),
                    DataColumn(label: Text('Frais unit.')),
                    DataColumn(label: Text('Attendu')),
                    DataColumn(label: Text('Reste')),
                  ],
                  rows: _filteredSortedPerClass()
                      .map(
                        (s) => DataRow(
                          cells: [
                            DataCell(Text(s.className)),
                            DataCell(Text(_formatCurrency(s.payments))),
                            DataCell(Text(_formatCurrency(s.expenses))),
                            DataCell(Text(
                              _formatCurrency(s.net),
                              style: TextStyle(
                                color: s.net >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                fontWeight: FontWeight.w600,
                              ),
                            )),
                            DataCell(Text(s.count.toString())),
                            DataCell(Text(_formatCurrency(s.unitFee))),
                            DataCell(Text(_formatCurrency(s.expected))),
                            DataCell(Text(_formatCurrency(s.remaining))),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_ClassFinance> _filteredSortedPerClass() {
    var list = _perClassFinance;
    if (_classSearchQuery.isNotEmpty) {
      final q = _classSearchQuery.toLowerCase();
      list = list.where((e) => e.className.toLowerCase().contains(q)).toList();
    }
    int cmp(double a, double b) => b.compareTo(a); // desc by default for numeric
    switch (_classSortKey) {
      case 'reste':
        list.sort((a, b) => cmp(a.remaining, b.remaining));
        break;
      case 'solde':
        list.sort((a, b) => cmp(a.net, b.net));
        break;
      case 'encaissements':
        list.sort((a, b) => cmp(a.payments, b.payments));
        break;
      case 'depenses':
        list.sort((a, b) => cmp(a.expenses, b.expenses));
        break;
      case 'attendu':
        list.sort((a, b) => cmp(a.expected, b.expected));
        break;
      case 'classe':
      default:
        list.sort((a, b) => a.className.compareTo(b.className));
    }
    return list;
  }

  Future<void> _exportPerClassToPdf() async {
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final pdf = pw.Document();
    final title = 'Récapitulatif par classe - Année ${selectedYear}';
    final formatter = NumberFormat('#,##0 FCFA', 'fr_FR');
    final schoolInfo = await _db.getSchoolInfo();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final list = _filteredSortedPerClass();
    double tPay = 0, tDep = 0, tNet = 0, tExp = 0, tRem = 0; int tCnt = 0;
    for (final s in list) {
      tPay += s.payments;
      tDep += s.expenses;
      tNet += s.net;
      tExp += s.expected;
      tRem += s.remaining;
      tCnt += s.count;
    }
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) {
          return [
            pw.Stack(children: [
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
                  // Bandeau administratif léger
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if ((schoolInfo?.ministry ?? '').isNotEmpty)
                              pw.Text((schoolInfo!.ministry!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                            if ((schoolInfo?.educationDirection ?? '').isNotEmpty)
                              pw.Text((schoolInfo!.educationDirection!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                            if ((schoolInfo?.inspection ?? '').isNotEmpty)
                              pw.Text((schoolInfo!.inspection!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            if ((schoolInfo?.republic ?? '').isNotEmpty)
                              pw.Text((schoolInfo!.republic!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8)),
                            if ((schoolInfo?.republicMotto ?? '').isNotEmpty)
                              pw.Text((schoolInfo!.republicMotto!).toUpperCase(), style: pw.TextStyle(font: times, fontSize: 8, fontStyle: pw.FontStyle.italic)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  // Titre centré avec logo au-dessus
                  pw.Center(
                    child: pw.Column(
                      children: [
                        if (schoolInfo?.logoPath != null && File(schoolInfo!.logoPath!).existsSync())
                          pw.Container(
                            height: 46,
                            width: 46,
                            margin: const pw.EdgeInsets.only(bottom: 4),
                            child: pw.Image(
                              pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        pw.Text(
                          (schoolInfo?.name ?? 'Établissement').toUpperCase(),
                          style: pw.TextStyle(font: timesBold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Text(title, style: pw.TextStyle(font: timesBold, fontSize: 14, color: PdfColors.white)),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Table.fromTextArray(
                    headers: ['Classe', 'Encaissements', 'Dépenses', 'Solde net', 'Effectif', 'Frais unit.', 'Attendu', 'Reste'],
                    data: list.map((s) => [
                      s.className,
                      formatter.format(s.payments),
                      formatter.format(s.expenses),
                      formatter.format(s.net),
                      s.count.toString(),
                      formatter.format(s.unitFee),
                      formatter.format(s.expected),
                      formatter.format(s.remaining),
                    ]).toList(),
                    headerStyle: pw.TextStyle(font: timesBold, fontSize: 10),
                    cellStyle: pw.TextStyle(font: times, fontSize: 9),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    cellAlignment: pw.Alignment.centerLeft,
                  ),
                  pw.SizedBox(height: 10),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        'Totaux - Enc.: ${formatter.format(tPay)}   Dép.: ${formatter.format(tDep)}   Solde: ${formatter.format(tNet)}   Effectif: ${tCnt}   Attendu: ${formatter.format(tExp)}   Reste: ${formatter.format(tRem)}',
                        style: pw.TextStyle(font: timesBold, fontSize: 10),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 14),
                  // Signature & cachet
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(children: [
                              pw.Text('Fait à : ', style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                              pw.Text((schoolInfo?.address ?? '').isNotEmpty ? schoolInfo!.address : '__________________________', style: pw.TextStyle(font: times, fontSize: 10)),
                            ]),
                            pw.SizedBox(height: 2),
                            pw.Row(children: [
                              pw.Text('Le : ', style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                              pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now()), style: pw.TextStyle(font: times, fontSize: 10)),
                            ]),
                            pw.SizedBox(height: 18),
                            pw.Text('Signature du responsable', style: pw.TextStyle(font: times, fontSize: 10)),
                            pw.SizedBox(height: 28),
                            pw.Container(width: 160, height: 0.8, color: PdfColors.grey400),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 24),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("Cachet et signature de l'établissement", style: pw.TextStyle(font: times, fontSize: 10)),
                            pw.SizedBox(height: 56),
                            pw.Container(width: 200, height: 0.8, color: PdfColors.grey400),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ]),
          ];
        },
      ),
    );
    final fileName = 'finances_par_classe_${selectedYear.replaceAll('/', '_')}.pdf';
    final file = File('$directory/$fileName');
    await file.writeAsBytes(await pdf.save());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF exporté: $fileName')),
      );
    }
    await OpenFile.open(file.path);
  }

  Future<void> _exportPerClassToExcel() async {
    final selectedYear = _selectedYearFilter ?? await getCurrentAcademicYear();
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return;
    final excel = Excel.createExcel();
    final sheet = excel['ParClasse'];
    sheet.appendRow([
      TextCellValue('Classe'),
      TextCellValue('Encaissements'),
      TextCellValue('Dépenses'),
      TextCellValue('Solde net'),
      TextCellValue('Effectif'),
      TextCellValue('Frais unitaire'),
      TextCellValue('Attendu'),
      TextCellValue('Reste'),
    ]);
    double tPay = 0, tDep = 0, tNet = 0, tExp = 0, tRem = 0; int tCnt = 0;
    for (final s in _filteredSortedPerClass()) {
      tPay += s.payments;
      tDep += s.expenses;
      tNet += s.net;
      tExp += s.expected;
      tRem += s.remaining;
      tCnt += s.count;
      sheet.appendRow([
        TextCellValue(s.className),
        DoubleCellValue(s.payments),
        DoubleCellValue(s.expenses),
        DoubleCellValue(s.net),
        IntCellValue(s.count),
        DoubleCellValue(s.unitFee),
        DoubleCellValue(s.expected),
        DoubleCellValue(s.remaining),
      ]);
    }
    sheet.appendRow([
      TextCellValue('TOTALS'),
      DoubleCellValue(tPay),
      DoubleCellValue(tDep),
      DoubleCellValue(tNet),
      IntCellValue(tCnt),
      TextCellValue(''),
      DoubleCellValue(tExp),
      DoubleCellValue(tRem),
    ]);
    final fileName = 'finances_par_classe_${selectedYear.replaceAll('/', '_')}.xlsx';
    final bytes = excel.encode();
    if (bytes != null) {
      final file = File('$directory/$fileName');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel exporté: $fileName')),
        );
      }
      await OpenFile.open(file.path);
    }
  }

  Widget _classFinanceCard(BuildContext context, _ClassFinance s) {
    final theme = Theme.of(context);
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(color: theme.shadowColor.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    s.className,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (s.net >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEE2E2)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    s.net >= 0 ? 'Positif' : 'Négatif',
                    style: TextStyle(
                      color: s.net >= 0 ? const Color(0xFF065F46) : const Color(0xFF7F1D1D),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.arrow_downward_rounded, color: const Color(0xFF10B981), size: 18),
                const SizedBox(width: 6),
                Text('Encaissements:', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                Text(
                  _formatCurrency(s.payments),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.arrow_upward_rounded, color: const Color(0xFFEF4444), size: 18),
                const SizedBox(width: 6),
                Text('Dépenses:', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                Text(
                  _formatCurrency(s.expenses),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: const Color(0xFF3B82F6), size: 18),
                const SizedBox(width: 6),
                Text('Solde net:', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                Text(
                  _formatCurrency(s.net),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: s.net >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.people_alt_outlined, color: const Color(0xFF64748B), size: 18),
                const SizedBox(width: 6),
                Text('Effectif:', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                Text(
                  s.count.toString(),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.attach_money, color: const Color(0xFF64748B), size: 18),
                const SizedBox(width: 6),
                Text('Frais unit.:', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                Text(
                  _formatCurrency(s.unitFee),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.assignment_turned_in_outlined, color: const Color(0xFF0EA5E9), size: 18),
                const SizedBox(width: 6),
                Text('Attendu:', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                Text(
                  _formatCurrency(s.expected),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.pending_actions_outlined, color: const Color(0xFFF59E0B), size: 18),
                const SizedBox(width: 6),
                Text('Reste:', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                Text(
                  _formatCurrency(s.remaining),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800,
                      color: s.remaining > 0 ? const Color(0xFFF59E0B) : theme.textTheme.bodyMedium?.color),
                ),
              ],
            ),
          ],
        ),
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

class _ClassFinance {
  final String className;
  final double payments;
  final double expenses;
  final double expected;
  final int count;
  final double unitFee;
  const _ClassFinance({
    required this.className,
    required this.payments,
    required this.expenses,
    required this.expected,
    required this.count,
    required this.unitFee,
  });
  double get net => payments - expenses;
  double get remaining => (expected - payments) < 0 ? 0 : (expected - payments);
}
