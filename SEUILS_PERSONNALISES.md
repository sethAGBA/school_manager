# 🎯 Système de Seuils de Passage Personnalisés par Classe

## 📋 Vue d'ensemble

Le système de seuils personnalisés permet à chaque établissement de configurer ses propres critères de passage en classe supérieure, adaptés à ses politiques éducatives et au niveau de ses élèves.

## 🔧 Fonctionnalités Implémentées

### **1. Configuration par Classe**

Chaque classe peut avoir ses propres seuils de passage :

| Seuil | Description | Valeur par défaut |
|-------|-------------|-------------------|
| **Félicitations** | Moyenne minimale pour les félicitations | 16.0 |
| **Encouragements** | Moyenne minimale pour les encouragements | 14.0 |
| **Admission** | Moyenne minimale pour l'admission simple | 12.0 |
| **Avertissement** | Moyenne minimale pour l'admission avec avertissement | 10.0 |
| **Sous conditions** | Moyenne minimale pour l'admission sous conditions | 8.0 |
| **Redoublement** | Moyenne maximale pour le redoublement | 8.0 |

### **2. Interface de Configuration**

#### **Localisation :** Détails de la classe → Section "Seuils de passage"

#### **Fonctionnalités :**
- ✅ Interface intuitive avec icônes explicatives
- ✅ Validation des valeurs (0-20)
- ✅ Sauvegarde automatique
- ✅ Pré-remplissage avec les valeurs existantes
- ✅ Design cohérent avec l'application

#### **Exemple d'utilisation :**
```
🏫 6ème A - École stricte
   Félicitations: ≥ 18.0
   Encouragements: ≥ 16.0
   Admission: ≥ 14.0
   Avertissement: ≥ 12.0
   Sous conditions: ≥ 10.0
   Redoublement: < 10.0
```

### **3. Logique de Décision Adaptative**

#### **Avant (seuils fixes) :**
```dart
if (moyenne >= 16) {
  decision = 'Félicitations';
} else if (moyenne >= 14) {
  decision = 'Encouragements';
}
// ... seuils fixes pour toutes les classes
```

#### **Après (seuils personnalisés) :**
```dart
final seuils = await _dbService.getClassPassingThresholds(className, academicYear);
if (moyenne >= seuils['felicitations']!) {
  decision = 'Félicitations';
} else if (moyenne >= seuils['encouragements']!) {
  decision = 'Encouragements';
}
// ... seuils adaptés à chaque classe
```

## 🏫 Exemples de Configurations

### **École Stricte (Excellence)**
- **Félicitations** : ≥ 18.0
- **Encouragements** : ≥ 16.0
- **Admission** : ≥ 14.0
- **Avertissement** : ≥ 12.0
- **Sous conditions** : ≥ 10.0
- **Redoublement** : < 10.0

### **École Standard (Équilibre)**
- **Félicitations** : ≥ 16.0
- **Encouragements** : ≥ 14.0
- **Admission** : ≥ 12.0
- **Avertissement** : ≥ 10.0
- **Sous conditions** : ≥ 8.0
- **Redoublement** : < 8.0

### **École Permissive (Inclusion)**
- **Félicitations** : ≥ 14.0
- **Encouragements** : ≥ 12.0
- **Admission** : ≥ 10.0
- **Avertissement** : ≥ 8.0
- **Sous conditions** : ≥ 6.0
- **Redoublement** : < 6.0

### **Lycée d'Excellence**
- **Félicitations** : ≥ 17.0
- **Encouragements** : ≥ 15.0
- **Admission** : ≥ 13.0
- **Avertissement** : ≥ 11.0
- **Sous conditions** : ≥ 9.0
- **Redoublement** : < 9.0

## 📊 Comparaison des Résultats

### **Moyenne de test : 13.5**

| Établissement | Décision |
|---------------|----------|
| **École Stricte** | Admis avec avertissement |
| **École Standard** | Admis en classe supérieure |
| **École Permissive** | Admis avec encouragements |
| **Lycée d'Excellence** | Admis en classe supérieure |

## 🔄 Flux de Fonctionnement

### **1. Configuration Initiale**
```
1. Accéder aux détails de la classe
2. Modifier les seuils dans la section dédiée
3. Sauvegarder les modifications
4. Les seuils sont appliqués immédiatement
```

### **2. Génération des Bulletins**
```
1. Sélection de la classe et de la période
2. Récupération des seuils spécifiques à la classe
3. Calcul des décisions basé sur les seuils personnalisés
4. Génération du bulletin avec les décisions adaptées
```

### **3. Mise à Jour des Seuils**
```
1. Modification des seuils dans l'interface
2. Validation des nouvelles valeurs
3. Sauvegarde en base de données
4. Application immédiate aux nouveaux bulletins
```

## 🛠️ Structure Technique

### **Base de Données**
```sql
CREATE TABLE classes(
  name TEXT NOT NULL,
  academicYear TEXT NOT NULL,
  -- ... autres champs existants
  seuilFelicitations REAL DEFAULT 16.0,
  seuilEncouragements REAL DEFAULT 14.0,
  seuilAdmission REAL DEFAULT 12.0,
  seuilAvertissement REAL DEFAULT 10.0,
  seuilConditions REAL DEFAULT 8.0,
  seuilRedoublement REAL DEFAULT 8.0,
  PRIMARY KEY (name, academicYear)
)
```

