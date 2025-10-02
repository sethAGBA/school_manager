# 🎯 Automatisation des Décisions du Conseil de Classe

## 📋 Vue d'ensemble

Le système d'automatisation des décisions du conseil de classe génère automatiquement une décision basée sur la moyenne annuelle de l'élève, **uniquement en fin d'année scolaire** (Trimestre 3 ou Semestre 2), tout en permettant une modification manuelle dans l'aperçu du bulletin.

## 🔧 Fonctionnalités Implémentées

### 1. **Calcul Automatique de la Décision**

#### **Logique de Décision :**
```dart
String? decisionAutomatique;
final bool isEndOfYear = selectedTerm == 'Trimestre 3' || selectedTerm == 'Semestre 2';

if (isEndOfYear) {
  if (moyenneAnnuelle != null) {
    if (moyenneAnnuelle >= 16) {
      decisionAutomatique = 'Admis en classe supérieure avec félicitations';
    } else if (moyenneAnnuelle >= 14) {
      decisionAutomatique = 'Admis en classe supérieure avec encouragements';
    } else if (moyenneAnnuelle >= 12) {
      decisionAutomatique = 'Admis en classe supérieure';
    } else if (moyenneAnnuelle >= 10) {
      decisionAutomatique = 'Admis en classe supérieure avec avertissement';
    } else if (moyenneAnnuelle >= 8) {
      decisionAutomatique = 'Admis en classe supérieure sous conditions';
    } else {
      decisionAutomatique = 'Redouble la classe';
    }
  } else {
    // Fallback sur la moyenne générale si pas de moyenne annuelle
    // Même logique appliquée à moyenneGenerale
  }
}
```

#### **Échelle des Décisions :**

| Moyenne Annuelle | Décision | Période d'Activation |
|------------------|----------|---------------------|
| **≥ 16.0** | Admis en classe supérieure avec félicitations | ✅ T3, S2 uniquement |
| **≥ 14.0** | Admis en classe supérieure avec encouragements | ✅ T3, S2 uniquement |
| **≥ 12.0** | Admis en classe supérieure | ✅ T3, S2 uniquement |
| **≥ 10.0** | Admis en classe supérieure avec avertissement | ✅ T3, S2 uniquement |
| **≥ 8.0** | Admis en classe supérieure sous conditions | ✅ T3, S2 uniquement |
| **< 8.0** | Redouble la classe | ✅ T3, S2 uniquement |

#### **Périodes d'Activation :**

| Période | Décisions Automatiques | Interface |
|---------|----------------------|-----------|
| **Trimestre 1** | ❌ Désactivées | Champ vide, pas de bouton |
| **Trimestre 2** | ❌ Désactivées | Champ vide, pas de bouton |
| **Semestre 1** | ❌ Désactivées | Champ vide, pas de bouton |
| **Trimestre 3** | ✅ Activées | Pré-remplissage + bouton |
| **Semestre 2** | ✅ Activées | Pré-remplissage + bouton |

### 2. **Pré-remplissage Automatique**

#### **Logique de Chargement :**
```dart
Future<void> loadReportCardSynthese() async {
  final row = await _dbService.getReportCard(...);
  if (row != null) {
    final decisionExistante = row['decision'] ?? '';
    if (decisionExistante.trim().isEmpty && isEndOfYear && decisionAutomatique != null) {
      decisionController.text = decisionAutomatique;  // ← Pré-remplissage automatique SEULEMENT en fin d'année
    } else {
      decisionController.text = decisionExistante;     // ← Garde la décision existante
    }
  } else {
    if (isEndOfYear && decisionAutomatique != null) {
      decisionController.text = decisionAutomatique;      // ← Nouveau bulletin SEULEMENT en fin d'année
    }
  }
}
```

#### **Comportement par Période :**

**En début d'année (T1, T2, S1) :**
- **Nouveau bulletin** : Champ vide, pas de pré-remplissage
- **Bulletin existant** : Garde la décision existante
- **Interface** : Pas de bouton refresh, pas d'indicateur automatique

**En fin d'année (T3, S2) :**
- **Nouveau bulletin** : Décision automatique pré-remplie
- **Bulletin existant vide** : Décision automatique pré-remplie
- **Bulletin existant avec décision** : Garde la décision existante
- **Interface** : Bouton refresh + indicateur automatique disponibles

### 3. **Interface Utilisateur**

#### **Bouton de Réinitialisation :**
```dart
// Bouton de réinitialisation seulement en fin d'année
if (isEndOfYear && decisionAutomatique != null)
  IconButton(
    onPressed: () {
      decisionController.text = decisionAutomatique!;
      saveSynthese();
    },
    icon: Icon(Icons.refresh, size: 18, color: mainColor),
    tooltip: 'Réinitialiser à la décision automatique',
  ),
```

#### **Indicateur Visuel :**
```dart
// Indicateur de décision automatique seulement en fin d'année
if (isEndOfYear && decisionAutomatique != null && decisionController.text == decisionAutomatique)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.blue.shade200),
    ),
    child: Row(
      children: [
        Icon(Icons.auto_awesome, size: 16, color: Colors.blue.shade600),
        Text('Décision automatique basée sur la moyenne annuelle (${moyenneAnnuelle?.toStringAsFixed(2) ?? moyenneGenerale.toStringAsFixed(2)})'),
      ],
    ),
  ),
```

### 4. **Sauvegarde Automatique**

