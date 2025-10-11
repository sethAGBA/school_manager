// Test pour vérifier l'implémentation des totaux dans les bulletins
// Ce fichier peut être utilisé pour tester la génération des totaux

import 'dart:io';
import 'package:school_manager/services/pdf_service.dart';
import 'package:school_manager/models/student.dart';
import 'package:school_manager/models/grade.dart';
import 'package:school_manager/models/school_info.dart';

void main() async {
  // Test des calculs de totaux
  print('🧮 Test des calculs de totaux pour les bulletins');

  // Données de test
  final student = Student(
    id: 'test-001',
    firstName: 'Jean',
    lastName: 'Dupont',
    className: '6ème A',
    academicYear: '2024-2025',
    dateOfBirth: '2010-05-15',
    gender: 'M',
    address: '123 Rue de Test',
    contactNumber: '0123456789',
    email: 'jean.dupont@test.com',
    emergencyContact: 'Marie Dupont - 0987654321',
    guardianName: 'Marie Dupont',
    guardianContact: '0987654321',
    enrollmentDate: '2024-09-01',
    status: 'Actif',
  );

  final schoolInfo = SchoolInfo(
    name: 'École Test',
    address: '123 Rue de Test',
    director: 'M. Directeur',
    ministry: 'Ministère de l\'Éducation',
    republic: 'République Française',
    republicMotto: 'Liberté, Égalité, Fraternité',
  );

  // Notes de test avec différents coefficients
  final grades = [
    Grade(
      id: 1,
      studentId: 'test-001',
      subjectId: 'math',
      subject: 'Mathématiques',
      type: 'Devoir',
      value: 15.0,
      maxValue: 20.0,
      coefficient: 4.0,
      className: '6ème A',
      academicYear: '2024-2025',
      term: 'Trimestre 1',
    ),
    Grade(
      id: 2,
      studentId: 'test-001',
      subjectId: 'math',
      subject: 'Mathématiques',
      type: 'Composition',
      value: 18.0,
      maxValue: 20.0,
      coefficient: 2.0,
      className: '6ème A',
      academicYear: '2024-2025',
      term: 'Trimestre 1',
    ),
    Grade(
      id: 3,
      studentId: 'test-001',
      subjectId: 'francais',
      subject: 'Français',
      type: 'Devoir',
      value: 12.0,
      maxValue: 20.0,
      coefficient: 3.0,
      className: '6ème A',
      academicYear: '2024-2025',
      term: 'Trimestre 1',
    ),
    Grade(
      id: 4,
      studentId: 'test-001',
      subjectId: 'francais',
      subject: 'Français',
      type: 'Composition',
      value: 14.0,
      maxValue: 20.0,
      coefficient: 2.0,
      className: '6ème A',
      academicYear: '2024-2025',
      term: 'Trimestre 1',
    ),
    Grade(
      id: 5,
      subjectId: 'histgeo',
      studentId: 'test-001',
      subject: 'Histoire-Géographie',
      type: 'Devoir',
      value: 16.0,
      maxValue: 20.0,
      coefficient: 2.0,
      className: '6ème A',
      academicYear: '2024-2025',
      term: 'Trimestre 1',
    ),
    Grade(
      id: 6,
      subjectId: 'histgeo',
      studentId: 'test-001',
      subject: 'Sciences',
      type: 'Devoir',
      value: 13.0,
      maxValue: 20.0,
      coefficient: 2.0,
      className: '6ème A',
      academicYear: '2024-2025',
      term: 'Trimestre 1',
    ),
    Grade(
      id: 7,
      subjectId: 'sciences',
      studentId: 'test-001',
      subject: 'Anglais',
      type: 'Devoir',
      value: 11.0,
      maxValue: 20.0,
      coefficient: 2.0,
      className: '6ème A',
      academicYear: '2024-2025',
      term: 'Trimestre 1',
    ),
    Grade(
      id: 8,
      subjectId: 'anglais',
      studentId: 'test-001',
      subject: 'EPS',
      type: 'Devoir',
      value: 17.0,
      maxValue: 20.0,
      coefficient: 1.0,
      className: '6ème A',
      academicYear: '2024-2025',
      term: 'Trimestre 1',
    ),
  ];

  // Professeurs et appréciations
  final professeurs = {
    'Mathématiques': 'M. Martin',
    'Français': 'Mme Dubois',
    'Histoire-Géographie': 'M. Leroy',
    'Sciences': 'Mme Petit',
    'Anglais': 'M. Brown',
    'EPS': 'M. Sport',
  };

  final appreciations = {
    'Mathématiques': 'Très bon travail, continuez ainsi',
    'Français': 'Bon travail, quelques efforts à fournir',
    'Histoire-Géographie': 'Excellent niveau',
    'Sciences': 'Travail satisfaisant',
    'Anglais': 'Des progrès à faire',
    'EPS': 'Très bonne participation',
  };

  final moyennesClasse = {
    'Mathématiques': '14.5',
    'Français': '12.8',
    'Histoire-Géographie': '15.2',
    'Sciences': '13.1',
    'Anglais': '10.5',
    'EPS': '16.3',
  };

  // Calculs manuels pour vérification
  print('\n📊 Calculs manuels de vérification:');

  // Mathématiques: (15*4 + 18*2) / (4+2) = (60 + 36) / 6 = 96/6 = 16.0
  final mathGrades = grades.where((g) => g.subject == 'Mathématiques').toList();
  double mathTotal = 0;
  double mathCoeff = 0;
  for (final g in mathGrades) {
    mathTotal += ((g.value / g.maxValue) * 20) * g.coefficient;
    mathCoeff += g.coefficient;
  }
  final mathMoyenne = mathTotal / mathCoeff;
  print(
    'Mathématiques: ${mathMoyenne.toStringAsFixed(2)} (coeff: ${mathCoeff})',
  );

  // Français: (12*3 + 14*2) / (3+2) = (36 + 28) / 5 = 64/5 = 12.8
  final francaisGrades = grades.where((g) => g.subject == 'Français').toList();
  double francaisTotal = 0;
  double francaisCoeff = 0;
  for (final g in francaisGrades) {
    francaisTotal += ((g.value / g.maxValue) * 20) * g.coefficient;
    francaisCoeff += g.coefficient;
  }
  final francaisMoyenne = francaisTotal / francaisCoeff;
  print(
    'Français: ${francaisMoyenne.toStringAsFixed(2)} (coeff: ${francaisCoeff})',
  );

  // Calcul des totaux
  final Map<String, double> subjectWeights = {
    'Mathématiques': 4.0,
    'Français': 3.0,
    'Histoire-Géographie': 2.0,
    'Sciences': 2.0,
    'Anglais': 2.0,
    'EPS': 1.0,
  };

  double sumCoefficients = 0;
  double sumPointsEleve = 0;
  double sumPointsClasse = 0;

  for (final subject in [
    'Mathématiques',
    'Français',
    'Histoire-Géographie',
    'Sciences',
    'Anglais',
    'EPS',
  ]) {
    final subjectGrades = grades.where((g) => g.subject == subject).toList();
    final devoirs = subjectGrades.where((g) => g.type == 'Devoir').toList();
    final compositions = subjectGrades
        .where((g) => g.type == 'Composition')
        .toList();

    double total = 0;
    double totalCoeff = 0;
    for (final g in [...devoirs, ...compositions]) {
      if (g.maxValue > 0 && g.coefficient > 0) {
        total += ((g.value / g.maxValue) * 20) * g.coefficient;
        totalCoeff += g.coefficient;
      }
    }
    final moyenneMatiere = totalCoeff > 0 ? (total / totalCoeff) : 0.0;
    final subjectWeight = subjectWeights[subject] ?? totalCoeff;

    sumCoefficients += subjectWeight;
    if (subjectGrades.isNotEmpty)
      sumPointsEleve += moyenneMatiere * subjectWeight;

    final mcText = moyennesClasse[subject] ?? '';
    final mcVal = double.tryParse(mcText.replaceAll(',', '.'));
    if (mcVal != null) sumPointsClasse += mcVal * subjectWeight;

    print(
      '$subject: Moyenne=${moyenneMatiere.toStringAsFixed(2)}, Coeff=${subjectWeight}, Points=${(moyenneMatiere * subjectWeight).toStringAsFixed(2)}',
    );
  }

  print('\n🎯 Totaux calculés:');
  print('Total Coefficients: ${sumCoefficients.toStringAsFixed(2)}');
  print('Total Points Élève: ${sumPointsEleve.toStringAsFixed(2)}');
  print('Total Points Classe: ${sumPointsClasse.toStringAsFixed(2)}');
  print(
    'Moyenne Générale: ${(sumPointsEleve / sumCoefficients).toStringAsFixed(2)}',
  );

  // Validation minimale des coefficients (aucune contrainte de somme = 20)
  final bool sumOk = sumCoefficients > 0;
  print(
    'Validation Coefficients: ${sumOk ? "✅ Somme > 0" : "❌ Somme ≤ 0"} (somme: ${sumCoefficients.toStringAsFixed(2)})',
  );

  print('\n📄 Génération du PDF de test...');

  try {
    final pdfBytes = await PdfService.generateReportCardPdf(
      student: student,
      schoolInfo: schoolInfo,
      grades: grades,
      professeurs: professeurs,
      appreciations: appreciations,
      moyennesClasse: moyennesClasse,
      appreciationGenerale:
          'Élève sérieux et appliqué. Bon niveau général avec des points forts en mathématiques et histoire-géographie.',
      decision: 'Admis en classe supérieure',
      recommandations: 'Continuer les efforts en français et anglais',
      forces: 'Mathématiques, Histoire-Géographie, EPS',
      pointsADevelopper: 'Français, Anglais',
      sanctions: 'Aucune',
      attendanceJustifiee: 2,
      attendanceInjustifiee: 0,
      retards: 1,
      presencePercent: 95.5,
      conduite: 'Très bonne conduite',
      telEtab: '01 23 45 67 89',
      mailEtab: 'contact@ecole-test.fr',
      webEtab: 'www.ecole-test.fr',
      titulaire: 'Mme Durand',
      subjects: [
        'Mathématiques',
        'Français',
        'Histoire-Géographie',
        'Sciences',
        'Anglais',
        'EPS',
      ],
      moyennesParPeriode: [14.2, 13.8, 15.1],
      moyenneGenerale: sumPointsEleve / sumCoefficients,
      rang: 5,
      exaequo: false,
      nbEleves: 25,
      mention: 'BIEN',
      allTerms: ['Trimestre 1', 'Trimestre 2', 'Trimestre 3'],
      periodLabel: 'Trimestre',
      selectedTerm: 'Trimestre 1',
      academicYear: '2024-2025',
      faitA: 'Paris',
      leDate: '15/12/2024',
      isLandscape: false,
      niveau: 'Collège',
      moyenneGeneraleDeLaClasse: sumPointsClasse / sumCoefficients,
      moyenneLaPlusForte: 17.5,
      moyenneLaPlusFaible: 8.2,
      moyenneAnnuelle: null,
    );

    // Sauvegarder le PDF de test
    final file = File('test_bulletin_totaux.pdf');
    await file.writeAsBytes(pdfBytes);
    print('✅ PDF généré avec succès: ${file.path}');
    print('📊 Taille du fichier: ${pdfBytes.length} bytes');
  } catch (e) {
    print('❌ Erreur lors de la génération du PDF: $e');
  }

  print('\n🎉 Test terminé!');
}
