// Test pour vérifier l'automatisation des décisions du conseil de classe
// Ce fichier peut être utilisé pour tester la logique de décision automatique

void main() {
  print('🎯 Test de l\'automatisation des décisions du conseil de classe');
  print(
    '📅 ATTENTION: Les décisions automatiques ne s\'affichent qu\'en fin d\'année (T3 ou S2)',
  );
  print('=' * 60);

  // Test des différentes moyennes et décisions correspondantes
  final testCases = [
    {
      'moyenne': 18.5,
      'expected': 'Admis en classe supérieure avec félicitations',
    },
    {
      'moyenne': 16.2,
      'expected': 'Admis en classe supérieure avec félicitations',
    },
    {
      'moyenne': 15.8,
      'expected': 'Admis en classe supérieure avec encouragements',
    },
    {
      'moyenne': 14.5,
      'expected': 'Admis en classe supérieure avec encouragements',
    },
    {'moyenne': 13.2, 'expected': 'Admis en classe supérieure'},
    {'moyenne': 12.0, 'expected': 'Admis en classe supérieure'},
    {
      'moyenne': 11.5,
      'expected': 'Admis en classe supérieure avec avertissement',
    },
    {
      'moyenne': 10.0,
      'expected': 'Admis en classe supérieure avec avertissement',
    },
    {'moyenne': 9.2, 'expected': 'Admis en classe supérieure sous conditions'},
    {'moyenne': 8.0, 'expected': 'Admis en classe supérieure sous conditions'},
    {'moyenne': 7.5, 'expected': 'Redouble la classe'},
    {'moyenne': 5.0, 'expected': 'Redouble la classe'},
  ];

  print('\n📊 Tests des décisions automatiques :');
  print('-' * 60);

  for (final testCase in testCases) {
    final moyenne = testCase['moyenne'] as double;
    final expected = testCase['expected'] as String;
    final decision = _getDecisionAutomatique(moyenne);

    final status = decision == expected ? '✅' : '❌';
    print('$status Moyenne: ${moyenne.toStringAsFixed(1)} → $decision');
    if (decision != expected) {
      print('   Attendu: $expected');
    }
  }

  print(
    '\n🔄 Test du fallback (moyenne générale si pas de moyenne annuelle) :',
  );
  print('-' * 60);

  // Test avec moyenne annuelle null
  final decisionFallback = _getDecisionAutomatiqueWithFallback(
    null,
    13.5,
    'Trimestre 3',
  );
  print(
    '✅ Moyenne annuelle: null, Moyenne générale: 13.5, T3 → $decisionFallback',
  );

  // Test avec moyenne annuelle disponible
  final decisionAnnuelle = _getDecisionAutomatiqueWithFallback(
    15.8,
    13.5,
    'Semestre 2',
  );
  print(
    '✅ Moyenne annuelle: 15.8, Moyenne générale: 13.5, S2 → $decisionAnnuelle',
  );

  print('\n🚫 Test des périodes non-automatiques :');
  print('-' * 60);

  // Test avec période non-automatique
  final decisionT1 = _getDecisionAutomatiqueWithFallback(
    15.8,
    13.5,
    'Trimestre 1',
  );
  print('❌ Moyenne annuelle: 15.8, Moyenne générale: 13.5, T1 → $decisionT1');

  final decisionS1 = _getDecisionAutomatiqueWithFallback(
    15.8,
    13.5,
    'Semestre 1',
  );
  print('❌ Moyenne annuelle: 15.8, Moyenne générale: 13.5, S1 → $decisionS1');

  print('\n📋 Résumé des seuils de décision :');
  print('-' * 60);
  print('≥ 16.0 : Admis en classe supérieure avec félicitations');
  print('≥ 14.0 : Admis en classe supérieure avec encouragements');
  print('≥ 12.0 : Admis en classe supérieure');
  print('≥ 10.0 : Admis en classe supérieure avec avertissement');
  print('≥ 8.0  : Admis en classe supérieure sous conditions');
  print('< 8.0  : Redouble la classe');

  print('\n📅 Périodes d\'activation :');
  print('-' * 60);
  print('✅ Trimestre 3 : Décisions automatiques activées');
  print('✅ Semestre 2  : Décisions automatiques activées');
  print('❌ Trimestre 1 : Décisions automatiques désactivées');
  print('❌ Trimestre 2 : Décisions automatiques désactivées');
  print('❌ Semestre 1  : Décisions automatiques désactivées');

  print('\n🎉 Tests terminés !');
}

/// Fonction de test pour obtenir la décision automatique basée sur la moyenne
String _getDecisionAutomatique(double moyenne) {
  if (moyenne >= 16) {
    return 'Admis en classe supérieure avec félicitations';
  } else if (moyenne >= 14) {
    return 'Admis en classe supérieure avec encouragements';
  } else if (moyenne >= 12) {
    return 'Admis en classe supérieure';
  } else if (moyenne >= 10) {
    return 'Admis en classe supérieure avec avertissement';
  } else if (moyenne >= 8) {
    return 'Admis en classe supérieure sous conditions';
  } else {
    return 'Redouble la classe';
  }
}

/// Fonction de test pour obtenir la décision avec fallback et vérification de période
String _getDecisionAutomatiqueWithFallback(
  double? moyenneAnnuelle,
  double moyenneGenerale,
  String selectedTerm,
) {
  // Vérifier si on est en fin d'année
  final bool isEndOfYear =
      selectedTerm == 'Trimestre 3' || selectedTerm == 'Semestre 2';

  if (!isEndOfYear) {
    return 'Aucune décision automatique (pas en fin d\'année)';
  }

  if (moyenneAnnuelle != null) {
    return _getDecisionAutomatique(moyenneAnnuelle);
  } else {
    return _getDecisionAutomatique(moyenneGenerale);
  }
}
