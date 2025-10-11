// services/pdf_export_service.dart
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';

class PdfExportService {
  /// Génère et exporte l'emploi du temps en PDF
  static Future<File> exporterEmploiDuTemps({
    required EmploiDuTemps emploiDuTemps,
    required List<Classe> classes,
    required List<Matiere> matieres,
    required List<Professeur> professeurs,
    required List<Salle> salles,
    String? classeId,
  }) async {
    final pdf = pw.Document();

    if (classeId != null) {
      // Export pour une classe spécifique
      final classe = classes.firstWhere((c) => c.id == classeId);
      final cours = emploiDuTemps.getCoursParClasse(classeId);
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) => _buildClassePage(
            classe: classe,
            cours: cours,
            matieres: matieres,
            professeurs: professeurs,
            salles: salles,
          ),
        ),
      );
    } else {
      // Export pour toutes les classes
      for (var classe in classes) {
        final cours = emploiDuTemps.getCoursParClasse(classe.id);
        
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            build: (context) => _buildClassePage(
              classe: classe,
              cours: cours,
              matieres: matieres,
              professeurs: professeurs,
              salles: salles,
            ),
          ),
        );
      }
    }

    // Sauvegarder le fichier
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/emploi_du_temps_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  /// Construit la page PDF pour une classe
  static pw.Widget _buildClassePage({
    required Classe classe,
    required List<Cours> cours,
    required List<Matiere> matieres,
    required List<Professeur> professeurs,
    required List<Salle> salles,
  }) {
    final jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi'];
    final heures = [
      '8h-9h',
      '9h-10h',
      '10h-11h',
      '11h-12h',
      '12h-13h',
      '13h-14h',
      '14h-15h',
      '15h-16h',
      '16h-17h',
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // En-tête
        pw.Container(
          padding: pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'EMPLOI DU TEMPS',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Classe: ${classe.nom}',
                style: pw.TextStyle(fontSize: 18),
              ),
              pw.Text(
                'Année scolaire: ${DateTime.now().year}-${DateTime.now().year + 1}',
                style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 10),

        // Tableau
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey),
            columnWidths: {
              0: pw.FixedColumnWidth(60),
              for (int i = 1; i <= 5; i++) i: pw.FlexColumnWidth(1),
            },
            children: [
              // En-tête du tableau
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.blue100),
                children: [
                  _buildHeaderCell('Heures'),
                  ...jours.map((jour) => _buildHeaderCell(jour)),
                ],
              ),

              // Lignes de cours
              ...List.generate(heures.length, (index) {
                return pw.TableRow(
                  children: [
                    _buildCell(heures[index], isHeader: true),
                    ...List.generate(5, (jourIndex) {
                      final creneau = Creneau(
                        jour: jourIndex,
                        heureDebut: 480 + (index * 60),
                        duree: 60,
                      );

                      final coursAuCreneau = cours.firstWhere(
                        (c) => c.creneau == creneau,
                        orElse: () => Cours(
                          id: '',
                          classeId: '',
                          matiereId: '',
                          professeurId: '',
                        ),
                      );

                      if (coursAuCreneau.id.isEmpty) {
                        return _buildCell('');
                      }

                      final matiere = matieres.firstWhere(
                        (m) => m.id == coursAuCreneau.matiereId,
                      );
                      final prof = professeurs.firstWhere(
                        (p) => p.id == coursAuCreneau.professeurId,
                      );
                      final salle = salles.firstWhere(
                        (s) => s.id == coursAuCreneau.salleId,
                        orElse: () => Salle(id: '', nom: 'N/A', capacite: 0),
                      );

                      return _buildCoursCell(
                        matiere: matiere.nom,
                        prof: '${prof.prenom} ${prof.nom}',
                        salle: salle.nom,
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),

        // Pied de page
        pw.Container(
          padding: pw.EdgeInsets.all(10),
          child: pw.Text(
            'Généré le ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
        ),
      ],
    );
  }

  /// Cellule d'en-tête
  static pw.Widget _buildHeaderCell(String text) {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Cellule simple
  static pw.Widget _buildCell(String text, {bool isHeader = false}) {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      alignment: pw.Alignment.center,
      decoration: isHeader
          ? pw.BoxDecoration(color: PdfColors.grey200)
          : null,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Cellule de cours
  static pw.Widget _buildCoursCell({
    required String matiere,
    required String prof,
    required String salle,
  }) {
    return pw.Container(
      padding: pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            matiere,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            prof,
            style: pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
          ),
          pw.Text(
            salle,
            style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  /// Partage le PDF
  static Future<void> partagerPdf(File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Emploi du temps',
    );
  }

  /// Export pour les professeurs
  static Future<File> exporterEmploiDuTempsProf({
    required EmploiDuTemps emploiDuTemps,
    required Professeur professeur,
    required List<Classe> classes,
    required List<Matiere> matieres,
    required List<Salle> salles,
  }) async {
    final pdf = pw.Document();
    final cours = emploiDuTemps.getCoursParProfesseur(professeur.id);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => _buildProfPage(
          professeur: professeur,
          cours: cours,
          classes: classes,
          matieres: matieres,
          salles: salles,
        ),
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/emploi_du_temps_prof_${professeur.nom}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  /// Page PDF pour un professeur
  static pw.Widget _buildProfPage({
    required Professeur professeur,
    required List<Cours> cours,
    required List<Classe> classes,
    required List<Matiere> matieres,
    required List<Salle> salles,
  }) {
    final jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi'];
    final heures = [
      '8h-9h', '9h-10h', '10h-11h', '11h-12h',
      '12h-13h', '13h-14h', '14h-15h', '15h-16h', '16h-17h',
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'EMPLOI DU TEMPS - PROFESSEUR',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                '${professeur.prenom} ${professeur.nom}',
                style: pw.TextStyle(fontSize: 18),
              ),
              pw.Text(
                'Année scolaire: ${DateTime.now().year}-${DateTime.now().year + 1}',
                style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 10),

        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey),
            columnWidths: {
              0: pw.FixedColumnWidth(60),
              for (int i = 1; i <= 5; i++) i: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.green100),
                children: [
                  _buildHeaderCell('Heures'),
                  ...jours.map((jour) => _buildHeaderCell(jour)),
                ],
              ),

              ...List.generate(heures.length, (index) {
                return pw.TableRow(
                  children: [
                    _buildCell(heures[index], isHeader: true),
                    ...List.generate(5, (jourIndex) {
                      final creneau = Creneau(
                        jour: jourIndex,
                        heureDebut: 480 + (index * 60),
                        duree: 60,
                      );

                      final coursAuCreneau = cours.firstWhere(
                        (c) => c.creneau == creneau,
                        orElse: () => Cours(
                          id: '',
                          classeId: '',
                          matiereId: '',
                          professeurId: '',
                        ),
                      );

                      if (coursAuCreneau.id.isEmpty) {
                        return _buildCell('');
                      }

                      final matiere = matieres.firstWhere(
                        (m) => m.id == coursAuCreneau.matiereId,
                      );
                      final classe = classes.firstWhere(
                        (c) => c.id == coursAuCreneau.classeId,
                      );
                      final salle = salles.firstWhere(
                        (s) => s.id == coursAuCreneau.salleId,
                        orElse: () => Salle(id: '', nom: 'N/A', capacite: 0),
                      );

                      return _buildCoursCell(
                        matiere: matiere.nom,
                        prof: classe.nom,
                        salle: salle.nom,
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),

        pw.Container(
          padding: pw.EdgeInsets.all(10),
          child: pw.Text(
            'Généré le ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
        ),
      ],
    );
  }
}