#### **Persistance :**
```dart
Future<void> saveSynthese() async {
  await _dbService.insertOrUpdateReportCard(
    studentId: student.id,
    className: selectedClass ?? '',
    academicYear: effectiveYear,
    term: selectedTerm ?? '',
    decision: decisionController.text,  // ← Sauvegarde la décision (automatique ou manuelle)
    // ... autres champs
  );
}
```

## 🎨 Interface Utilisateur

### **Structure de l'Interface :**

```
┌─────────────────────────────────────────────────────────┐
│ Décision du conseil de classe :                    🔄  │
├─────────────────────────────────────────────────────────┤
│ 🤖 Décision automatique basée sur la moyenne annuelle  │
│    (15.80)                                             │
├─────────────────────────────────────────────────────────┤
│ [Champ de texte éditable]                              │
│ Admis en classe supérieure avec encouragements         │
└─────────────────────────────────────────────────────────┘
```

### **Éléments Visuels :**

1. **Titre avec bouton** : "Décision du conseil de classe :" + bouton refresh
2. **Indicateur automatique** : Badge bleu avec icône et moyenne affichée
3. **Champ éditable** : TextField permettant la modification
4. **Sauvegarde automatique** : À chaque modification

## 🔄 Flux de Fonctionnement

### **1. Chargement Initial :**
```
1. Calcul de la moyenne annuelle
2. Génération de la décision automatique
3. Chargement des données existantes
4. Pré-remplissage si nécessaire
5. Affichage de l'indicateur automatique
```

### **2. Modification Utilisateur :**
```
1. Utilisateur modifie le texte
2. Sauvegarde automatique déclenchée
3. Indicateur automatique disparaît
4. Décision personnalisée sauvegardée
```

### **3. Réinitialisation :**
```
1. Clic sur le bouton refresh
2. Restauration de la décision automatique
3. Sauvegarde automatique
4. Indicateur automatique réapparaît
```

## 📊 Cas d'Usage

### **Cas 1 : Nouveau Bulletin**
- Moyenne annuelle : 15.8
- Décision automatique : "Admis en classe supérieure avec encouragements"
- Interface : Pré-remplie avec indicateur automatique

### **Cas 2 : Modification Manuelle**
- Utilisateur change en : "Admis en classe supérieure avec félicitations"
- Interface : Indicateur automatique disparaît
- Sauvegarde : Décision personnalisée

### **Cas 3 : Réinitialisation**
- Clic sur bouton refresh
- Interface : Retour à la décision automatique
- Indicateur automatique réapparaît

### **Cas 4 : Fallback**
- Moyenne annuelle : null
- Moyenne générale : 13.2
- Décision automatique : "Admis en classe supérieure"

## 🧪 Tests

### **Fichier de Test :** `test_decision_automatique.dart`

**Exécution :**
```bash
dart test_decision_automatique.dart
```

**Tests Inclus :**
- ✅ Décisions pour différentes moyennes
- ✅ Test du fallback (moyenne générale)
- ✅ Validation des seuils
- ✅ Cas limites

## ⚙️ Configuration

### **Seuils Modifiables :**

Pour modifier les seuils de décision, éditez les valeurs dans le code :

```dart
// Dans grades_page.dart lignes 1685-1714 et 4575-4604
if (moyenneAnnuelle >= 16) {        // ← Seuil félicitations
  decisionAutomatique = 'Admis en classe supérieure avec félicitations';
} else if (moyenneAnnuelle >= 14) { // ← Seuil encouragements
  decisionAutomatique = 'Admis en classe supérieure avec encouragements';
} else if (moyenneAnnuelle >= 12) { // ← Seuil admission simple
  decisionAutomatique = 'Admis en classe supérieure';
} else if (moyenneAnnuelle >= 10) { // ← Seuil avertissement
  decisionAutomatique = 'Admis en classe supérieure avec avertissement';
} else if (moyenneAnnuelle >= 8) {  // ← Seuil conditions
  decisionAutomatique = 'Admis en classe supérieure sous conditions';
} else {                            // ← Seuil redoublement
  decisionAutomatique = 'Redouble la classe';
}
```

## 🎯 Avantages

1. **Automatisation** : Réduit le temps de saisie manuelle
2. **Cohérence** : Décisions basées sur des critères objectifs
3. **Flexibilité** : Possibilité de modification manuelle
4. **Transparence** : Indicateur visuel de l'automatisation
5. **Persistance** : Sauvegarde automatique des modifications
6. **Fallback** : Gestion des cas sans moyenne annuelle

## 🔧 Maintenance

### **Modification des Textes de Décision :**

Pour changer les textes des décisions, modifiez les chaînes dans le code :

```dart
// Exemple de personnalisation
if (moyenneAnnuelle >= 16) {
  decisionAutomatique = 'Admis en classe supérieure avec félicitations du conseil';
} else if (moyenneAnnuelle >= 14) {
  decisionAutomatique = 'Admis en classe supérieure avec encouragements du conseil';
}
```

### **Ajout de Nouveaux Seuils :**

```dart
// Exemple d'ajout d'un seuil intermédiaire
if (moyenneAnnuelle >= 18) {
  decisionAutomatique = 'Admis en classe supérieure avec félicitations exceptionnelles';
} else if (moyenneAnnuelle >= 16) {
  decisionAutomatique = 'Admis en classe supérieure avec félicitations';
} else if (moyenneAnnuelle >= 15) {
  decisionAutomatique = 'Admis en classe supérieure avec encouragements particuliers';
}
```

Ce système d'automatisation des décisions améliore significativement l'efficacité de la gestion des bulletins tout en conservant la flexibilité nécessaire pour les cas particuliers ! 🎉