### **Modèle de Données**
```dart
class Class {
  final String name;
  final String academicYear;
  // ... autres propriétés
  final double seuilFelicitations;
  final double seuilEncouragements;
  final double seuilAdmission;
  final double seuilAvertissement;
  final double seuilConditions;
  final double seuilRedoublement;
}
```

### **Service de Base de Données**
```dart
Future<Map<String, double>> getClassPassingThresholds(
  String className,
  String academicYear,
) async {
  // Récupération des seuils spécifiques à la classe
  // Retour des seuils par défaut si la classe n'existe pas
}
```

## 🎨 Interface Utilisateur

### **Section de Configuration**
```
┌─────────────────────────────────────────────────────────┐
│ 🏫 Seuils de passage en classe supérieure              │
├─────────────────────────────────────────────────────────┤
│ Configurez les moyennes minimales pour chaque type     │
│ de décision du conseil de classe :                     │
├─────────────────────────────────────────────────────────┤
│ ⭐ Félicitations (≥)    👍 Encouragements (≥)          │
│ [16.0]                  [14.0]                         │
├─────────────────────────────────────────────────────────┤
│ ✅ Admission (≥)        ⚠️ Avertissement (≥)           │
│ [12.0]                  [10.0]                         │
├─────────────────────────────────────────────────────────┤
│ ❓ Sous conditions (≥)  🔄 Redoublement (<)            │
│ [8.0]                   [8.0]                          │
└─────────────────────────────────────────────────────────┘
```

### **Éléments Visuels**
- 🏫 **Icône principale** : École
- ⭐ **Félicitations** : Étoile
- 👍 **Encouragements** : Pouce levé
- ✅ **Admission** : Coche verte
- ⚠️ **Avertissement** : Triangle d'avertissement
- ❓ **Sous conditions** : Point d'interrogation
- 🔄 **Redoublement** : Flèche de répétition

## 📈 Avantages du Système

### **1. Flexibilité Institutionnelle**
- Adaptation aux politiques éducatives de chaque établissement
- Respect des spécificités locales
- Évolution possible des critères

### **2. Cohérence Pédagogique**
- Alignement avec les objectifs pédagogiques
- Adaptation au niveau des élèves
- Motivation par des critères réalistes

### **3. Gestion Personnalisée**
- Configuration par classe
- Historique des modifications
- Traçabilité des décisions

### **4. Interface Intuitive**
- Configuration simple et rapide
- Validation automatique des données
- Sauvegarde transparente

## 🔧 Maintenance et Évolution

### **Modification des Seuils**
1. Accéder aux détails de la classe
2. Modifier les valeurs dans l'interface
3. Sauvegarder les changements
4. Les nouveaux bulletins utilisent les nouveaux seuils

### **Migration des Données**
- Les classes existantes conservent les seuils par défaut
- Possibilité de migration en lot
- Rétrocompatibilité assurée

### **Sauvegarde et Restauration**
- Sauvegarde automatique des configurations
- Possibilité de restauration des seuils par défaut
- Export/Import des configurations

## 🧪 Tests et Validation

### **Fichier de Test :** `test_seuils_personnalises.dart`

**Exécution :**
```bash
dart test_seuils_personnalises.dart
```

**Tests Inclus :**
- ✅ Configurations de différents types d'établissements
- ✅ Comparaison des décisions entre établissements
- ✅ Validation des seuils personnalisés
- ✅ Cas limites et valeurs extrêmes

## 🎯 Cas d'Usage Pratiques

### **Cas 1 : École Primaire Stricte**
- **Objectif** : Maintenir un niveau d'excellence élevé
- **Seuils** : Tous élevés (18, 16, 14, 12, 10, 10)
- **Résultat** : Décisions motivantes pour l'excellence

### **Cas 2 : Collège d'Insertion**
- **Objectif** : Favoriser la réussite de tous
- **Seuils** : Plus permissifs (14, 12, 10, 8, 6, 6)
- **Résultat** : Décisions encourageantes pour tous

### **Cas 3 : Lycée Technique**
- **Objectif** : Équilibre entre théorie et pratique
- **Seuils** : Intermédiaires (15, 13, 11, 9, 7, 7)
- **Résultat** : Décisions adaptées au profil technique

## 🚀 Évolutions Futures Possibles

### **1. Seuils par Matière**
- Configuration de seuils spécifiques par discipline
- Adaptation aux particularités de chaque matière

### **2. Seuils Temporels**
- Évolution des seuils selon les périodes
- Adaptation aux rythmes scolaires

### **3. Seuils par Profil d'Élève**
- Configuration selon les besoins éducatifs particuliers
- Personnalisation poussée

### **4. Analytics et Reporting**
- Statistiques sur l'évolution des seuils
- Analyse de l'impact des modifications

Ce système de seuils personnalisés offre une flexibilité maximale tout en conservant la simplicité d'utilisation, permettant à chaque établissement de s'adapter parfaitement à ses besoins spécifiques ! 🎉