import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:school_manager/models/signature.dart';
import 'package:school_manager/services/signature_assignment_service.dart';

class SignaturePdfService {
  final SignatureAssignmentService _assignmentService = SignatureAssignmentService();

  /// Récupère les signatures pour un bulletin
  Future<Map<String, Signature?>> getSignaturesForBulletin({
    required String className,
    required String titulaire,
  }) async {
    try {
      final futures = await Future.wait([
        _assignmentService.getTitulaireSignature(className),
        _assignmentService.getDirecteurSignature(),
        _assignmentService.getDirecteurCachet(),
      ]);

      return {
        'titulaire': futures[0],
        'directeur': futures[1],
        'cachet': futures[2],
      };
    } catch (e) {
      return {
        'titulaire': null,
        'directeur': null,
        'cachet': null,
      };
    }
  }

  /// Récupère les signatures pour un reçu de paiement
  Future<Map<String, Signature?>> getSignaturesForReceipt() async {
    try {
      final futures = await Future.wait([
        _assignmentService.getDirecteurSignature(),
        _assignmentService.getDirecteurCachet(),
      ]);

      return {
        'directeur': futures[0],
        'cachet': futures[1],
      };
    } catch (e) {
      return {
        'directeur': null,
        'cachet': null,
      };
    }
  }

  /// Crée un widget de signature pour le PDF
  pw.Widget createSignatureWidget({
    required Signature? signature,
    required String label,
    required double width,
    required double height,
    required pw.Font times,
    required PdfColor textColor,
    required PdfColor mainColor,
  }) {
    return pw.Container(
      width: width,
      height: height,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: times,
              color: mainColor,
              fontSize: 10,
            ),
          ),
          pw.SizedBox(height: 4),
          if (signature != null && signature.imagePath != null)
            pw.Container(
              width: width,
              height: height - 20,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Image(
                pw.MemoryImage(File(signature.imagePath!).readAsBytesSync()),
                fit: pw.BoxFit.contain,
              ),
            )
          else
            pw.Container(
              width: width,
              height: height - 20,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Center(
                child: pw.Text(
                  'Signature non disponible',
                  style: pw.TextStyle(
                    font: times,
                    color: PdfColors.grey400,
                    fontSize: 8,
                  ),
                ),
              ),
            ),
          pw.SizedBox(height: 2),
          pw.Text(
            signature?.name ?? '_________________',
            style: pw.TextStyle(
              font: times,
              color: textColor,
              fontSize: 8,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Crée un widget de cachet pour le PDF
  pw.Widget createCachetWidget({
    required Signature? cachet,
    required String label,
    required double width,
    required double height,
    required pw.Font times,
    required PdfColor textColor,
    required PdfColor mainColor,
  }) {
    return pw.Container(
      width: width,
      height: height,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: times,
              color: mainColor,
              fontSize: 10,
            ),
          ),
          pw.SizedBox(height: 4),
          if (cachet != null && cachet.imagePath != null)
            pw.Container(
              width: width,
              height: height - 20,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Image(
                pw.MemoryImage(File(cachet.imagePath!).readAsBytesSync()),
                fit: pw.BoxFit.contain,
              ),
            )
          else
            pw.Container(
              width: width,
              height: height - 20,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Center(
                child: pw.Text(
                  'Cachet non disponible',
                  style: pw.TextStyle(
                    font: times,
                    color: PdfColors.grey400,
                    fontSize: 8,
                  ),
                ),
              ),
            ),
          pw.SizedBox(height: 2),
          pw.Text(
            cachet?.name ?? '_________________',
            style: pw.TextStyle(
              font: times,
              color: textColor,
              fontSize: 8,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Crée le bloc de signatures complet pour un bulletin
  Future<pw.Widget> createBulletinSignatureBlock({
    required String className,
    required String titulaire,
    required String directeur,
    required pw.Font times,
    required pw.Font timesBold,
    required PdfColor mainColor,
    required PdfColor secondaryColor,
    required double baseFont,
    required double spacing,
    required bool isLandscape,
  }) async {
    final signatures = await getSignaturesForBulletin(
      className: className,
      titulaire: titulaire,
    );

    return pw.Container(
      padding: pw.EdgeInsets.all(isLandscape ? 6 : 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.blue100, width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: [
          // Signature du directeur
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Directeur(ice) :',
                  style: pw.TextStyle(
                    font: timesBold,
                    color: mainColor,
                    fontSize: baseFont,
                  ),
                ),
                pw.SizedBox(height: 4),
                if (directeur.isNotEmpty)
                  pw.Text(
                    directeur,
                    style: pw.TextStyle(
                      font: timesBold,
                      color: secondaryColor,
                      fontSize: baseFont,
                    ),
                  ),
                pw.SizedBox(height: 8),
                createSignatureWidget(
                  signature: signatures['directeur'],
                  label: 'Signature',
                  width: 120,
                  height: 60,
                  times: times,
                  textColor: secondaryColor,
                  mainColor: mainColor,
                ),
                pw.SizedBox(height: 8),
                createCachetWidget(
                  cachet: signatures['cachet'],
                  label: 'Cachet',
                  width: 120,
                  height: 40,
                  times: times,
                  textColor: secondaryColor,
                  mainColor: mainColor,
                ),
              ],
            ),
          ),
          pw.SizedBox(width: isLandscape ? 12 : 24),
          // Signature du titulaire
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Titulaire :',
                  style: pw.TextStyle(
                    font: timesBold,
                    color: mainColor,
                    fontSize: baseFont,
                  ),
                ),
                pw.SizedBox(height: 4),
                if (titulaire.isNotEmpty)
                  pw.Text(
                    titulaire,
                    style: pw.TextStyle(
                      font: timesBold,
                      color: secondaryColor,
                      fontSize: baseFont,
                    ),
                  ),
                pw.SizedBox(height: 8),
                createSignatureWidget(
                  signature: signatures['titulaire'],
                  label: 'Signature',
                  width: 120,
                  height: 60,
                  times: times,
                  textColor: secondaryColor,
                  mainColor: mainColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Crée le bloc de signatures pour un reçu de paiement
  Future<pw.Widget> createReceiptSignatureBlock({
    required String directeur,
    required pw.Font times,
    required pw.Font timesBold,
    required PdfColor mainColor,
    required PdfColor secondaryColor,
    required double baseFont,
    required double spacing,
  }) async {
    final signatures = await getSignaturesForReceipt();

    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.blue100, width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: [
          // Signature du directeur
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Directeur(ice) :',
                  style: pw.TextStyle(
                    font: timesBold,
                    color: mainColor,
                    fontSize: baseFont,
                  ),
                ),
                pw.SizedBox(height: 4),
                if (directeur.isNotEmpty)
                  pw.Text(
                    directeur,
                    style: pw.TextStyle(
                      font: timesBold,
                      color: secondaryColor,
                      fontSize: baseFont,
                    ),
                  ),
                pw.SizedBox(height: 8),
                createSignatureWidget(
                  signature: signatures['directeur'],
                  label: 'Signature',
                  width: 150,
                  height: 60,
                  times: times,
                  textColor: secondaryColor,
                  mainColor: mainColor,
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 24),
          // Cachet
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Cachet de l\'établissement',
                  style: pw.TextStyle(
                    font: timesBold,
                    color: mainColor,
                    fontSize: baseFont,
                  ),
                ),
                pw.SizedBox(height: 8),
                createCachetWidget(
                  cachet: signatures['cachet'],
                  label: 'Cachet',
                  width: 150,
                  height: 60,
                  times: times,
                  textColor: secondaryColor,
                  mainColor: mainColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}