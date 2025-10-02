
import 'package:flutter/material.dart';
import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:intl/intl.dart';

import 'package:school_manager/models/school_info.dart';

class StatisticsModal extends StatefulWidget {
  final String? className;
  final String? academicYear;
  final String? term;
  final List<Student> students;
  final List<Grade> grades;
  final List<Course> subjects;
  final DatabaseService dbService;

  const StatisticsModal({
    Key? key,
    required this.className,
    required this.academicYear,
    required this.term,
    required this.students,
    required this.grades,
    required this.subjects,
    required this.dbService,
  }) : super(key: key);

  @override
  _StatisticsModalState createState() => _StatisticsModalState();
}

class _StatisticsModalState extends State<StatisticsModal> {
  bool isLoading = true;
  Map<String, dynamic> stats = {};
  late SchoolInfo schoolInfo;

  @override
  void initState() {
    super.initState();
    _loadSchoolInfo();
    _loadStats();
  }

  Future<void> _loadSchoolInfo() async {
    schoolInfo = await loadSchoolInfo();
  }

  Future<void> _loadStats() async {
    if (widget.className == null || widget.academicYear == null || widget.term == null) {
      setState(() => isLoading = false);
      return;
    }

    final classStudents = widget.students.where((s) => s.className == widget.className && s.academicYear == widget.academicYear).toList();
    stats['student_count'] = classStudents.length;

    // Calculate general average for each student
    List<Map<String, dynamic>> studentAverages = [];
    for (var student in classStudents) {
      double totalPoints = 0;
      double totalCoefficients = 0;
      final studentGrades = widget.grades.where((g) => g.studentId == student.id && g.term == widget.term);

      for (var grade in studentGrades) {
        if (grade.value > 0 && grade.maxValue > 0 && grade.coefficient > 0) {
          totalPoints += (grade.value / grade.maxValue) * 20 * grade.coefficient;
          totalCoefficients += grade.coefficient;
        }
      }

      if (totalCoefficients > 0) {
        studentAverages.add({
          'student': student,
          'average': totalPoints / totalCoefficients,
        });
      }
    }

    // Classement par mérite (avec ex æquo)
    studentAverages.sort((a, b) => b['average'].compareTo(a['average']));
    const double eps = 0.001; // tolérance d'égalité des moyennes
    int position = 0; // position 1..N
    int currentRank = 0; // rang affiché (standard competition ranking)
    double? prevAvg;
    for (int i = 0; i < studentAverages.length; i++) {
      final entry = studentAverages[i];
      position += 1;
      final double avg = entry['average'] as double;
      if (prevAvg == null || (avg - prevAvg!).abs() > eps) {
        currentRank = position;
        prevAvg = avg;
      }
      // Ex æquo si voisin (précédent ou suivant) a même moyenne
      bool ex = false;
      if (i > 0) {
        final double prev = (studentAverages[i - 1]['average'] as double);
        if ((avg - prev).abs() <= eps) ex = true;
      }
      if (!ex && i < studentAverages.length - 1) {
        final double next = (studentAverages[i + 1]['average'] as double);
        if ((avg - next).abs() <= eps) ex = true;
      }
      entry['rank'] = currentRank;
      entry['exaequo'] = ex;
    }
    stats['merit_ranking'] = studentAverages;

    // Top 3 et Bottom 3
    stats['top_3_students'] = studentAverages.take(3).toList();
    stats['bottom_3_students'] = studentAverages.reversed.take(3).toList();

    // Taux de réussite par matière & Moyennes de classe par matière
    Map<String, double> successRateBySubject = {};
    Map<String, double> classAverageBySubject = {};
    for (var subject in widget.subjects) {
      int studentsWithAverage = 0;
      double totalSubjectAverage = 0;
      int studentCountForSubject = 0;

      for (var student in classStudents) {
        final subjectGrades = widget.grades.where((g) => g.studentId == student.id && g.subject == subject.name && g.term == widget.term);
        double totalPoints = 0;
        double totalCoefficients = 0;

        for (var grade in subjectGrades) {
          if (grade.value > 0 && grade.maxValue > 0 && grade.coefficient > 0) {
            totalPoints += (grade.value / grade.maxValue) * 20 * grade.coefficient;
            totalCoefficients += grade.coefficient;
          }
        }

        if (totalCoefficients > 0) {
          double studentSubjectAverage = totalPoints / totalCoefficients;
          totalSubjectAverage += studentSubjectAverage;
          studentCountForSubject++;
          if (studentSubjectAverage >= 10) {
            studentsWithAverage++;
          }
        }
      }

      if (classStudents.isNotEmpty) {
        successRateBySubject[subject.name] = (studentsWithAverage / classStudents.length) * 100;
      }
      if (studentCountForSubject > 0) {
        classAverageBySubject[subject.name] = totalSubjectAverage / studentCountForSubject;
      }
    }
    stats['success_rate_by_subject'] = successRateBySubject;
    stats['class_average_by_subject'] = classAverageBySubject;

    // Nombre d'élèves par tranche de notes
    stats['excellent_students'] = studentAverages.where((s) => s['average'] >= 16).length;
    stats['bien_students'] = studentAverages.where((s) => s['average'] >= 14 && s['average'] < 16).length;
    stats['assez_bien_students'] = studentAverages.where((s) => s['average'] >= 12 && s['average'] < 14).length;
    stats['passable_students'] = studentAverages.where((s) => s['average'] >= 10 && s['average'] < 12).length;
    stats['insuffisant_students'] = studentAverages.where((s) => s['average'] < 10).length;

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.className == null || widget.academicYear == null || widget.term == null) {
      return const AlertDialog(
        title: Text("Statistiques"),
        content: Text("Veuillez sélectionner une classe, une année académique et une période pour voir les statistiques."),
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFFF0F4F8),
      title: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.analytics, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text("Statistiques - ${widget.className}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Année Académique: ${widget.academicYear}"),
            Text("Période: ${widget.term}"),
            const SizedBox(height: 20),
            _buildStatCard("Nombre d'élèves", stats['student_count'].toString(), Icons.people),
            _buildDivider(),
            _buildRankingSection(),
            _buildDivider(),
            _buildSubjectStatsSection(),
            _buildDivider(),
            _buildGradeDistributionSection(),
            _buildDivider(),
            _buildTopBottomStudentsSection(),
          ],
        ),
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: _exportToExcel,
          icon: const Icon(Icons.grid_on, color: Colors.white),
          label: const Text('Exporter en Excel'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _exportToPdf,
          icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
          label: const Text('Exporter en PDF'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Future<void> _exportToExcel() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return; // User canceled the picker

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Statistiques'];

    // Headers
    sheetObject.appendRow([TextCellValue('Statistiques pour la classe ${widget.className}')]);
    sheetObject.appendRow([TextCellValue('Année Académique: ${widget.academicYear}'), TextCellValue('Période: ${widget.term}')]);
    sheetObject.appendRow([]);

    // Ranking
    sheetObject.appendRow([TextCellValue('Classement par mérite')]);
    sheetObject.appendRow([TextCellValue('Rang'), TextCellValue('Élève'), TextCellValue('Moyenne'), TextCellValue('Ex æquo')]);
    final List<Map<String, dynamic>> ranking = stats['merit_ranking'];
    for (var i = 0; i < ranking.length; i++) {
      sheetObject.appendRow([
        IntCellValue((ranking[i]['rank'] ?? (i + 1)) as int),
        TextCellValue(ranking[i]['student'].name),
        DoubleCellValue(ranking[i]['average']),
        TextCellValue(((ranking[i]['exaequo'] as bool?) ?? false) ? 'Oui' : 'Non'),
      ]);
    }
    sheetObject.appendRow([]);

    // Subject Stats
    sheetObject.appendRow([TextCellValue('Statistiques par matière')]);
    sheetObject.appendRow([TextCellValue('Matière'), TextCellValue('Taux de réussite'), TextCellValue('Moyenne de classe')]);
    final Map<String, double> successRate = stats['success_rate_by_subject'];
    final Map<String, double> classAverage = stats['class_average_by_subject'];
    for (var subject in widget.subjects) {
      sheetObject.appendRow([
        TextCellValue(subject.name),
        DoubleCellValue(successRate[subject.name] ?? 0),
        DoubleCellValue(classAverage[subject.name] ?? 0)
      ]);
    }
    sheetObject.appendRow([]);

    // Grade Distribution
    sheetObject.appendRow([TextCellValue('Répartition des notes')]);
    sheetObject.appendRow([TextCellValue('Excellent (>= 16)'), IntCellValue(stats['excellent_students'])]);
    sheetObject.appendRow([TextCellValue('Bien (14-16)'), IntCellValue(stats['bien_students'])]);
    sheetObject.appendRow([TextCellValue('Assez Bien (12-14)'), IntCellValue(stats['assez_bien_students'])]);
    sheetObject.appendRow([TextCellValue('Passable (10-12)'), IntCellValue(stats['passable_students'])]);
    sheetObject.appendRow([TextCellValue('Insuffisant (< 10)'), IntCellValue(stats['insuffisant_students'])]);
    sheetObject.appendRow([]);

    // Top/Bottom 3
    sheetObject.appendRow([TextCellValue('Top 3 des élèves')]);
    final List<Map<String, dynamic>> top3 = stats['top_3_students'];
    for (var s in top3) {
      sheetObject.appendRow([TextCellValue(s['student'].name), DoubleCellValue(s['average'])]);
    }
    sheetObject.appendRow([]);
    sheetObject.appendRow([TextCellValue('3 derniers élèves')]);
    final List<Map<String, dynamic>> bottom3 = stats['bottom_3_students'];
    for (var s in bottom3) {
      sheetObject.appendRow([TextCellValue(s['student'].name), DoubleCellValue(s['average'])]);
    }

    // Save file
    final path = '$directory/statistiques_${widget.className}.xlsx';
    final file = File(path);
    await file.writeAsBytes(excel.encode()!);

    OpenFile.open(path);
  }

  Future<void> _exportToPdf() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return; // User canceled the picker

    final pdf = pw.Document();
    final times = await pw.Font.times();
    final timesBold = await pw.Font.timesBold();
    final primary = PdfColor.fromHex('#1F2937');
    final accent = PdfColor.fromHex('#2563EB');
    final light = PdfColor.fromHex('#F3F4F6');

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
                          'Année académique: ${widget.academicYear}  •  Généré le: ' + DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
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
            pw.Text('Rapport de Statistiques - ${widget.className}', style: pw.TextStyle(font: timesBold, fontSize: 20, color: accent, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),

            // Ranking
            pw.Text('Classement par mérite', style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent)),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(font: timesBold, fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: light),
              headers: ['Rang', 'Élève', 'Moyenne', 'Ex æquo'],
              data: (stats['merit_ranking'] as List<Map<String, dynamic>>).map((e) => [
                (e['rank'] ?? '').toString(),
                e['student'].name,
                (e['average'] as double).toStringAsFixed(2),
                ((e['exaequo'] as bool?) ?? false) ? 'Oui' : 'Non',
              ]).toList(),
            ),
            pw.SizedBox(height: 16),

            // Subject Stats
            pw.Text('Statistiques par matière', style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent)),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(font: timesBold, fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: light),
              headers: ['Matière', 'Taux de réussite', 'Moyenne de classe'],
              data: widget.subjects.map((s) => [
                s.name,
                '${stats['success_rate_by_subject'][s.name]?.toStringAsFixed(2) ?? 'N/A'}%',
                stats['class_average_by_subject'][s.name]?.toStringAsFixed(2) ?? 'N/A',
              ]).toList(),
            ),
            pw.SizedBox(height: 16),

            // Grade Distribution
            pw.Text('Répartition des notes', style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent)),
            pw.SizedBox(height: 6),
            pw.Text('Excellent (>= 16): ${stats['excellent_students']}'),
            pw.Text('Bien (14-16): ${stats['bien_students']}'),
            pw.Text('Assez Bien (12-14): ${stats['assez_bien_students']}'),
            pw.Text('Passable (10-12): ${stats['passable_students']}'),
            pw.Text('Insuffisant (< 10): ${stats['insuffisant_students']}'),
            pw.SizedBox(height: 16),

            // Top/Bottom 3
            pw.Text('Top 3 des élèves', style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent)),
            ...(stats['top_3_students'] as List<Map<String, dynamic>>).map((s) => pw.Text('${s['student'].name}: ${s['average'].toStringAsFixed(2)}')),
            pw.SizedBox(height: 10),
            pw.Text('3 derniers élèves', style: pw.TextStyle(font: timesBold, fontSize: 14, color: accent)),
            ...(stats['bottom_3_students'] as List<Map<String, dynamic>>).map((s) => pw.Text('${s['student'].name}: ${s['average'].toStringAsFixed(2)}')),
          ];
        },
      ),
    );

    final path = '$directory/statistiques_${widget.className}.pdf';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    OpenFile.open(path);
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16.0),
      child: Divider(height: 1, color: Colors.grey),
    );
  }

  Widget _buildRankingSection() {
    final List<Map<String, dynamic>> ranking = stats['merit_ranking'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.emoji_events, color: Colors.amber),
            SizedBox(width: 8),
            Text("Classement par mérite", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        DataTable(
          columns: const [
            DataColumn(label: Text("Rang")),
            DataColumn(label: Text("Élève")),
            DataColumn(label: Text("Moyenne")),
          ],
          rows: ranking.map((entry) {
            int rank = (entry['rank'] as int?) ?? 0;
            bool ex = (entry['exaequo'] as bool?) ?? false;
            Student student = entry['student'];
            double average = entry['average'];
            return DataRow(
              cells: [
                DataCell(Text(ex ? '$rank (ex æquo)' : rank.toString())),
                DataCell(Text(student.name)),
                DataCell(Text(average.toStringAsFixed(2))),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubjectStatsSection() {
    final Map<String, double> successRate = stats['success_rate_by_subject'];
    final Map<String, double> classAverage = stats['class_average_by_subject'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.subject, color: Colors.blue),
            SizedBox(width: 8),
            Text("Statistiques par matière", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        DataTable(
          columns: const [
            DataColumn(label: Text("Matière")),
            DataColumn(label: Text("Taux de réussite")),
            DataColumn(label: Text("Moyenne de classe")),
          ],
          rows: widget.subjects.map((subject) {
            return DataRow(
              cells: [
                DataCell(Text(subject.name)),
                DataCell(Text("${successRate[subject.name]?.toStringAsFixed(2) ?? 'N/A'}%")),
                DataCell(Text(classAverage[subject.name]?.toStringAsFixed(2) ?? 'N/A')),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGradeDistributionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.pie_chart, color: Colors.green),
            SizedBox(width: 8),
            Text("Répartition des notes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        _buildStatCard("Excellent (>= 16)", stats['excellent_students'].toString(), Icons.star, color: Colors.amber),
        _buildStatCard("Bien (14-16)", stats['bien_students'].toString(), Icons.thumb_up, color: Colors.lightGreen),
        _buildStatCard("Assez Bien (12-14)", stats['assez_bien_students'].toString(), Icons.check_circle, color: Colors.blue),
        _buildStatCard("Passable (10-12)", stats['passable_students'].toString(), Icons.check, color: Colors.orange),
        _buildStatCard("Insuffisant (< 10)", stats['insuffisant_students'].toString(), Icons.warning, color: Colors.red),
      ],
    );
  }

  Widget _buildTopBottomStudentsSection() {
    final List<Map<String, dynamic>> top3 = stats['top_3_students'];
    final List<Map<String, dynamic>> bottom3 = stats['bottom_3_students'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.arrow_upward, color: Colors.green),
            SizedBox(width: 8),
            Text("Top 3 des élèves", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        ...top3.map((s) => Text("${s['student'].name}: ${s['average'].toStringAsFixed(2)}")),
        const SizedBox(height: 20),
        Row(
          children: const [
            Icon(Icons.arrow_downward, color: Colors.red),
            SizedBox(width: 8),
            Text("3 derniers élèves", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        ...bottom3.map((s) => Text("${s['student'].name}: ${s['average'].toStringAsFixed(2)}")),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, {Color color = Colors.blue}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 16),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 18, color: Colors.blue)),
          ],
        ),
      ),
    );
  }
}
