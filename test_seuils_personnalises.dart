// Test pour vérifier le système de seuils personnalisés par classe
// Ce fichier peut être utilisé pour tester la logique de décision avec des seuils personnalisés

void main() {
  print('🎯 Test du système de seuils personnalisés par classe');
  print('=' * 60);

  // Test des différentes configurations de seuils par classe
  final testClasses = [
    {
      'nom': '6ème A - École stricte',
      'seuils': {
        'felicitations': 18.0,
        'encouragements': 16.0,
        'admission': 14.0,
        'avertissement': 12.0,
        'conditions': 10.0,
        'redoublement': 10.0,
      },
      'description': 'École avec des critères très élevés'
    },
    {
      'nom': '6ème B - École standard',
      'seuils': {
        'felicitations': 16.0,
        'encouragements': 14.0,
        'admission': 12.0,
        'avertissement': 10.0,
        'conditions': 8.0,
        'redoublement': 8.0,
      },
      'description': 'École avec des critères standards'
    },
    {
      'nom': '6ème C - École permissive',
      'seuils': {
        'felicitations': 14.0,
        'encouragements': 12.0,
        'admission': 10.0,
        'avertissement': 8.0,
        'conditions': 6.0,
        'redoublement': 6.0,
      },
      'description': 'École avec des critères plus permissifs'
    },
    {
      'nom': 'Terminale A - Lycée d\'excellence',
      'seuils': {
        'felicitations': 17.0,
        'encouragements': 15.0,
        'admission': 13.0,
        'avertissement': 11.0,
        'conditions': 9.0,
        'redoublement': 9.0,
      },
      'description': 'Lycée d\'excellence avec critères élevés'
    },
  ];

  print('\n📊 Tests des configurations de seuils par classe :');
  print('-' * 60);

  for (final classe in testClasses) {
    final nom = classe['nom'] as String;
    final seuils = classe['seuils'] as Map<String, double>;
    final description = classe['description'] as String;
    
    print('\n🏫 $nom');
    print('   $description');
    print('   Seuils: Félicitations≥${seuils['felicitations']}, Encouragements≥${seuils['encouragements']}, Admission≥${seuils['admission']}, Avertissement≥${seuils['avertissement']}, Conditions≥${seuils['conditions']}, Redoublement<${seuils['redoublement']}');
    
    // Test avec différentes moyennes
    final testMoyennes = [19.5, 17.0, 15.5, 13.0, 11.5, 9.5, 7.0, 5.0];
    
    for (final moyenne in testMoyennes) {
      final decision = _getDecisionAvecSeuils(moyenne, seuils);
      print('   📈 Moyenne: ${moyenne.toStringAsFixed(1)} → $decision');
    }
  }

  print('\n🔄 Test de comparaison entre établissements :');
  print('-' * 60);
  
  final moyenneTest = 13.5;
  print('📊 Moyenne de test: ${moyenneTest.toStringAsFixed(1)}');
  
  for (final classe in testClasses) {
    final nom = classe['nom'] as String;
    final seuils = classe['seuils'] as Map<String, double>;
    final decision = _getDecisionAvecSeuils(moyenneTest, seuils);
    print('   🏫 $nom → $decision');
  }

  print('\n📋 Résumé des avantages du système :');
  print('-' * 60);
  print('✅ Personnalisation par établissement');
  print('✅ Adaptation aux niveaux de classe');
  print('✅ Flexibilité des critères de passage');
  print('✅ Cohérence avec les politiques éducatives');
  print('✅ Gestion des cas particuliers');
  print('✅ Interface de configuration intuitive');

  print('\n🎉 Tests terminés !');
}

/// Fonction de test pour obtenir la décision avec des seuils personnalisés
String _getDecisionAvecSeuils(double moyenne, Map<String, double> seuils) {
  if (moyenne >= seuils['felicitations']!) {
    return 'Admis en classe supérieure avec félicitations';
  } else if (moyenne >= seuils['encouragements']!) {
    return 'Admis en classe supérieure avec encouragements';
  } else if (moyenne >= seuils['admission']!) {
    return 'Admis en classe supérieure';
  } else if (moyenne >= seuils['avertissement']!) {
    return 'Admis en classe supérieure avec avertissement';
  } else if (moyenne >= seuils['conditions']!) {
    return 'Admis en classe supérieure sous conditions';
  } else {
    return 'Redouble la classe';
  }
}