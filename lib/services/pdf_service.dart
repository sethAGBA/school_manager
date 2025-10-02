import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:school_manager/models/payment.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/school_info.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/category.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'package:school_manager/services/database_service.dart';

class PdfService {
  /// Helper method pour formater les dates
  static String _formatDate(String dateString) {
    if (dateString.isEmpty) return 'Non renseigné';
    
    try {
      // Essayer de parser la date dans différents formats
      DateTime? date;
      
      // Format ISO (2024-01-15)
      if (dateString.contains('-') && dateString.length >= 10) {
        date = DateTime.tryParse(dateString);
      }
      // Format français (15/01/2024)
      else if (dateString.contains('/')) {
        final parts = dateString.split('/');
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final year = int.tryParse(parts[2]);
          if (day != null && month != null && year != null) {
            date = DateTime(year, month, day);
          }
        }
      }
      
      if (date != null) {
        return DateFormat('dd/MM/yyyy').format(date);
      }
    } catch (e) {
      // En cas d'erreur, retourner la chaîne originale
    }
    
    return dateString;
  }

  /// Génère un PDF de reçu de paiement et retourne les bytes (pour aperçu ou impression)
  static Future<List<int>> generatePaymentReceiptPdf({
    required Payment currentPayment,
    required List<Payment> allPayments,
    required Student student,
    required SchoolInfo schoolInfo,
    required Class studentClass,
    required double totalPaid,
    required double totalDue,
  }) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0 FCFA', 'fr_FR');
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primaryColor = PdfColor.fromHex('#4F46E5');
    final secondaryColor = PdfColor.fromHex('#6B7280');
    final lightBgColor = PdfColor.fromHex('#F3F4F6');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final double remainingBalance = totalDue - totalPaid;
          return pw.Stack(children: [
            if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
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
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
              // --- En-tête ---
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: lightBgColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
                      pw.Image(
                        pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                        height: 60,
                        width: 60,
                      ),
                    if (schoolInfo.logoPath != null) pw.SizedBox(width: 20),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            schoolInfo.name,
                            style: pw.TextStyle(font: timesBold, fontSize: 20, color: primaryColor, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(schoolInfo.address, style: pw.TextStyle(font: times, fontSize: 10, color: secondaryColor)),
                          pw.SizedBox(height: 2),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              if ((schoolInfo.email ?? '').isNotEmpty)
                                pw.Text('Email : ${schoolInfo.email}', style: pw.TextStyle(font: times, fontSize: 10, color: secondaryColor)),
                              if ((schoolInfo.website ?? '').isNotEmpty)
                                pw.Text('Site web : ${schoolInfo.website}', style: pw.TextStyle(font: times, fontSize: 10, color: secondaryColor)),
                              if ((schoolInfo.telephone ?? '').isNotEmpty)
                                pw.Text('Téléphone : ${schoolInfo.telephone}', style: pw.TextStyle(font: times, fontSize: 10, color: secondaryColor)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('REÇU DE PAIEMENT', style: pw.TextStyle(font: timesBold, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('Reçu N°: ${currentPayment.id ?? currentPayment.date.hashCode}', style: pw.TextStyle(font: times, fontSize: 10)),
                        pw.Text('Date: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(currentPayment.date))}', style: pw.TextStyle(font: times, fontSize: 10)),
                        pw.Text('Année: ${studentClass.academicYear}', style: pw.TextStyle(font: times, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // --- Informations sur l'élève ---
              pw.Text('Reçu de :', style: pw.TextStyle(font: timesBold, fontSize: 14, color: primaryColor)),
              pw.Divider(color: lightBgColor, thickness: 2),
              pw.SizedBox(height: 0),
              pw.Row(
                children: [
                  pw.Expanded(flex: 2, child: pw.Text('Nom de l\'élève:', style: pw.TextStyle(font: timesBold))),
                  pw.Expanded(flex: 3, child: pw.Text(student.name, style: pw.TextStyle(font: times))),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(flex: 2, child: pw.Text('Classe:', style: pw.TextStyle(font: timesBold))),
                  pw.Expanded(flex: 3, child: pw.Text(student.className, style: pw.TextStyle(font: times))),
                ],
              ),
              pw.SizedBox(height: 30),

              // --- Détails du paiement actuel ---
              pw.Text('Historique des transactions', style: pw.TextStyle(font: timesBold, fontSize: 14, color: primaryColor)),
              pw.Table(
                border: pw.TableBorder.all(color: lightBgColor, width: 1.5),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: lightBgColor),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Date', style: pw.TextStyle(font: timesBold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Description', style: pw.TextStyle(font: timesBold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Montant', style: pw.TextStyle(font: timesBold), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  ...allPayments.map((payment) => pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(payment.date)), style: pw.TextStyle(font: times))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(payment.comment ?? 'Paiement frais de scolarité', style: pw.TextStyle(font: times))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(formatter.format(payment.amount), style: pw.TextStyle(font: times), textAlign: pw.TextAlign.right)),
                    ],
                  )),
                ],
              ),
              if (currentPayment.isCancelled)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text('LE DERNIER PAIEMENT A ÉTÉ ANNULÉ', style: pw.TextStyle(font: timesBold, color: PdfColors.red, fontWeight: pw.FontWeight.bold, fontSize: 14), textAlign: pw.TextAlign.center),
                ),
              pw.SizedBox(height: 30),

              // --- Résumé financier ---
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: lightBgColor, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Résumé Financier', style: pw.TextStyle(font: timesBold, fontSize: 14, color: primaryColor)),
                        pw.SizedBox(height: 10),
                        _buildSummaryRow('Total des Frais de Scolarité:', formatter.format(totalDue), times, timesBold),
                        _buildSummaryRow('Montant Total Payé:', formatter.format(totalPaid), times, timesBold),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: remainingBalance > 0 ? PdfColors.amber50 : PdfColors.green50,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text('Solde Restant', style: pw.TextStyle(font: timesBold, fontSize: 12)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            formatter.format(remainingBalance),
                            style: pw.TextStyle(font: timesBold, fontSize: 18, fontWeight: pw.FontWeight.bold, color: remainingBalance > 0 ? PdfColors.amber700 : PdfColors.green700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              // --- Pied de page ---
              pw.Divider(color: lightBgColor, thickness: 1),
              // (Aucune photo ici pour le reçu)
              pw.Text('Merci pour votre paiement.', style: pw.TextStyle(font: times, fontStyle: pw.FontStyle.italic, color: secondaryColor), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 16),
              pw.Text('Signature et Cachet de l\'établissement', style: pw.TextStyle(font: times, color: secondaryColor), textAlign: pw.TextAlign.right),
              pw.SizedBox(height: 40),
              ],
            ),
          ]);
        },
      ),
    );
    return pdf.save();
  }

  static pw.Widget _buildSummaryRow(String title, String value, pw.Font font, pw.Font fontBold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
      child: pw.Row(
        children: [
          pw.Text(title, style: pw.TextStyle(font: font, fontSize: 11)),
          pw.SizedBox(width: 10),
          pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  /// Sauvegarde le PDF de reçu de paiement dans le dossier documents et retourne le fichier
  static Future<File> savePaymentReceiptPdf({
    required Payment currentPayment,
    required List<Payment> allPayments,
    required Student student,
    required SchoolInfo schoolInfo,
    required Class studentClass,
    required double totalPaid,
    required double totalDue,
  }) async {
    final bytes = await generatePaymentReceiptPdf(
      currentPayment: currentPayment,
      allPayments: allPayments,
      student: student,
      schoolInfo: schoolInfo,
      studentClass: studentClass,
      totalPaid: totalPaid,
      totalDue: totalDue,
    );
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/recu_paiement_${student.id}_${currentPayment.id ?? DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Génère un PDF tabulaire de la liste des paiements (export)
  static Future<List<int>> exportPaymentsListPdf({
    required List<Map<String, dynamic>> rows,
  }) async {
    final pdf = pw.Document();
    final formatter = NumberFormat('#,##0.00', 'fr_FR');
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final dbService = DatabaseService();
    final schoolInfo = await dbService.getSchoolInfo();
    final currentAcademicYear = await getCurrentAcademicYear();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // En-tête administratif (Ministère / République / Devise + Inspection / Direction)
            if (schoolInfo != null) ...[
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: ((schoolInfo!.ministry ?? '').isNotEmpty)
                        ? pw.Text(
                            (schoolInfo!.ministry ?? '').toUpperCase(),
                            style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.blueGrey800),
                          )
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          ((schoolInfo!.republic ?? 'RÉPUBLIQUE').toUpperCase()),
                          style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.blueGrey800),
                        ),
                        if ((schoolInfo!.republicMotto ?? '').isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: pw.Text(
                              schoolInfo!.republicMotto!,
                              style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.blueGrey700, fontStyle: pw.FontStyle.italic),
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
                        ? pw.Text('Inspection: ${schoolInfo!.inspection}', style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.blueGrey700))
                        : pw.SizedBox(),
                  ),
                  pw.Expanded(
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: ((schoolInfo!.educationDirection ?? '').isNotEmpty)
                          ? pw.Text("Direction de l'enseignement: ${schoolInfo!.educationDirection}", style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.blueGrey700))
                          : pw.SizedBox(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
            ],
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (schoolInfo?.logoPath != null && File(schoolInfo!.logoPath!).existsSync())
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(
                        pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                        width: 50,
                        height: 50,
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(schoolInfo?.name ?? 'Établissement', style: pw.TextStyle(font: timesBold, fontSize: 16)),
                        pw.Text(schoolInfo?.address ?? '', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.blueGrey800)),
                        pw.SizedBox(height: 2),
                        pw.Text('Année académique: $currentAcademicYear', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.blueGrey800)),
                        pw.SizedBox(height: 4),
                        if ((schoolInfo?.email ?? '').isNotEmpty)
                          pw.Text('Email : ${schoolInfo!.email}', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.blueGrey800)),
                        if ((schoolInfo?.website ?? '').isNotEmpty)
                          pw.Text('Site web : ${schoolInfo!.website}', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.blueGrey800)),
                        if ((schoolInfo?.telephone ?? '').isNotEmpty)
                          pw.Text('Téléphone : ${schoolInfo!.telephone}', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.blueGrey800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text('Export des paiements', style: pw.TextStyle(font: timesBold, fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              cellStyle: pw.TextStyle(font: times, fontSize: 11),
              headerStyle: pw.TextStyle(font: timesBold, fontSize: 12, fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              headers: [
                'Nom', 'Classe', 'Année', 'Montant payé', 'Date', 'Statut', 'Commentaire'
              ],
              data: rows.map((row) {
                final student = row['student'];
                final payment = row['payment'];
                final classe = row['classe'];
                final montantMax = (classe?.fraisEcole ?? 0) + (classe?.fraisCotisationParallele ?? 0);
                final totalPaid = row['totalPaid'] ?? 0.0;
                String statut;
                if (montantMax > 0 && totalPaid >= montantMax) {
                  statut = 'Payé';
                } else if (payment != null && totalPaid > 0) {
                  statut = 'En attente';
                } else {
                  statut = 'Impayé';
                }
                return [
                  student.name,
                  student.className,
                  classe?.academicYear ?? '',
                  formatter.format(payment?.amount ?? 0),
                  payment != null ? payment.date.replaceFirst('T', ' ').substring(0, 16) : '',
                  statut,
                  payment?.comment ?? '',
                ];
              }).toList(),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerLeft,
                5: pw.Alignment.center,
                6: pw.Alignment.centerLeft,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FlexColumnWidth(1.2),
                6: const pw.FlexColumnWidth(2),
              },
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF tabulaire de la liste des élèves d'une classe (export)
  static Future<List<int>> exportStudentsListPdf({
    required List<Map<String, dynamic>> students,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');
    final success = PdfColor.fromHex('#10B981');
    final warning = PdfColor.fromHex('#F59E0B');
    
    // Style de base avec fallback
    final baseTextStyle = pw.TextStyle(font: times, fontSize: 9);
    final baseBoldStyle = pw.TextStyle(font: timesBold, fontSize: 9, fontWeight: pw.FontWeight.bold);

    // Trie par nom
    final sorted = List<Map<String, dynamic>>.from(students)
      ..sort((a, b) => (a['student'].name as String).compareTo(b['student'].name as String));

    // Récupération des informations de l'école
    final dbService = DatabaseService();
    final schoolInfo = await dbService.getSchoolInfo();
    final currentAcademicYear = await getCurrentAcademicYear();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Stack(
            children: [
              // Logo en filigrane en arrière-plan
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
              // Contenu principal
              pw.Column(
                children: [
                  // En-tête administratif
                  if (schoolInfo != null) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: ((schoolInfo!.ministry ?? '').isNotEmpty)
                              ? pw.Text((schoolInfo!.ministry ?? '').toUpperCase(), style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary))
                              : pw.SizedBox(),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text(((schoolInfo!.republic ?? 'RÉPUBLIQUE').toUpperCase()), style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                              if ((schoolInfo!.republicMotto ?? '').isNotEmpty)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(top: 2),
                                  child: pw.Text(schoolInfo!.republicMotto!, style: pw.TextStyle(font: times, fontSize: 9, color: primary, fontStyle: pw.FontStyle.italic), textAlign: pw.TextAlign.right),
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
                              ? pw.Text('Inspection: ${schoolInfo!.inspection}', style: pw.TextStyle(font: times, fontSize: 9, color: primary))
                              : pw.SizedBox(),
                        ),
                        pw.Expanded(
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: ((schoolInfo!.educationDirection ?? '').isNotEmpty)
                                ? pw.Text("Direction de l'enseignement: ${schoolInfo!.educationDirection}", style: pw.TextStyle(font: times, fontSize: 9, color: primary))
                                : pw.SizedBox(),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                  ],
                  // Header avec logo et informations de l'école
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
                          schoolInfo?.name ?? 'École',
                          style: pw.TextStyle(font: timesBold, fontSize: 20, color: accent, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          schoolInfo?.address ?? '',
                          style: pw.TextStyle(font: times, fontSize: 11, color: primary),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Année académique: $currentAcademicYear  •  Généré le: ' + DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                          style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                        ),
                        if ((schoolInfo?.email ?? '').isNotEmpty)
                          pw.Text('Email : ${schoolInfo!.email}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        if ((schoolInfo?.website ?? '').isNotEmpty)
                          pw.Text('Site web : ${schoolInfo!.website}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        if ((schoolInfo?.telephone ?? '').isNotEmpty)
                          pw.Text('Téléphone : ${schoolInfo!.telephone}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                      ],
                    ),
                  ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  // Titre principal
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'Liste des élèves de la classe de ${sorted.isNotEmpty ? sorted.first['classe']?.name ?? 'classe' : 'classe'}',
                      style: pw.TextStyle(font: timesBold, fontSize: 18, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Statistiques rapides
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        pw.Column(
                          children: [
                            pw.Text(
                              '${sorted.length}',
                              style: pw.TextStyle(font: timesBold, fontSize: 16, color: accent, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.Text(
                              'Total élèves',
                              style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                            ),
                          ],
                        ),
                        pw.Container(
                          width: 1,
                          height: 30,
                          color: PdfColors.grey400,
                        ),
                        pw.Column(
                          children: [
                            pw.Text(
                              '${sorted.where((s) => s['student'].gender == 'M').length}',
                              style: pw.TextStyle(font: timesBold, fontSize: 16, color: success, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.Text(
                              'Garçons',
                              style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                            ),
                          ],
                        ),
                        pw.Container(
                          width: 1,
                          height: 30,
                          color: PdfColors.grey400,
                        ),
                        pw.Column(
                          children: [
                            pw.Text(
                              '${sorted.where((s) => s['student'].gender == 'F').length}',
                              style: pw.TextStyle(font: timesBold, fontSize: 16, color: warning, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.Text(
                              'Filles',
                              style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  // Tableau simplifié pour liste de présence
                  pw.Table.fromTextArray(
                    cellStyle: pw.TextStyle(font: times, fontSize: 11),
                    headerStyle: pw.TextStyle(font: timesBold, fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    headerDecoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    headers: [
                      'N°', 'Nom complet', 'Sexe', 'Statut', 'Présence'
                    ],
                    data: List.generate(sorted.length, (i) {
                      final student = sorted[i]['student'];
                      
                      // Prendre la première lettre du statut en majuscule
                      String statusLetter = '';
                      if (student.status != null && student.status!.isNotEmpty) {
                        statusLetter = student.status!.substring(0, 1).toUpperCase();
                      }
                      
                      return [
                        (i + 1).toString(),
                        student.name,
                        student.gender == 'M' ? 'M' : 'F',
                        statusLetter,
                        '', // Colonne vide pour cocher la présence
                      ];
                    }),
                    cellAlignment: pw.Alignment.centerLeft,
                    headerAlignments: {
                      0: pw.Alignment.center,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.center,
                      3: pw.Alignment.center,
                      4: pw.Alignment.center,
                    },
                    columnWidths: {
                      0: const pw.FlexColumnWidth(0.8),
                      1: const pw.FlexColumnWidth(3.5),
                      2: const pw.FlexColumnWidth(1.2),
                      3: const pw.FlexColumnWidth(1.5),
                      4: const pw.FlexColumnWidth(3.0),
                    },
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    cellPadding: const pw.EdgeInsets.all(8),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF de fiche profil individuelle pour un élève
  static Future<List<int>> exportStudentProfilePdf({
    required Student student,
    required Class? classe,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');
    final success = PdfColor.fromHex('#10B981');

    // Récupération des informations de l'école
    final dbService = DatabaseService();
    final schoolInfo = await dbService.getSchoolInfo();
    final currentAcademicYear = await getCurrentAcademicYear();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Stack(
            children: [
              // Logo en filigrane en arrière-plan
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
              // Contenu principal
              pw.Column(
                children: [
                  // Header avec logo et informations de l'école
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
                                schoolInfo?.name ?? 'École',
                                style: pw.TextStyle(font: timesBold, fontSize: 20, color: accent, fontWeight: pw.FontWeight.bold),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                schoolInfo?.address ?? '',
                                style: pw.TextStyle(font: times, fontSize: 11, color: primary),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                'Année académique: $currentAcademicYear  •  Généré le: ' + DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                                style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  // Titre principal avec photo
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Row(
                      children: [
                        // Photo de l'élève
                        if (student.photoPath != null && student.photoPath!.isNotEmpty && File(student.photoPath!).existsSync())
                          pw.Container(
                            width: 80,
                            height: 80,
                            decoration: pw.BoxDecoration(
                              borderRadius: pw.BorderRadius.circular(8),
                              border: pw.Border.all(color: PdfColors.white, width: 2),
                            ),
                            child: pw.ClipRRect(
                              child: pw.Image(
                                pw.MemoryImage(File(student.photoPath!).readAsBytesSync()),
                                fit: pw.BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          pw.Container(
                            width: 80,
                            height: 80,
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex('#E5E7EB'),
                              borderRadius: pw.BorderRadius.circular(8),
                              border: pw.Border.all(color: PdfColors.white, width: 2),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'PHOTO',
                                style: pw.TextStyle(
                                  font: timesBold, 
                                  fontSize: 10, 
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        pw.SizedBox(width: 16),
                        // Titre avec nom
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'FICHE ACADÉMIQUE',
                                style: pw.TextStyle(font: timesBold, fontSize: 16, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                student.name.toUpperCase(),
                                style: pw.TextStyle(font: timesBold, fontSize: 20, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  // Informations personnelles
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColors.grey200, width: 1),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'INFORMATIONS PERSONNELLES',
                          style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 12),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow('Nom complet', student.name, times, timesBold, primary),
                                  _buildInfoRow('Matricule', student.matricule ?? 'Non renseigné', times, timesBold, primary),
                                  _buildInfoRow('Sexe', student.gender == 'M' ? 'Masculin' : 'Féminin', times, timesBold, primary),
                                  _buildInfoRow('Date de naissance', _formatDate(student.dateOfBirth), times, timesBold, primary),
                                  _buildInfoRow('Statut', student.status, times, timesBold, primary),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 20),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow('Classe', student.className, times, timesBold, primary),
                                  _buildInfoRow('Année académique', student.academicYear, times, timesBold, primary),
                                  _buildInfoRow('Date d\'inscription', _formatDate(student.enrollmentDate), times, timesBold, primary),
                                  _buildInfoRow('Contact', student.contactNumber, times, timesBold, primary),
                                  _buildInfoRow('Email', student.email, times, timesBold, primary),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Adresse
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColors.grey200, width: 1),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ADRESSE',
                          style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          student.address,
                          style: pw.TextStyle(font: times, fontSize: 12, color: primary),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Informations du tuteur
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColors.grey200, width: 1),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'INFORMATIONS DU TUTEUR',
                          style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 12),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow('Nom du tuteur', student.guardianName, times, timesBold, primary),
                                  _buildInfoRow('Contact tuteur', student.guardianContact, times, timesBold, primary),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 20),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow('Contact urgence', student.emergencyContact, times, timesBold, primary),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Informations médicales
                  if (student.medicalInfo != null && student.medicalInfo!.isNotEmpty)
                    pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColors.grey200, width: 1),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'INFORMATIONS MÉDICALES',
                            style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(
                            student.medicalInfo!,
                            style: pw.TextStyle(font: times, fontSize: 12, color: primary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  /// Helper method pour construire une ligne d'information
  static pw.Widget _buildInfoRow(String label, String value, pw.Font font, pw.Font fontBold, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(font: fontBold, fontSize: 11, color: color, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: font, fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Génère un PDF tabulaire de la liste des classes (export)
  static Future<List<int>> exportClassesListPdf({required List<Class> classes}) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Liste des classes', style: pw.TextStyle(font: timesBold, fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              cellStyle: pw.TextStyle(font: times, fontSize: 11),
              headerStyle: pw.TextStyle(font: timesBold, fontSize: 12, fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              headers: ['Nom', 'Année', 'Titulaire', 'Frais école', 'Frais cotisation parallèle'],
              data: classes.map((c) => [
                c.name,
                c.academicYear,
                c.titulaire ?? '',
                c.fraisEcole?.toString() ?? '',
                c.fraisCotisationParallele?.toString() ?? '',
              ]).toList(),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF fidèle du bulletin scolaire d'un élève
  static Future<List<int>> generateReportCardPdf({
    required Student student,
    required SchoolInfo schoolInfo,
    required List<Grade> grades,
    required Map<String, String> professeurs,
    required Map<String, String> appreciations,
    required Map<String, String> moyennesClasse,
    required String appreciationGenerale,
    required String decision,
    String recommandations = '',
    String forces = '',
    String pointsADevelopper = '',
    String sanctions = '',
    int attendanceJustifiee = 0,
    int attendanceInjustifiee = 0,
    int retards = 0,
    double presencePercent = 0.0,
    String conduite = '',
    required String telEtab,
    required String mailEtab,
    required String webEtab,
    String titulaire = '',
    required List<String> subjects,
    required List<double?> moyennesParPeriode,
    required double moyenneGenerale,
    required int rang,
    required int nbEleves,
    bool exaequo = false,
    required String mention,
    required List<String> allTerms,
    required String periodLabel,
    required String selectedTerm,
    required String academicYear,
    required String faitA,
    required String leDate,
    required bool isLandscape,
    String niveau = '',
    double? moyenneGeneraleDeLaClasse,
    double? moyenneLaPlusForte,
    double? moyenneLaPlusFaible,
    double? moyenneAnnuelle,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final secondaryColor = PdfColors.blueGrey800;
    final mainColor = PdfColors.blue800;
    final tableHeaderBg = PdfColors.blue200;
    final tableHeaderText = PdfColors.white;
    final tableRowAlt = PdfColors.blue50;
    // Charger catégories et matières de la classe pour permettre un groupement par catégories
    final DatabaseService _db = DatabaseService();
    final List<Category> _pdfCategories = await _db.getCategories();
    final List<Course> _pdfClassCourses = await _db.getCoursesForClass(student.className, academicYear);
    final List<Grade> classPeriodGrades = await _db.getAllGradesForPeriod(
      className: student.className,
      academicYear: academicYear,
      term: selectedTerm,
    );
    // Charger coefficients de matière au niveau de la classe; fallback sur appreciations (archive incluse)
    Map<String, double> subjectWeights = await _db.getClassSubjectCoefficients(student.className, academicYear);
    if (subjectWeights.isEmpty) {
      List<Map<String, dynamic>> subjAppsRows = await _db.getSubjectAppreciations(
        studentId: student.id,
        className: student.className,
        academicYear: academicYear,
        term: selectedTerm,
      );
      if (subjAppsRows.isEmpty) {
        subjAppsRows = await _db.getSubjectAppreciationsArchiveByKeys(
          studentId: student.id,
          className: student.className,
          academicYear: academicYear,
          term: selectedTerm,
        );
      }
      subjectWeights = {
        for (final r in subjAppsRows)
          if ((r['subject'] as String?) != null && r['coefficient'] != null)
            (r['subject'] as String): (r['coefficient'] as num).toDouble()
      };
    }
    // Pré-calcul du rang/eff. par période pour le tableau des moyennes par période
    final Map<String, Map<String, int>> rankPerTerm = {};
    final Map<String, double> nAnnualByStudent = {};
    final Map<String, double> cAnnualByStudent = {};
    const double epsRank = 0.001;
    for (final term in allTerms) {
      final gradesForTerm = await _db.getAllGradesForPeriod(
        className: student.className,
        academicYear: academicYear,
        term: term,
      );
      // Accumulate annual (inchangé)
      for (final g in gradesForTerm.where((g) => (g.type == 'Devoir' || g.type == 'Composition') && g.value != null && g.value != 0)) {
        if (g.maxValue > 0 && g.coefficient > 0) {
          nAnnualByStudent[g.studentId] = (nAnnualByStudent[g.studentId] ?? 0) + ((g.value / g.maxValue) * 20) * g.coefficient;
          cAnnualByStudent[g.studentId] = (cAnnualByStudent[g.studentId] ?? 0) + g.coefficient;
        }
      }
      // Classement pondéré par coefficients de matières
      final Set<String> studentIds = gradesForTerm.map((g) => g.studentId).toSet();
      final List<double> avgs = [];
      double myAvg = 0.0;
      for (final sid in studentIds) {
        double sumPoints = 0.0;
        double sumWeights = 0.0;
        for (final subject in subjects) {
          final sg = gradesForTerm.where((g) => g.studentId == sid && g.subject == subject && (g.type == 'Devoir' || g.type == 'Composition') && g.value != null && g.value != 0).toList();
          if (sg.isEmpty) continue;
          double n = 0.0;
          double c = 0.0;
          for (final g in sg) {
            if (g.maxValue > 0 && g.coefficient > 0) {
              n += ((g.value / g.maxValue) * 20) * g.coefficient;
              c += g.coefficient;
            }
          }
          final double moyMatiere = c > 0 ? (n / c) : 0.0;
          final double w = subjectWeights[subject] ?? c; // fallback si non défini
          if (w > 0) {
            sumPoints += moyMatiere * w;
            sumWeights += w;
          }
        }
        final double avg = sumWeights > 0 ? (sumPoints / sumWeights) : 0.0;
        avgs.add(avg);
        if (sid == student.id) myAvg = avg;
      }
      avgs.sort((a, b) => b.compareTo(a));
      final int nb = avgs.length;
      final int rank = 1 + avgs.where((v) => (v - myAvg) > epsRank).length;
      rankPerTerm[term] = {'rank': rank, 'nb': nb};
    }
    // Annual class average and rank for student
    double? moyenneAnnuelleClasseComputed;
    int? rangAnnuelComputed;
    if (nAnnualByStudent.isNotEmpty) {
      final List<double> annualAvgs = [];
      double myAnnual = 0.0;
      nAnnualByStudent.forEach((sid, n) {
        final c = cAnnualByStudent[sid] ?? 0.0;
        final avg = c > 0 ? (n / c) : 0.0;
        annualAvgs.add(avg);
        if (sid == student.id) myAnnual = avg;
      });
      if (annualAvgs.isNotEmpty) {
        moyenneAnnuelleClasseComputed = annualAvgs.reduce((a, b) => a + b) / annualAvgs.length;
        annualAvgs.sort((a, b) => b.compareTo(a));
        rangAnnuelComputed = 1 + annualAvgs.where((v) => (v - myAnnual) > epsRank).length;
      }
    }
    final now = DateTime.now();
    final prenom = student.name.split(' ').length > 1 ? student.name.split(' ').first : student.name;
    final nom = student.name.split(' ').length > 1 ? student.name.split(' ').sublist(1).join(' ') : '';
    final sexe = student.gender;
    // ---
    final PdfPageFormat _pageFormat = isLandscape ? PdfPageFormat(842, 595) : PdfPageFormat(595.28, 1000);
    final pw.PageTheme _pageTheme = pw.PageTheme(
      pageFormat: _pageFormat,
      // Réduit les marges pour gagner de l'espace vertical et éviter une 2e page
      margin: isLandscape ? const pw.EdgeInsets.all(12) : const pw.EdgeInsets.all(20),
      buildBackground: (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
          ? (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Opacity(
                  opacity: 0.05,
                  child: pw.Image(
                    pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                    fit: pw.BoxFit.cover,
                  ),
                ),
              )
          : null,
    );
    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme,
        build: (pw.Context context) {
          final int totalSubjects = subjects.length;
          final bool denseMode = totalSubjects > (isLandscape ? 22 : 16);
          final double smallFont = denseMode ? (isLandscape ? 5.0 : 5.5) : (isLandscape ? 6.0 : 6.8);
          final double baseFont = smallFont;
          final double headerFont = denseMode ? (isLandscape ? 8.5 : 10.0) : (isLandscape ? 9.5 : 14.0);
          final double spacing = denseMode ? (isLandscape ? 2 : 3) : (isLandscape ? 4 : 6);
          String _toOrdinalWord(int n) {
            switch (n) {
              case 1:
                return 'premier';
              case 2:
                return 'deuxième';
              case 3:
                return 'troisième';
              case 4:
                return 'quatrième';
              case 5:
                return 'cinquième';
              default:
                return '$nᵉ';
            }
          }
          String _buildBulletinSubtitle() {
            final String base = 'Bulletin du ';
            final String period = periodLabel.toLowerCase();
            final match = RegExp(r"(\d+)").firstMatch(selectedTerm);
            if (match != null) {
              final numStr = match.group(1);
              final idx = int.tryParse(numStr ?? '');
              if (idx != null) {
                return base + _toOrdinalWord(idx) + ' ' + period;
              }
            }
            if (selectedTerm.isNotEmpty) {
              return base + period + ' ' + selectedTerm.toLowerCase();
            }
            return base + period;
          }
          // Découpe un texte en 2 lignes équilibrées et en majuscules
          List<String> _splitTwoLines(String input) {
            final s = input.trim().toUpperCase();
            if (s.isEmpty) return [];
            final words = s.split(RegExp(r'\s+'));
            if (words.length <= 1) return [s];
            final totalLen = s.length;
            final target = totalLen ~/ 2;
            int bestIdx = 1;
            int bestDist = totalLen;
            int running = 0;
            for (int i = 0; i < words.length - 1; i++) {
              running += words[i].length + 1; // +space
              final dist = (running - target).abs();
              if (dist < bestDist) {
                bestDist = dist;
                bestIdx = i + 1;
              }
            }
            final first = words.sublist(0, bestIdx).join(' ');
            final second = words.sublist(bestIdx).join(' ');
            return [first, second];
          }
          final String bulletinSubtitle = _buildBulletinSubtitle();
          double _estimateTextWidth(String text, double fontSize) {
            if (text.isEmpty) return 0;
            // Approximate average glyph width factor for Times (safety tuned)
            return text.length * fontSize * 0.62;
          }
          return <pw.Widget>[
              // En-tête État: Ministère (gauche) / République + devise (droite)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 2,
                        child: (schoolInfo.ministry ?? '').isNotEmpty
                            ? () {
                                final parts = _splitTwoLines(schoolInfo.ministry ?? '');
                                if (parts.isEmpty) return pw.SizedBox();
                                final hasTwo = parts.length > 1;
                                // Taille de police de base
                                final baseFs = smallFont + 1;
                                // Largeur dispo approximative pour la colonne gauche
                                final margin = isLandscape ? 12.0 : 20.0;
                                final contentWidth = _pageFormat.width - 2 * margin;
                                // Calculer la largeur réellement allouée à la colonne gauche
                                // Les Expanded du header utilisent les flex: gauche=2, centre=3, droite=2
                                // On calcule la part = 2 / (2+3+2) = 2/7 pour que la largeur utilisée
                                // corresponde exactement à l'espace rendu et évite la troncation.
                                const double leftFlex = 2;
                                const double centerFlex = 3;
                                const double rightFlex = 2;
                                final double totalFlex = leftFlex + centerFlex + rightFlex;
                                final leftColWidth = contentWidth * (leftFlex / totalFlex);
                                // Ajuste la taille si nécessaire pour forcer 2 lignes sans wrap
                                double fs = baseFs;
                                double w1Base = _estimateTextWidth(parts[0], fs);
                                double w2Base = hasTwo ? _estimateTextWidth(parts[1], fs) : 0.0;
                                double maxBase = hasTwo ? math.max(w1Base, w2Base) : w1Base;
                                if (maxBase > leftColWidth) {
                                  final scale = leftColWidth / maxBase;
                                  fs = (fs * scale).clamp(5.0, baseFs);
                                  w1Base = _estimateTextWidth(parts[0], fs);
                                  w2Base = hasTwo ? _estimateTextWidth(parts[1], fs) : 0.0;
                                  maxBase = hasTwo ? math.max(w1Base, w2Base) : w1Base;
                                }
                                // Padding pour centrer la ligne la plus courte dans la largeur disponible
                                // On utilise explicitement leftColWidth (espace réel alloué) pour éviter
                                // que la seconde ligne soit tronquée : le container occupera toute la
                                // largeur disponible et le padding centre le texte à l'intérieur.
                                final availableW = leftColWidth;
                                double padFirst = 0;
                                double padSecond = 0;
                                if (hasTwo) {
                                  if (w2Base > w1Base) {
                                    padFirst = (availableW - w1Base) / 2;
                                    padSecond = 0;
                                  } else if (w1Base > w2Base) {
                                    padFirst = 0;
                                    padSecond = (availableW - w2Base) / 2;
                                  }
                                }
                                return pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  mainAxisSize: pw.MainAxisSize.min,
                                  children: [
                                    pw.Container(
                                      width: availableW,
                                      padding: pw.EdgeInsets.only(left: padFirst),
                                      child: pw.Text(
                                        parts[0],
                                        maxLines: 1,
                                        style: pw.TextStyle(font: timesBold, fontSize: fs, color: mainColor),
                                      ),
                                    ),
                                    if (hasTwo)
                                      pw.Container(
                                        width: availableW,
                                        padding: pw.EdgeInsets.only(left: padSecond),
                                        child: pw.Text(
                                          parts[1],
                                          maxLines: 1,
                                          style: pw.TextStyle(font: timesBold, fontSize: fs, color: mainColor),
                                        ),
                                      ),
                                    if ((schoolInfo.inspection ?? '').isNotEmpty) ...[
                                      pw.SizedBox(height: isLandscape ? 3 : 6),
                                      pw.Text(
                                        'Inspection: ${schoolInfo.inspection}',
                                        style: pw.TextStyle(font: times, fontSize: smallFont + 1, color: secondaryColor),
                                      ),
                                    ],
                                    // Photo élève en dessous de l'Inspection (si dispo)
                                    if (student.photoPath != null && student.photoPath!.isNotEmpty && File(student.photoPath!).existsSync()) ...[
                                      pw.SizedBox(height: 4),
                                      pw.Container(
                                        width: isLandscape ? 40 : 80,
                                        height: isLandscape ? 40 : 80,
                                        decoration: pw.BoxDecoration(
                                          borderRadius: pw.BorderRadius.circular(8),
                                          border: pw.Border.all(color: PdfColors.blue100, width: 1),
                                        ),
                                        child: pw.ClipRRect(
                                          child: pw.Image(
                                            pw.MemoryImage(File(student.photoPath!).readAsBytesSync()),
                                            fit: pw.BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              }()
                            : pw.SizedBox(),
                      ),
                      // Bloc central: logo + infos établissement
                      pw.Expanded(
                        flex: 3,
                        child: pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(bottom: 2),
                                child: pw.Image(
                                  pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                                  height: isLandscape ? 22 : 56,
                                ),
                              ),
                            pw.Text(
                              schoolInfo.name,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: timesBold, fontSize: headerFont, color: mainColor, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.SizedBox(height: isLandscape ? 1 : 2),
                            if ((schoolInfo.address).isNotEmpty)
                              pw.Text(
                                schoolInfo.address,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(font: times, fontSize: smallFont, color: secondaryColor),
                              ),
                            pw.SizedBox(height: 1),
                            // Année académique déplacée sous "Direction de l'enseignement" (colonne droite)
                          if (schoolInfo.director.isNotEmpty) ...[
                            // Masqué: affichage du proviseur / directeur (gardé en commentaire pour restauration ultérieure)
                            // pw.SizedBox(height: 1),
                            // pw.Text(
                            //   (niveau.toLowerCase().contains('lycée') ? 'Proviseur(e) : ' : 'Directeur(ice) : ') + schoolInfo.director,
                            //   textAlign: pw.TextAlign.center,
                            //   style: pw.TextStyle(font: times, fontSize: smallFont, color: secondaryColor),
                            // ),
                          ],
                          // Contacts condensés
                          if (mailEtab.isNotEmpty || webEtab.isNotEmpty || telEtab.isNotEmpty) ...[
                            pw.SizedBox(height: 1),
                            pw.Text(
                              [
                                if (mailEtab.isNotEmpty) 'Email: ' + mailEtab,
                                if (webEtab.isNotEmpty) 'Site: ' + webEtab,
                                if (telEtab.isNotEmpty) 'Tél: ' + telEtab,
                              ].join('  |  '),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: times, fontSize: smallFont, color: secondaryColor),
                            ),
                          ],
                          ],
                        ),
                      ),
                      // Colonne droite: République + devise
                      pw.Expanded(
                        flex: 2,
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Column(
                            mainAxisSize: pw.MainAxisSize.min,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text(
                                ((schoolInfo.republic ?? 'RÉPUBLIQUE').toUpperCase()),
                                style: pw.TextStyle(font: timesBold, fontSize: smallFont + 1, color: mainColor),
                              ),
                              if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(top: 2),
                                  child: pw.Text(
                                    schoolInfo.republicMotto!,
                                    style: pw.TextStyle(font: times, fontStyle: pw.FontStyle.italic, fontSize: smallFont, color: secondaryColor),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ),
                              if ((schoolInfo.educationDirection ?? '').isNotEmpty)
                                pw.Padding(
                                  padding: pw.EdgeInsets.only(top: isLandscape ? 3 : 6),
                                  child: pw.Text(
                                    "Direction de l'enseignement: ${schoolInfo.educationDirection}",
                                    style: pw.TextStyle(font: times, fontSize: smallFont + 1, color: secondaryColor),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ),
                              pw.Padding(
                                padding: pw.EdgeInsets.only(top: isLandscape ? 6 : 10),
                                child: pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: pw.BoxDecoration(
                                    color: PdfColors.blue50,
                                    borderRadius: pw.BorderRadius.circular(6),
                                    border: pw.Border.all(color: PdfColors.blue200, width: 1),
                                  ),
                                  child: pw.Text(
                                    'Année académique : $academicYear',
                                    style: pw.TextStyle(font: timesBold, fontSize: smallFont + 1, color: mainColor),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // (Inspection / Direction déjà affichées sous Ministère / République)
                ],
              ),
              pw.SizedBox(height: isLandscape ? 2 : 6),
              // (photo élève supprimée ici; elle est affichée sous Inspection)
              // Titre + photo (photo à droite, sous l'entête)
              pw.Stack(
                children: [
                  pw.Center(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'BULLETIN SCOLAIRE',
                          style: pw.TextStyle(font: timesBold, fontSize: headerFont, color: mainColor, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(bulletinSubtitle, style: pw.TextStyle(font: timesBold, fontSize: smallFont, color: secondaryColor)),
                        if ((schoolInfo.motto ?? '').isNotEmpty) ...[
                          pw.SizedBox(height: 6),
                          pw.Row(
                            children: [
                              pw.Expanded(child: pw.Divider(color: PdfColors.blue100, thickness: 1)),
                              pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                                child: pw.Text(
                                  schoolInfo.motto!,
                                  style: pw.TextStyle(font: times, fontStyle: pw.FontStyle.italic, fontSize: smallFont, color: secondaryColor),
                                ),
                              ),
                              pw.Expanded(child: pw.Divider(color: PdfColors.blue100, thickness: 1)),
                            ],
                          ),
                        ]
                      ],
                    ),
                  ),
                  // photo non affichée ici (déjà collée à la ligne "Année académique")
                ],
              ),
              pw.SizedBox(height: spacing),
              // Bloc élève
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: PdfColors.blue100),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Text('Nom : $nom', style: pw.TextStyle(font: timesBold, color: mainColor))),
                        pw.Expanded(child: pw.Text('Prénom : $prenom', style: pw.TextStyle(font: timesBold, color: mainColor))),
                        pw.Expanded(child: pw.Text('Sexe : $sexe', style: pw.TextStyle(font: timesBold, color: mainColor))),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Text('Date de naissance : ' + _formatDate(student.dateOfBirth), style: pw.TextStyle(font: timesBold, color: mainColor))),
                        pw.Expanded(child: pw.Text('Statut : ${student.status.isNotEmpty ? student.status : '-'}', style: pw.TextStyle(font: timesBold, color: mainColor))),
                        pw.Expanded(child: pw.SizedBox()),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: PdfColors.blue100),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Row(
                        children: [
                          pw.Text('Classe : ', style: pw.TextStyle(font: timesBold, color: mainColor)),
                          pw.Text(student.className, style: pw.TextStyle(font: times, color: secondaryColor)),
                        ],
                      ),
                    ),
                    pw.Row(children: [
                      pw.Text('Effectif : ', style: pw.TextStyle(font: timesBold, color: mainColor)),
                      pw.Text(nbEleves > 0 ? '$nbEleves' : '-', style: pw.TextStyle(font: times, color: secondaryColor)),
                    ]),
                  ],
                ),
              ),
              pw.SizedBox(height: spacing),
              // Tableau matières (groupé par catégories si disponibles)
              ...(() {
                // Map subject -> categoryId
                final Map<String, String?> subjectCat = {
                  for (final c in _pdfClassCourses) c.name: c.categoryId
                };
                // Regrouper à partir de la liste subjects passée
                final Map<String?, List<String>> grouped = {};
                for (final s in subjects) {
                  final catId = subjectCat[s];
                  grouped.putIfAbsent(catId, () => []).add(s);
                }
                final bool hasCategories = grouped.keys.any((k) => k != null);

                pw.Widget buildTableForSubjects(List<String> names, {bool showTotals = false}) {
                  double sumCoefficients = 0.0;
                  double sumPointsEleve = 0.0;
                  double sumPointsClasse = 0.0;

                  final List<pw.TableRow> rows = [];
                  rows.add(
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: tableHeaderBg),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Matière', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Sur', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Dev', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Comp', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Coef', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Moy Gen', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Moy Gen Coef', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Moy Cl', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Professeur(s)', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text('Appréciation prof.', style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: 9))),
                      ],
                    ),
                  );

                  for (final subject in names) {
                    final subjectGrades = grades.where((g) => g.subject == subject).toList();
                    final devoirs = subjectGrades.where((g) => g.type == 'Devoir').toList();
                    final compositions = subjectGrades.where((g) => g.type == 'Composition').toList();
                    final devoirNote = devoirs.isNotEmpty ? devoirs.first.value.toStringAsFixed(2) : '-';
                    final devoirSur = devoirs.isNotEmpty ? devoirs.first.maxValue.toStringAsFixed(2) : '-';
                    final compoNote = compositions.isNotEmpty ? compositions.first.value.toStringAsFixed(2) : '-';
                    final compoSur = compositions.isNotEmpty ? compositions.first.maxValue.toStringAsFixed(2) : '-';
                    double total = 0;
                    double totalCoeff = 0;
                    for (final g in [...devoirs, ...compositions]) {
                      if (g.maxValue > 0 && g.coefficient > 0) {
                        total += ((g.value / g.maxValue) * 20) * g.coefficient;
                        totalCoeff += g.coefficient;
                      }
                    }
                    final moyenneMatiere = (totalCoeff > 0) ? (total / totalCoeff) : 0.0;

                    final double subjectWeight = subjectWeights[subject] ?? totalCoeff;
                    sumCoefficients += subjectWeight;
                    final double moyGenCoef = (subjectGrades.isNotEmpty) ? (moyenneMatiere * subjectWeight) : 0.0;
                    if (subjectGrades.isNotEmpty) sumPointsEleve += moyGenCoef;
                    final mcText = (moyennesClasse[subject] ?? '').replaceAll(',', '.');
                    final mcVal = double.tryParse(mcText);
                    if (mcVal != null) sumPointsClasse += mcVal * subjectWeight;

                    rows.add(
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: PdfColors.white),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(subject, style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(devoirSur != '-' ? devoirSur : compoSur, style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(devoirNote, style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(compoNote, style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text((subjectWeights[subject] ?? totalCoeff) > 0 ? (subjectWeights[subject] ?? totalCoeff).toStringAsFixed(2) : '-', style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(subjectGrades.isNotEmpty ? moyenneMatiere.toStringAsFixed(2) : '-', style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(subjectGrades.isNotEmpty ? moyGenCoef.toStringAsFixed(2) : '-', style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(moyennesClasse[subject] ?? '-', style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(professeurs[subject] ?? '-', style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                          pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(appreciations[subject] ?? '-', style: pw.TextStyle(color: secondaryColor, fontSize: 8))),
                        ],
                      ),
                    );
                  }

                  // Ligne de totaux avec validation des coefficients
                  if (showTotals) {
                    final bool sumOk = (sumCoefficients - 20).abs() < 1e-6;
                    final PdfColor totalColor = sumOk ? secondaryColor : PdfColors.red;
                    
                    rows.add(
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: PdfColors.blue50),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2), 
                            child: pw.Text('TOTAUX', style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: 9))
                          ),
                          pw.SizedBox(),
                          pw.SizedBox(),
                          pw.SizedBox(),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2), 
                            child: pw.Text(
                              sumCoefficients > 0 ? sumCoefficients.toStringAsFixed(2) : '0', 
                              style: pw.TextStyle(font: timesBold, color: totalColor, fontSize: 9)
                            )
                          ),
                          pw.SizedBox(),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2), 
                            child: pw.Text(
                              sumPointsEleve > 0 ? sumPointsEleve.toStringAsFixed(2) : '0', 
                              style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: 9)
                            )
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2), 
                            child: pw.Text(
                              sumPointsClasse > 0 ? sumPointsClasse.toStringAsFixed(2) : '0', 
                              style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: 9)
                            )
                          ),
                          pw.SizedBox(),
                          pw.SizedBox(),
                        ],
                      ),
                    );
                  }

                  return pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.blue100),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.3),   // Matière
                      1: const pw.FlexColumnWidth(0.6),   // Sur
                      2: const pw.FlexColumnWidth(0.6),   // Dev
                      3: const pw.FlexColumnWidth(0.6),   // Comp
                      4: const pw.FlexColumnWidth(0.6),   // Coef
                      5: const pw.FlexColumnWidth(0.8),   // Moy Gen
                      6: const pw.FlexColumnWidth(0.9),   // Moy Gen Coef
                      7: const pw.FlexColumnWidth(0.8),   // Moy Cl
                      8: const pw.FlexColumnWidth(1.3),   // Professeur
                      9: const pw.FlexColumnWidth(1.7),   // Appréciation
                    },
                    children: rows,
                  );
                }

                pw.Widget buildGlobalTotals() {
                  double sumCoefficients = 0.0;
                  double sumPointsEleve = 0.0;
                  double sumPointsClasse = 0.0;
                  for (final subject in subjects) {
                    final subjectGrades = grades.where((g) => g.subject == subject).toList();
                    final devoirs = subjectGrades.where((g) => g.type == 'Devoir').toList();
                    final compositions = subjectGrades.where((g) => g.type == 'Composition').toList();
                    double total = 0; double totalCoeff = 0;
                    for (final g in [...devoirs, ...compositions]) {
                      if (g.maxValue > 0 && g.coefficient > 0) {
                        total += ((g.value / g.maxValue) * 20) * g.coefficient;
                        totalCoeff += g.coefficient;
                      }
                    }
                    final moyenneMatiere = totalCoeff > 0 ? (total / totalCoeff) : 0.0;
                    final subjectWeight = subjectWeights[subject] ?? totalCoeff;
                    sumCoefficients += subjectWeight;
                    if (subjectGrades.isNotEmpty) sumPointsEleve += moyenneMatiere * subjectWeight;
                    final mcText = (moyennesClasse[subject] ?? '').replaceAll(',', '.');
                    final mcVal = double.tryParse(mcText);
                    if (mcVal != null) sumPointsClasse += mcVal * subjectWeight;
                  }
                  
                  // Validation des coefficients pour les totaux globaux
                  final bool sumOk = (sumCoefficients - 20).abs() < 1e-6;
                  final PdfColor totalColor = sumOk ? secondaryColor : PdfColors.red;
                  
                  return pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.blue100),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.3),
                      1: const pw.FlexColumnWidth(0.6),
                      2: const pw.FlexColumnWidth(0.6),
                      3: const pw.FlexColumnWidth(0.6),
                      4: const pw.FlexColumnWidth(0.6),
                      5: const pw.FlexColumnWidth(0.8),
                      6: const pw.FlexColumnWidth(0.9),
                      7: const pw.FlexColumnWidth(0.8),
                      8: const pw.FlexColumnWidth(1.3),
                      9: const pw.FlexColumnWidth(1.7),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: PdfColors.blue50),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2), 
                            child: pw.Text('TOTAUX', style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: 9))
                          ),
                          pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2), 
                            child: pw.Text(
                              sumCoefficients.toStringAsFixed(2), 
                              style: pw.TextStyle(font: timesBold, color: totalColor, fontSize: 9)
                            )
                          ),
                          pw.SizedBox(),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2), 
                            child: pw.Text(
                              sumPointsEleve.toStringAsFixed(2), 
                              style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: 9)
                            )
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2), 
                            child: pw.Text(
                              sumPointsClasse.toStringAsFixed(2), 
                              style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: 9)
                            )
                          ),
                          pw.SizedBox(), pw.SizedBox(),
                        ],
                      ),
                    ],
                  );
                }

                if (!hasCategories) {
                  if (denseMode) {
                    final mid = (subjects.length / 2).ceil();
                    final left = subjects.sublist(0, mid);
                    final right = subjects.sublist(mid);
                    return <pw.Widget>[
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(child: buildTableForSubjects(left, showTotals: false)),
                          pw.SizedBox(width: 6),
                          pw.Expanded(child: buildTableForSubjects(right, showTotals: false)),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      buildGlobalTotals(),
                    ];
                  }
                  return <pw.Widget>[ buildTableForSubjects(subjects, showTotals: false), pw.SizedBox(height: 6), buildGlobalTotals() ];
                }
                // Ordonner les sections selon l'ordre des catégories, puis Non classée
                final List<String?> orderedKeys = [];
                for (final cat in _pdfCategories) {
                  if (grouped.containsKey(cat.id)) orderedKeys.add(cat.id);
                }
                if (grouped.containsKey(null)) orderedKeys.add(null);

                // Si dense, on aplatit en deux colonnes sans en-têtes de catégories pour gagner de la place
                if (denseMode) {
                  final flat = <String>[];
                  for (final k in orderedKeys) {
                    flat.addAll(grouped[k]!);
                  }
                  final mid = (flat.length / 2).ceil();
                  final left = flat.sublist(0, mid);
                  final right = flat.sublist(mid);
                  return <pw.Widget>[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(child: buildTableForSubjects(left)),
                        pw.SizedBox(width: 6),
                        pw.Expanded(child: buildTableForSubjects(right)),
                      ],
                    ),
                  ];
                }
                // Sinon, afficher sections par catégories
                final List<pw.Widget> sections = [];
                for (final key in orderedKeys) {
                  final bool isUncat = key == null;
                  final String label = isUncat
                      ? 'Matières non classées'
                      : 'Matières ' + _pdfCategories.firstWhere((c) => c.id == key, orElse: () => Category.empty()).name.toLowerCase();
                  final PdfColor badge = isUncat
                      ? PdfColors.blueGrey
                      : PdfColor.fromHex(_pdfCategories.firstWhere((c) => c.id == key, orElse: () => Category.empty()).color.replaceFirst('#', ''));
                  // Moyenne intermédiaire (pondérée) pour la catégorie
                  double catPts = 0.0;
                  double catCoeffs = 0.0;
                  for (final subj in grouped[key]!) {
                    final sGrades = grades.where((g) => g.subject == subj && (g.type == 'Devoir' || g.type == 'Composition') && g.value != 0).toList();
                    for (final g in sGrades) {
                      if (g.maxValue > 0 && g.coefficient > 0) {
                        catPts += ((g.value / g.maxValue) * 20) * g.coefficient;
                        catCoeffs += g.coefficient;
                      }
                    }
                  }
                  final String catAvgStr = catCoeffs > 0 ? (catPts / catCoeffs).toStringAsFixed(2) : '-';
                  // Moyenne catégorie de la classe (agrégée sur toutes les notes de la classe pour la période)
                  double catClassPts = 0.0;
                  double catClassCoeffs = 0.0;
                  for (final subj in grouped[key]!) {
                    final classSubjGrades = classPeriodGrades.where((g) => g.subject == subj && (g.type == 'Devoir' || g.type == 'Composition') && g.value != null && g.value != 0).toList();
                    for (final g in classSubjGrades) {
                      if (g.maxValue > 0 && g.coefficient > 0) {
                        catClassPts += ((g.value / g.maxValue) * 20) * g.coefficient;
                        catClassCoeffs += g.coefficient;
                      }
                    }
                  }
                  final String catClassAvgStr = catClassCoeffs > 0 ? (catClassPts / catClassCoeffs).toStringAsFixed(2) : '-';
                  sections.add(
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      margin: const pw.EdgeInsets.only(bottom: 6),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(width: 8, height: 20, decoration: pw.BoxDecoration(color: badge, borderRadius: pw.BorderRadius.circular(4))),
                          pw.SizedBox(width: 8),
                          pw.Text(label, style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: 10)),
                          pw.Spacer(),
                          pw.Text('Moy. intermédiaire: $catAvgStr', style: pw.TextStyle(font: times, color: secondaryColor, fontSize: 9)),
                          pw.SizedBox(width: 6),
                          pw.Text('Moy. cat. classe: $catClassAvgStr', style: pw.TextStyle(font: times, color: secondaryColor, fontSize: 9)),
                          pw.SizedBox(width: 6),
                          pw.Text('${grouped[key]!.length} matière(s)', style: pw.TextStyle(font: times, color: secondaryColor, fontSize: 9)),
                        ],
                      ),
                    ),
                  );
                  sections.add(buildTableForSubjects(grouped[key]!));
                  sections.add(pw.SizedBox(height: spacing));
                }
                // Ajouter les totaux globaux après toutes les catégories
                sections.add(buildGlobalTotals());
                return sections;
              }()),
              pw.SizedBox(height: spacing),
              // Synthèse : tableau des moyennes par période
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: PdfColors.blue100),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Moyenne par ' + periodLabel.toLowerCase(), style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: smallFont)),
                    pw.SizedBox(height: 8),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.blue100),
                      columnWidths: {
                        for (int i = 0; i < allTerms.length; i++) i: const pw.FlexColumnWidth(),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: tableHeaderBg),
                          children: List.generate(allTerms.length, (i) {
                            final label = allTerms[i];
                            final avg = (i < moyennesParPeriode.length && moyennesParPeriode[i] != null)
                              ? ' (' + (moyennesParPeriode[i]!.toStringAsFixed(2)) + ')'
                              : '';
                            return pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(label + avg, style: pw.TextStyle(font: timesBold, color: tableHeaderText, fontSize: smallFont)),
                            );
                          }),
                        ),
                        pw.TableRow(
                          children: List.generate(allTerms.length, (i) {
                            final String term = allTerms[i];
                            final double? m = (i < moyennesParPeriode.length) ? moyennesParPeriode[i] : null;
                            final r = rankPerTerm[term];
                            final String mainTxt = m != null ? m.toStringAsFixed(2) : '-';
                            final String? suffix = (m != null && r != null && (r['nb'] ?? 0) > 0)
                                ? '(rang ${r['rank']}/${r['nb']})'
                                : null;
                            return pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Row(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(mainTxt, style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
                                  if (suffix != null) ...[
                                    pw.SizedBox(width: 4),
                                    pw.Text(suffix, style: pw.TextStyle(color: PdfColors.grey600, fontSize: smallFont - 0.5, fontStyle: pw.FontStyle.italic)),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: spacing),
              // Synthèse générale
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: PdfColors.blue100),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Moyenne de l\'élève : ${moyenneGenerale.toStringAsFixed(2)}', style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: smallFont + 1)),
                          if (moyenneGeneraleDeLaClasse != null)
                            pw.Text('Moyenne de la classe : ${moyenneGeneraleDeLaClasse.toStringAsFixed(2)}', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          if (moyenneLaPlusForte != null)
                            pw.Text('Moyenne la plus forte : ${moyenneLaPlusForte.toStringAsFixed(2)}', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          if (moyenneLaPlusFaible != null)
                            pw.Text('Moyenne la plus faible : ${moyenneLaPlusFaible.toStringAsFixed(2)}', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          // Afficher la moyenne/rang annuels uniquement en fin de période (T3 ou S2)
                          if ((() {
                            final pl = periodLabel.toLowerCase();
                            final st = selectedTerm.toLowerCase();
                            if (pl.contains('trimestre')) return st.contains('3');
                            if (pl.contains('semestre')) return st.contains('2');
                            return false;
                          })()) ...[
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 4),
                              child: pw.Text('Moyenne annuelle : ' +
                                (moyenneAnnuelle != null
                                  ? moyenneAnnuelle.toStringAsFixed(2)
                                  : (moyennesParPeriode.isNotEmpty && moyennesParPeriode.every((m) => m != null)
                                    ? (moyennesParPeriode.whereType<double>().reduce((a, b) => a + b) / moyennesParPeriode.length).toStringAsFixed(2)
                                    : '-')
                                ),
                                style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: smallFont),
                              ),
                            ),
                            if (moyenneAnnuelleClasseComputed != null)
                              pw.Text('Moyenne annuelle de la classe : ' + moyenneAnnuelleClasseComputed!.toStringAsFixed(2), style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                            if (rangAnnuelComputed != null && nbEleves > 0)
                              pw.Text('Rang annuel : ${rangAnnuelComputed!} / $nbEleves', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          ],
                          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Text('Rang : ', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
              pw.Text(exaequo ? '$rang (ex æquo) / $nbEleves' : '$rang / $nbEleves', style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
            ],
          ),
                          pw.SizedBox(height: 8),
                          pw.Row(
                            children: [
                              pw.Text('Mention : ', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: pw.BoxDecoration(
                                  color: mainColor,
                                  borderRadius: pw.BorderRadius.circular(8),
                                ),
                                child: pw.Text(mention, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: smallFont)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Appréciation générale :', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 8),
                          pw.Text(appreciationGenerale, style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 16),
                          pw.Text('Décision du conseil de classe :', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 8),
                          pw.Text(decision, style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 8),
                          pw.Text('Recommandations :', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 4),
                          pw.Text(recommandations, style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 8),
                          pw.Text('Forces :', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 4),
                          pw.Text(forces, style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 8),
                          pw.Text('Points à développer :', style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 4),
                          pw.Text(pointsADevelopper, style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Assiduité et Conduite', style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: smallFont)),
                          pw.SizedBox(height: 6),
                          pw.Row(children: [
                            pw.Expanded(child: pw.Text('Présence: ' + (presencePercent > 0 ? presencePercent.toStringAsFixed(1) : '-'), style: pw.TextStyle(color: secondaryColor, fontSize: smallFont))),
                            pw.Expanded(child: pw.Text('Retards: ' + (retards > 0 ? '$retards' : '-'), style: pw.TextStyle(color: secondaryColor, fontSize: smallFont))),
                          ]),
                          pw.SizedBox(height: 4),
                          pw.Row(children: [
                            pw.Expanded(child: pw.Text('Abs. justifiées: ' + (attendanceJustifiee > 0 ? '$attendanceJustifiee' : '-'), style: pw.TextStyle(color: secondaryColor, fontSize: smallFont))),
                            pw.Expanded(child: pw.Text('Abs. injustifiées: ' + (attendanceInjustifiee > 0 ? '$attendanceInjustifiee' : '-'), style: pw.TextStyle(color: secondaryColor, fontSize: smallFont))),
                          ]),
                          pw.SizedBox(height: 4),
                          pw.Text('Conduite: ' + (conduite.isNotEmpty ? conduite : '-'), style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
                          pw.SizedBox(height: 6),
                          pw.Text('Sanctions', style: pw.TextStyle(font: timesBold, color: PdfColors.red700, fontSize: smallFont)),
                          pw.SizedBox(height: 4),
                          pw.Text(sanctions.isNotEmpty ? sanctions : '-', style: pw.TextStyle(color: secondaryColor, fontSize: smallFont)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: spacing),
              // Bloc signature
              pw.Container(
                padding: pw.EdgeInsets.all(isLandscape ? 6 : 8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(10),
                  border: pw.Border.all(color: PdfColors.blue100, width: 1),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Fait à :', style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: baseFont)),
                          pw.SizedBox(height: 2),
                          pw.Text(faitA.isNotEmpty ? faitA : '__________________________', style: pw.TextStyle(font: times, color: secondaryColor, fontSize: baseFont)),
                          pw.SizedBox(height: spacing/2),
                          pw.Text(
                            niveau.toLowerCase().contains('lycée') ? 'Proviseur(e) :' : 'Directeur(ice) :',
                            style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: baseFont),
                          ),
                          pw.SizedBox(height: 2),
                          if (schoolInfo.director.isNotEmpty)
                            pw.Text(
                              schoolInfo.director,
                              style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: baseFont),
                            ),
                          pw.SizedBox(height: 2),
                          pw.Text('__________________________', style: pw.TextStyle(font: times, color: secondaryColor, fontSize: baseFont)),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: isLandscape ? 12 : 24),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Le :', style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: baseFont)),
                          pw.SizedBox(height: 2),
                          pw.Text(leDate.isNotEmpty ? leDate : '__________________________', style: pw.TextStyle(font: times, color: secondaryColor, fontSize: baseFont)),
                          pw.SizedBox(height: spacing/2),
                              pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Titulaire : ', style: pw.TextStyle(font: timesBold, color: mainColor, fontSize: baseFont)),
                              pw.SizedBox(height: 2),
                              if (titulaire.isNotEmpty)
                                pw.Text(titulaire, style: pw.TextStyle(font: timesBold, color: secondaryColor, fontSize: baseFont)),
                              pw.SizedBox(height: 2),
                              pw.Text('__________________________', style: pw.TextStyle(font: times, color: secondaryColor, fontSize: baseFont)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Sanctions now displayed in the right column
              pw.SizedBox(height: isLandscape ? 8 : 24),
            ];
        },
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF de l'emploi du temps
  static Future<List<int>> generateTimetablePdf({
    required SchoolInfo schoolInfo,
    required String academicYear, // The academic year for the timetable
    required List<String> daysOfWeek,
    required List<String> timeSlots,
    required List<TimetableEntry> timetableEntries,
    required String title,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Stack(
            children: [
              // Logo en filigrane en arrière-plan
              if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
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
              // Contenu principal
              pw.Column(
                children: [
                  // En-tête administratif
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: ((schoolInfo.ministry ?? '').isNotEmpty)
                            ? pw.Text((schoolInfo.ministry ?? '').toUpperCase(), style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary))
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(((schoolInfo.republic ?? 'RÉPUBLIQUE').toUpperCase()), style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                            if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 2),
                                child: pw.Text(schoolInfo.republicMotto!, style: pw.TextStyle(font: times, fontSize: 9, color: primary, fontStyle: pw.FontStyle.italic), textAlign: pw.TextAlign.right),
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
                        child: ((schoolInfo.inspection ?? '').isNotEmpty)
                            ? pw.Text('Inspection: ${schoolInfo.inspection}', style: pw.TextStyle(font: times, fontSize: 9, color: primary))
                            : pw.SizedBox(),
                      ),
                      pw.Expanded(
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: ((schoolInfo.educationDirection ?? '').isNotEmpty)
                              ? pw.Text("Direction de l'enseignement: ${schoolInfo.educationDirection}", style: pw.TextStyle(font: times, fontSize: 9, color: primary))
                              : pw.SizedBox(),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  // Header
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: light,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(right: 12),
                            child: pw.Image(
                              pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                              width: 50,
                              height: 50,
                            ),
                          ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                schoolInfo.name,
                                style: pw.TextStyle(font: timesBold, fontSize: 18, color: accent, fontWeight: pw.FontWeight.bold),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(schoolInfo.address, style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Année académique: $academicYear  •  Généré le: ' + DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                                style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                              ),
                              pw.SizedBox(height: 2),
                              if ((schoolInfo.email ?? '').isNotEmpty)
                                pw.Text('Email : ${schoolInfo.email}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                              if ((schoolInfo.website ?? '').isNotEmpty)
                                pw.Text('Site web : ${schoolInfo.website}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                              if ((schoolInfo.telephone ?? '').isNotEmpty)
                                pw.Text('Téléphone : ${schoolInfo.telephone}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),

                  // Title
                  pw.Text(title, style: pw.TextStyle(font: timesBold, fontSize: 20, color: accent, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),

                  // Timetable Table
                  pw.Table.fromTextArray(
                    headers: ['Heure', ...daysOfWeek],
                    data: timeSlots.map((timeSlot) {
                      return [
                        timeSlot,
                        ...daysOfWeek.map((day) {
                          final timeSlotParts = timeSlot.split(' - ');
                          final slotStartTime = timeSlotParts[0];

                          final entry = timetableEntries.firstWhere(
                            (e) => e.dayOfWeek == day && e.startTime == slotStartTime,
                            orElse: () => TimetableEntry(
                              subject: '',
                              teacher: '',
                              className: '',
                              academicYear: '',
                              dayOfWeek: '',
                              startTime: '',
                              endTime: '',
                              room: '',
                            ),
                          );
                          return entry.subject.isNotEmpty
                              ? '${entry.subject}\n${entry.teacher}\n${entry.className}\n${entry.room}'
                              : '';
                        }),
                      ];
                    }).toList(),
                    cellStyle: pw.TextStyle(font: times, fontSize: 8),
                    headerStyle: pw.TextStyle(font: timesBold, fontSize: 9),
                    border: pw.TableBorder.all(color: light, width: 1.2),
                    cellAlignment: pw.Alignment.center,
                    headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<List<int>> exportStatisticsPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required int totalStudents,
    required int totalStaff,
    required int totalClasses,
    required double totalRevenue,
    required List<Map<String, dynamic>> monthlyEnrollment,
    required Map<String, int> classDistribution,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    String formatMonth(String ym) {
      // Expects YYYY-MM
      try {
        final parts = ym.split('-');
        if (parts.length == 2) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final date = DateTime(year, month, 1);
          return DateFormat('MMM yyyy', 'fr_FR').format(date);
        }
      } catch (_) {}
      return ym;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: light,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(
                        pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                        width: 50,
                        height: 50,
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo.name,
                          style: pw.TextStyle(font: timesBold, fontSize: 18, color: accent, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(schoolInfo.address, style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Année académique: $academicYear  •  Généré le: ' + DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                          style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Title
            pw.Text('Rapport de Statistiques', style: pw.TextStyle(font: timesBold, fontSize: 20, color: accent, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),

            // KPI cards (as table)
            pw.Table(
              border: pw.TableBorder.all(color: light, width: 1.2),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Indicateur', style: pw.TextStyle(font: timesBold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Valeur', style: pw.TextStyle(font: timesBold))),
                  ],
                ),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Total élèves', style: pw.TextStyle(font: times))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$totalStudents', style: pw.TextStyle(font: timesBold))),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Personnel', style: pw.TextStyle(font: times))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$totalStaff', style: pw.TextStyle(font: timesBold))),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Classes', style: pw.TextStyle(font: times))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$totalClasses', style: pw.TextStyle(font: timesBold))),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Revenus (total)', style: pw.TextStyle(font: times))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA', decimalDigits: 0).format(totalRevenue), style: pw.TextStyle(font: timesBold))),
                ]),
              ],
            ),

            if (monthlyEnrollment.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text('Inscriptions mensuelles', style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: light, width: 1.0),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Mois', style: pw.TextStyle(font: timesBold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Inscriptions', style: pw.TextStyle(font: timesBold))),
                    ],
                  ),
                  ...monthlyEnrollment.map((e) => pw.TableRow(children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(formatMonth((e['month'] ?? '').toString()), style: pw.TextStyle(font: times))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(((e['count'] ?? 0)).toString(), style: pw.TextStyle(font: times))),
                      ])),
                ],
              ),
            ],

            if (classDistribution.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text('Répartition des élèves par classe', style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: light, width: 1.0),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Classe', style: pw.TextStyle(font: timesBold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Effectif', style: pw.TextStyle(font: timesBold))),
                    ],
                  ),
                  ...classDistribution.entries.map((e) => pw.TableRow(children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e.key, style: pw.TextStyle(font: times))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e.value.toString(), style: pw.TextStyle(font: times))),
                      ])),
                ],
              ),
            ],
          ];
        },
      ),
    );
    return pdf.save();
  }

  static Future<List<int>> generateStaffPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required List<Staff> staffList,
    required String title,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      buildBackground: (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
          ? (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Opacity(
                  opacity: 0.05,
                  child: pw.Image(
                    pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                    fit: pw.BoxFit.cover,
                  ),
                ),
              )
          : null,
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        build: (pw.Context context) {
          return [
            // En-tête administratif
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: ((schoolInfo.ministry ?? '').isNotEmpty)
                      ? pw.Text((schoolInfo.ministry ?? '').toUpperCase(), style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary))
                      : pw.SizedBox(),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(((schoolInfo.republic ?? 'RÉPUBLIQUE').toUpperCase()), style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                      if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(schoolInfo.republicMotto!, style: pw.TextStyle(font: times, fontSize: 9, color: primary, fontStyle: pw.FontStyle.italic), textAlign: pw.TextAlign.right),
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
                  child: ((schoolInfo.inspection ?? '').isNotEmpty)
                      ? pw.Text('Inspection: ${schoolInfo.inspection}', style: pw.TextStyle(font: times, fontSize: 9, color: primary))
                      : pw.SizedBox(),
                ),
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: ((schoolInfo.educationDirection ?? '').isNotEmpty)
                        ? pw.Text("Direction de l'enseignement: ${schoolInfo.educationDirection}", style: pw.TextStyle(font: times, fontSize: 9, color: primary))
                        : pw.SizedBox(),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            // Header avec logo et informations de l'école
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 16),
                        child: pw.Image(
                          pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                          height: 60,
                          width: 60,
                        ),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo.name,
                          style: pw.TextStyle(font: timesBold, fontSize: 18, color: primary),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          schoolInfo.address ?? '',
                          style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if ((schoolInfo.email ?? '').isNotEmpty)
                              pw.Text('Email : ${schoolInfo.email}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                            if ((schoolInfo.website ?? '').isNotEmpty)
                              pw.Text('Site web : ${schoolInfo.website}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                            if ((schoolInfo.telephone ?? '').isNotEmpty)
                              pw.Text('Téléphone : ${schoolInfo.telephone}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Année scolaire',
                      style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                    ),
                    pw.Text(
                      academicYear,
                      style: pw.TextStyle(font: timesBold, fontSize: 12, color: primary),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Title centré
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(font: timesBold, fontSize: 24, color: accent, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 16),

            // Tableau du personnel avec design amélioré
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Table(
                border: pw.TableBorder.all(color: light, width: 1.2),
                columnWidths: {
                  0: const pw.FixedColumnWidth(80),  // Photo
                  1: const pw.FlexColumnWidth(2),   // Nom
                  2: const pw.FlexColumnWidth(1.5),  // Poste
                  3: const pw.FlexColumnWidth(1.5),  // Contact
                  4: const pw.FlexColumnWidth(1),    // Statut
                },
                children: [
                  // Headers
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: accent),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Photo', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Nom', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Poste', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Contact', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Statut', style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.white))),
                    ],
                  ),
                // Data rows
                ...staffList.map((staff) => pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Container(
                      width: 40,
                      height: 40,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey200,
                        borderRadius: pw.BorderRadius.circular(20),
                      ),
                      child: staff.photoPath != null && staff.photoPath!.isNotEmpty
                          ? pw.Image(
                              pw.MemoryImage(File(staff.photoPath!).readAsBytesSync()),
                              fit: pw.BoxFit.cover,
                            )
                          : pw.Center(
                              child: pw.Text(
                                _getInitials(staff.name),
                                style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.grey600),
                              ),
                            ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(staff.name, style: pw.TextStyle(font: timesBold, fontSize: 9)),
                        if (staff.firstName != null && staff.firstName!.isNotEmpty)
                          pw.Text('Prénom: ${staff.firstName}', style: pw.TextStyle(font: times, fontSize: 7, color: PdfColors.grey600)),
                        if (staff.lastName != null && staff.lastName!.isNotEmpty)
                          pw.Text('Nom: ${staff.lastName}', style: pw.TextStyle(font: times, fontSize: 7, color: PdfColors.grey600)),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(staff.typeRole, style: pw.TextStyle(font: timesBold, fontSize: 8)),
                        pw.Text(staff.role, style: pw.TextStyle(font: times, fontSize: 7, color: PdfColors.grey600)),
                        if (staff.department.isNotEmpty)
                          pw.Text(staff.department, style: pw.TextStyle(font: times, fontSize: 7, color: PdfColors.grey600)),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(staff.phone, style: pw.TextStyle(font: times, fontSize: 8)),
                        pw.Text(staff.email, style: pw.TextStyle(font: times, fontSize: 7, color: PdfColors.grey600)),
                        if (staff.address != null && staff.address!.isNotEmpty)
                          pw.Text(staff.address!, style: pw.TextStyle(font: times, fontSize: 6, color: PdfColors.grey600)),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: _getStatusColor(staff.status),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        staff.status,
                        style: pw.TextStyle(font: timesBold, fontSize: 7, color: PdfColors.white),
                      ),
                    ),
                  ),
                ])),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Informations détaillées pour chaque membre du personnel
            ...staffList.map((staff) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 16),
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Détails - ${staff.name}',
                    style: pw.TextStyle(font: timesBold, fontSize: 16, color: accent),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      _buildInfoTableRow('Date d\'embauche', DateFormat('dd/MM/yyyy').format(staff.hireDate), times, timesBold),
                      if (staff.birthDate != null)
                        _buildInfoTableRow('Date de naissance', DateFormat('dd/MM/yyyy').format(staff.birthDate!), times, timesBold),
                      if (staff.gender != null)
                        _buildInfoTableRow('Sexe', staff.gender!, times, timesBold),
                      if (staff.nationality != null)
                        _buildInfoTableRow('Nationalité', staff.nationality!, times, timesBold),
                      if (staff.matricule != null)
                        _buildInfoTableRow('Matricule', staff.matricule!, times, timesBold),
                      if (staff.region != null)
                        _buildInfoTableRow('Région', staff.region!, times, timesBold),
                      if (staff.levels != null && staff.levels!.isNotEmpty)
                        _buildInfoTableRow('Niveaux enseignés', staff.levels!.join(', '), times, timesBold),
                      if (staff.highestDegree != null)
                        _buildInfoTableRow('Diplôme', staff.highestDegree!, times, timesBold),
                      if (staff.experienceYears != null)
                        _buildInfoTableRow('Expérience', '${staff.experienceYears} années', times, timesBold),
                      if (staff.courses.isNotEmpty)
                        _buildInfoTableRow('Cours assignés', staff.courses.join(', '), times, timesBold),
                      if (staff.classes.isNotEmpty)
                        _buildInfoTableRow('Classes assignées', staff.classes.join(', '), times, timesBold),
                    ],
                  ),
                ],
              ),
            )),
          ];
        },
      ),
    );
    return pdf.save();
  }

  static pw.TableRow _buildInfoTableRow(String label, String value, pw.Font font, pw.Font fontBold) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(label, style: pw.TextStyle(font: fontBold, fontSize: 8)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 8)),
      ),
    ]);
  }

  static String _getInitials(String name) {
    final parts = name.trim().split(' ').where((n) => n.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String initials = parts.map((n) => n[0]).join();
    if (initials.length > 2) initials = initials.substring(0, 2);
    return initials.toUpperCase();
  }

  static PdfColor _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'actif':
        return PdfColors.green;
      case 'en congé':
        return PdfColors.orange;
      default:
        return PdfColors.red;
    }
  }

  static Future<List<int>> generateIndividualStaffPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required Staff staff,
    required String title,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      buildBackground: (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
          ? (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Opacity(
                  opacity: 0.05,
                  child: pw.Image(
                    pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                    fit: pw.BoxFit.cover,
                  ),
                ),
              )
          : null,
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        build: (pw.Context context) {
          return [
            // Header avec logo et informations de l'école
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 16),
                        child: pw.Image(
                          pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                          height: 60,
                          width: 60,
                        ),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo.name,
                          style: pw.TextStyle(font: timesBold, fontSize: 18, color: primary),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          schoolInfo.address ?? '',
                          style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if ((schoolInfo.email ?? '').isNotEmpty)
                              pw.Text('Email : ${schoolInfo.email}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                            if ((schoolInfo.website ?? '').isNotEmpty)
                              pw.Text('Site web : ${schoolInfo.website}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                            if ((schoolInfo.telephone ?? '').isNotEmpty)
                              pw.Text('Téléphone : ${schoolInfo.telephone}', style: pw.TextStyle(font: times, fontSize: 10, color: primary)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Année scolaire',
                      style: pw.TextStyle(font: times, fontSize: 10, color: primary),
                    ),
                    pw.Text(
                      academicYear,
                      style: pw.TextStyle(font: timesBold, fontSize: 12, color: primary),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Title centré
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(font: timesBold, fontSize: 24, color: accent, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 24),

            // Photo et informations principales centrées
            pw.Center(
              child: pw.Column(
                children: [
                  // Photo
                  pw.Container(
                    width: 150,
                    height: 150,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(75),
                      border: pw.Border.all(color: accent, width: 3),
                    ),
                    child: staff.photoPath != null && staff.photoPath!.isNotEmpty
                        ? pw.Image(
                            pw.MemoryImage(File(staff.photoPath!).readAsBytesSync()),
                            fit: pw.BoxFit.cover,
                          )
                        : pw.Center(
                            child: pw.Text(
                              _getInitials(staff.name),
                              style: pw.TextStyle(font: timesBold, fontSize: 32, color: PdfColors.grey600),
                            ),
                          ),
                  ),
                  pw.SizedBox(height: 20),
                  // Informations principales
                  pw.Text(
                    staff.name,
                    style: pw.TextStyle(font: timesBold, fontSize: 28, color: primary),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    staff.typeRole,
                    style: pw.TextStyle(font: timesBold, fontSize: 18, color: accent),
                  ),
                  pw.Text(
                    staff.role,
                    style: pw.TextStyle(font: times, fontSize: 16, color: PdfColors.grey600),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: _getStatusColor(staff.status),
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Text(
                      staff.status,
                      style: pw.TextStyle(font: timesBold, fontSize: 12, color: PdfColors.white),
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 32),

            // Informations détaillées avec design amélioré
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'Informations personnelles',
                    style: pw.TextStyle(font: timesBold, fontSize: 18, color: accent),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      _buildInfoTableRow('Nom complet', staff.name, times, timesBold),
                      if (staff.firstName != null && staff.firstName!.isNotEmpty)
                        _buildInfoTableRow('Prénoms', staff.firstName!, times, timesBold),
                      if (staff.lastName != null && staff.lastName!.isNotEmpty)
                        _buildInfoTableRow('Nom de famille', staff.lastName!, times, timesBold),
                      if (staff.gender != null)
                        _buildInfoTableRow('Sexe', staff.gender!, times, timesBold),
                      if (staff.birthDate != null)
                        _buildInfoTableRow('Date de naissance', DateFormat('dd/MM/yyyy').format(staff.birthDate!), times, timesBold),
                      if (staff.birthPlace != null)
                        _buildInfoTableRow('Lieu de naissance', staff.birthPlace!, times, timesBold),
                      if (staff.nationality != null)
                        _buildInfoTableRow('Nationalité', staff.nationality!, times, timesBold),
                      if (staff.address != null)
                        _buildInfoTableRow('Adresse', staff.address!, times, timesBold),
                      _buildInfoTableRow('Téléphone', staff.phone, times, timesBold),
                      _buildInfoTableRow('Email', staff.email, times, timesBold),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Informations professionnelles
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'Informations professionnelles',
                    style: pw.TextStyle(font: timesBold, fontSize: 18, color: accent),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      _buildInfoTableRow('Poste', staff.typeRole, times, timesBold),
                      _buildInfoTableRow('Rôle détaillé', staff.role, times, timesBold),
                      if (staff.department.isNotEmpty)
                        _buildInfoTableRow('Département', staff.department, times, timesBold),
                      if (staff.region != null)
                        _buildInfoTableRow('Région', staff.region!, times, timesBold),
                      if (staff.levels != null && staff.levels!.isNotEmpty)
                        _buildInfoTableRow('Niveaux enseignés', staff.levels!.join(', '), times, timesBold),
                      if (staff.highestDegree != null)
                        _buildInfoTableRow('Diplôme', staff.highestDegree!, times, timesBold),
                      if (staff.specialty != null)
                        _buildInfoTableRow('Spécialité', staff.specialty!, times, timesBold),
                      if (staff.experienceYears != null)
                        _buildInfoTableRow('Expérience', '${staff.experienceYears} années', times, timesBold),
                      if (staff.previousInstitution != null)
                        _buildInfoTableRow('Ancienne école', staff.previousInstitution!, times, timesBold),
                      if (staff.qualifications.isNotEmpty)
                        _buildInfoTableRow('Qualifications', staff.qualifications, times, timesBold),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Informations administratives
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'Informations administratives',
                    style: pw.TextStyle(font: timesBold, fontSize: 18, color: accent),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      if (staff.matricule != null)
                        _buildInfoTableRow('Matricule', staff.matricule!, times, timesBold),
                      if (staff.idNumber != null)
                        _buildInfoTableRow('CNI/Passeport', staff.idNumber!, times, timesBold),
                      if (staff.socialSecurityNumber != null)
                        _buildInfoTableRow('Sécurité sociale', staff.socialSecurityNumber!, times, timesBold),
                      if (staff.maritalStatus != null)
                        _buildInfoTableRow('Situation matrimoniale', staff.maritalStatus!, times, timesBold),
                      if (staff.numberOfChildren != null)
                        _buildInfoTableRow('Nombre d\'enfants', staff.numberOfChildren.toString(), times, timesBold),
                      _buildInfoTableRow('Statut', staff.status, times, timesBold),
                      if (staff.contractType != null)
                        _buildInfoTableRow('Type de contrat', staff.contractType!, times, timesBold),
                      _buildInfoTableRow('Date d\'embauche', DateFormat('dd/MM/yyyy').format(staff.hireDate), times, timesBold),
                      if (staff.baseSalary != null)
                        _buildInfoTableRow('Salaire de base', '${staff.baseSalary} FCFA', times, timesBold),
                      if (staff.weeklyHours != null)
                        _buildInfoTableRow('Heures hebdomadaires', '${staff.weeklyHours} heures', times, timesBold),
                      if (staff.supervisor != null)
                        _buildInfoTableRow('Responsable', staff.supervisor!, times, timesBold),
                      if (staff.retirementDate != null)
                        _buildInfoTableRow('Date de retraite', DateFormat('dd/MM/yyyy').format(staff.retirementDate!), times, timesBold),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Affectations
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    'Affectations',
                    style: pw.TextStyle(font: timesBold, fontSize: 18, color: accent),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border: pw.TableBorder.all(color: light, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      if (staff.courses.isNotEmpty)
                        _buildInfoTableRow('Cours assignés', staff.courses.join(', '), times, timesBold),
                      if (staff.classes.isNotEmpty)
                        _buildInfoTableRow('Classes assignées', staff.classes.join(', '), times, timesBold),
                      if (staff.documents != null && staff.documents!.isNotEmpty)
                        _buildInfoTableRow('Documents', staff.documents!.join(', '), times, timesBold),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  /// Génère un PDF de la liste des matières avec leurs catégories
  static Future<List<int>> generateSubjectsPdf({
    required SchoolInfo schoolInfo,
    required String academicYear,
    required List<Course> courses,
    required List<Category> categories,
    required String title,
  }) async {
    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#4F46E5');
    final accent = PdfColor.fromHex('#8B5CF6');
    final light = PdfColor.fromHex('#E5E7EB');
    final lightBg = PdfColor.fromHex('#F9FAFB');

    final subjectsPageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      buildBackground: (context) {
        if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync()) {
          return pw.Center(
            child: pw.Opacity(
              opacity: 0.06,
              child: pw.Image(
                pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                width: 400,
              ),
            ),
          );
        }
        return pw.SizedBox();
      },
    );
    pdf.addPage(
      pw.MultiPage(
        pageTheme: subjectsPageTheme,
        header: (context) {
          // En-tête de page léger (pas sur la 1ère page où un grand en-tête existe déjà)
          if (context.pageNumber == 1) return pw.SizedBox();
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: light, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  schoolInfo.name,
                  style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary),
                ),
                pw.Text(
                  '$title - $academicYear',
                  style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: light, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  DateFormat('dd/MM/yyyy').format(DateTime.now()),
                  style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Page ${context.pageNumber} / ${context.pagesCount}',
                  style: pw.TextStyle(font: times, fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // Contenu principal
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // En-tête administratif
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: ((schoolInfo.ministry ?? '').isNotEmpty)
                          ? pw.Text((schoolInfo.ministry ?? '').toUpperCase(), style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary))
                          : pw.SizedBox(),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(((schoolInfo.republic ?? 'RÉPUBLIQUE').toUpperCase()), style: pw.TextStyle(font: timesBold, fontSize: 10, color: primary)),
                          if ((schoolInfo.republicMotto ?? '').isNotEmpty)
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 2),
                              child: pw.Text(schoolInfo.republicMotto!, style: pw.TextStyle(font: times, fontSize: 9, color: primary, fontStyle: pw.FontStyle.italic), textAlign: pw.TextAlign.right),
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
                      child: ((schoolInfo.inspection ?? '').isNotEmpty)
                          ? pw.Text('Inspection: ${schoolInfo.inspection}', style: pw.TextStyle(font: times, fontSize: 9, color: primary))
                          : pw.SizedBox(),
                    ),
                    pw.Expanded(
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: ((schoolInfo.educationDirection ?? '').isNotEmpty)
                            ? pw.Text("Direction de l'enseignement: ${schoolInfo.educationDirection}", style: pw.TextStyle(font: times, fontSize: 9, color: primary))
                            : pw.SizedBox(),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                // En-tête avec logo et informations de l'école
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Row(
                children: [
                  if (schoolInfo.logoPath != null && File(schoolInfo.logoPath!).existsSync())
                    pw.Container(
                      width: 60,
                      height: 60,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Image(
                        pw.MemoryImage(File(schoolInfo.logoPath!).readAsBytesSync()),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          schoolInfo.name,
                          style: pw.TextStyle(font: timesBold, fontSize: 20, color: primary),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          title,
                          style: pw.TextStyle(font: timesBold, fontSize: 16, color: primary),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Année académique: $academicYear',
                          style: pw.TextStyle(font: times, fontSize: 12, color: PdfColors.grey600),
                        ),
                        pw.Text(
                          'Généré le: ${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.now())}',
                          style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.grey600),
                        ),
                        pw.SizedBox(height: 2),
                        if ((schoolInfo.email ?? '').isNotEmpty)
                          pw.Text('Email : ${schoolInfo.email}', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.grey700)),
                        if ((schoolInfo.website ?? '').isNotEmpty)
                          pw.Text('Site web : ${schoolInfo.website}', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.grey700)),
                        if ((schoolInfo.telephone ?? '').isNotEmpty)
                          pw.Text('Téléphone : ${schoolInfo.telephone}', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Statistiques générales
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: lightBg,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('${courses.length}', style: pw.TextStyle(font: timesBold, fontSize: 24, color: primary)),
                      pw.Text('Matières', style: pw.TextStyle(font: times, fontSize: 12, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('${categories.length}', style: pw.TextStyle(font: timesBold, fontSize: 24, color: accent)),
                      pw.Text('Catégories', style: pw.TextStyle(font: times, fontSize: 12, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('${courses.where((c) => c.categoryId != null).length}', style: pw.TextStyle(font: timesBold, fontSize: 24, color: PdfColor.fromHex('#10B981'))),
                      pw.Text('Classées', style: pw.TextStyle(font: times, fontSize: 12, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 12),
            // Sommaire des catégories
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: light, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Sommaire des catégories', style: pw.TextStyle(font: timesBold, fontSize: 12, color: primary)),
                  pw.SizedBox(height: 8),
                  pw.Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...categories.map((cat) {
                        final color = PdfColor.fromHex(cat.color.replaceFirst('#', ''));
                        final count = courses.where((c) => c.categoryId == cat.id).length;
                        return pw.Link(
                          destination: 'cat_${cat.id}',
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(20),
                              border: pw.Border.all(color: color, width: 1),
                            ),
                            child: pw.Row(children: [
                              pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(4))),
                              pw.SizedBox(width: 6),
                              pw.Text('${cat.name} ($count)', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.grey800)),
                            ]),
                          ),
                        );
                      }).toList(),
                      if (courses.where((c) => c.categoryId == null).isNotEmpty)
                        pw.Link(
                          destination: 'cat_uncat',
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(20),
                              border: pw.Border.all(color: PdfColors.grey600, width: 1),
                            ),
                            child: pw.Row(children: [
                              pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: PdfColors.grey600, borderRadius: pw.BorderRadius.circular(4))),
                              pw.SizedBox(width: 6),
                              pw.Text('Non classées (${courses.where((c) => c.categoryId == null).length})', style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.grey800)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // Liste des matières par catégorie
            ...categories.map((category) {
              final categoryCourses = courses.where((c) => c.categoryId == category.id).toList();
              final categoryColor = PdfColor.fromHex(category.color.replaceFirst('#', ''));
              
              return pw.Anchor(
                name: 'cat_${category.id}',
                child: pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 16),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // En-tête de catégorie
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: categoryColor,
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            width: 20,
                            height: 20,
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                '${categoryCourses.length}',
                                style: pw.TextStyle(font: timesBold, fontSize: 10, color: categoryColor),
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 12),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  category.name,
                                  style: pw.TextStyle(font: timesBold, fontSize: 16, color: PdfColors.white),
                                ),
                                if (category.description != null && category.description!.isNotEmpty)
                                  pw.Text(
                                    category.description!,
                                    style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.white),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    pw.SizedBox(height: 8),
                    
                    // Liste des matières de cette catégorie
                    if (categoryCourses.isNotEmpty)
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: light, width: 1),
                        ),
                        child: pw.Table(
                          border: pw.TableBorder.all(color: light, width: 0.5),
                          columnWidths: {
                            0: const pw.FlexColumnWidth(1),
                            1: const pw.FlexColumnWidth(3),
                            2: const pw.FlexColumnWidth(2),
                          },
                          children: [
                            // En-tête du tableau
                            pw.TableRow(
                              decoration: pw.BoxDecoration(color: lightBg),
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text('N°', style: pw.TextStyle(font: timesBold, fontSize: 10)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text('Matière', style: pw.TextStyle(font: timesBold, fontSize: 10)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text('Description', style: pw.TextStyle(font: timesBold, fontSize: 10)),
                                ),
                              ],
                            ),
                            // Données des matières
                            ...categoryCourses.asMap().entries.map((entry) {
                              final index = entry.key + 1;
                              final course = entry.value;
                              return pw.TableRow(
                                children: [
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(8),
                                    child: pw.Text('$index', style: pw.TextStyle(font: times, fontSize: 9)),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(8),
                                    child: pw.Text(course.name, style: pw.TextStyle(font: timesBold, fontSize: 9)),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(8),
                                    child: pw.Text(
                                      course.description ?? '-',
                                      style: pw.TextStyle(font: times, fontSize: 8, color: PdfColors.grey600),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      )
                    else
                      pw.Container(
                        padding: const pw.EdgeInsets.all(16),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey50,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: light, width: 1),
                        ),
                        child: pw.Text(
                          'Aucune matière dans cette catégorie',
                          style: pw.TextStyle(font: times, fontSize: 10, color: PdfColors.grey600),
                        ),
                      ),
                  ],
                ),
                ),
              );
            }),

            // Matières non classées
            if (courses.where((c) => c.categoryId == null).isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Anchor(
                name: 'cat_uncat',
                child: pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 16),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // En-tête pour les matières non classées
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey600,
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            width: 20,
                            height: 20,
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                '${courses.where((c) => c.categoryId == null).length}',
                                style: pw.TextStyle(font: timesBold, fontSize: 10, color: PdfColors.grey600),
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 12),
                          pw.Text(
                            'Matières non classées',
                            style: pw.TextStyle(font: timesBold, fontSize: 16, color: PdfColors.white),
                          ),
                        ],
                      ),
                    ),
                    
                    pw.SizedBox(height: 8),
                    
                    // Liste des matières non classées
                    pw.Container(
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: light, width: 1),
                      ),
                      child: pw.Table(
                        border: pw.TableBorder.all(color: light, width: 0.5),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(1),
                          1: const pw.FlexColumnWidth(3),
                          2: const pw.FlexColumnWidth(2),
                        },
                        children: [
                          // En-tête du tableau
                          pw.TableRow(
                            decoration: pw.BoxDecoration(color: lightBg),
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('N°', style: pw.TextStyle(font: timesBold, fontSize: 10)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('Matière', style: pw.TextStyle(font: timesBold, fontSize: 10)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text('Description', style: pw.TextStyle(font: timesBold, fontSize: 10)),
                              ),
                            ],
                          ),
                          // Données des matières non classées
                          ...courses.where((c) => c.categoryId == null).toList().asMap().entries.map((entry) {
                            final index = entry.key + 1;
                            final course = entry.value;
                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text('$index', style: pw.TextStyle(font: times, fontSize: 9)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(course.name, style: pw.TextStyle(font: timesBold, fontSize: 9)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                    course.description ?? '-',
                                    style: pw.TextStyle(font: times, fontSize: 8, color: PdfColors.grey600),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ],
          ]),
        ];
        },
      ),
    );
    return pdf.save();
  }
} 
