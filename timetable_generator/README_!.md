# 📚 Générateur d'Emploi du Temps Scolaire - Flutter

Application Flutter complète pour la génération automatique d'emplois du temps scolaires avec algorithme d'optimisation intelligent.

## 🎯 Fonctionnalités

### ✅ Gestion des données
- Gestion des **classes** (niveau, section, nombre d'élèves)
- Gestion des **professeurs** (disponibilités, matières enseignées)
- Gestion des **matières** (volume horaire, durée des séances)
- Gestion des **salles** (capacité, type, équipements)

### 🤖 Génération intelligente
- **Algorithme d'optimisation** avec contraintes dures et souples
- Respect des disponibilités des professeurs
- Optimisation de la charge de travail
- Placement intelligent des matières difficiles le matin
- Évitement des trous dans l'emploi du temps
- Équilibrage de la charge journalière

### 📊 Visualisation
- Affichage par classe sous forme de grille
- Affichage par professeur
- Code couleur selon le type de matière
- Vue hebdomadaire complète

### 📄 Export et partage
- Export PDF par classe
- Export PDF par professeur
- Partage via email ou applications
- Sauvegarde locale de tous les emplois du temps

## 🚀 Installation

### Prérequis
- Flutter SDK ≥ 3.0.0
- Dart SDK ≥ 3.0.0
- Android Studio / VS Code avec extensions Flutter

### Étapes d'installation

1. **Cloner le projet**
```bash
git clone https://github.com/votre-repo/timetable_generator.git
cd timetable_generator
```

2. **Installer les dépendances**
```bash
flutter pub get
```

3. **Générer les adaptateurs Hive**
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

4. **Lancer l'application**
```bash
flutter run
```

## 📁 Structure du projet

```
lib/
├── models/                    # Modèles de données
│   ├── classe.dart
│   ├── professeur.dart
│   ├── matiere.dart
│   ├── salle.dart
│   ├── creneau.dart
│   ├── cours.dart
│   └── emploi_du_temps.dart
│
├── services/                  # Services métier
│   ├── timetable_generator.dart   # Algorithme principal
│   ├── database_service.dart      # Gestion BDD
│   └── pdf_export_service.dart    # Export PDF
│
├── providers/                 # Gestion d'état
│   └── timetable_provider.dart
│
├── screens/                   # Écrans de l'application
│   ├── home_page.dart
│   ├── classes_page.dart
│   ├── professeurs_page.dart
│   ├── matieres_page.dart
│   ├── salles_page.dart
│   └── timetable_view_page.dart
│
└── main.dart                  # Point d'entrée
```

## 🔧 Configuration

### Créer les adaptateurs Hive

Ajoutez les annotations dans vos modèles :

```dart
import 'package:hive/hive.dart';

part 'classe.g.dart';

@HiveType(typeId: 0)
class Classe extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String nom;
  
  // ... autres champs
}
```

Puis générez :
```bash
flutter pub run build_runner build
```

### Configuration des horaires

Modifiez `ConfigurationHoraire` dans `timetable_generator.dart` :

```dart
ConfigurationHoraire(
  joursParSemaine: 5,        // Lundi à Vendredi
  heureDebut: 480,            // 8h00 (en minutes)
  heureFin: 1020,             // 17h00 (en minutes)
  dureeCreneauStandard: 60,   // 60 minutes
)
```

## 💡 Utilisation

### 1. Initialiser les données

```dart
// Charger des données d'exemple
await provider.chargerDonneesExemple();
```

### 2. Ajouter des entités

```dart
// Ajouter une classe
await provider.ajouterClasse(Classe(
  id: 'c1',
  nom: '6ème A',
  niveau: '6ème',
  section: 'A',
  nombreEleves: 30,
));

// Ajouter un professeur
await provider.ajouterProfesseur(Professeur(
  id: 'p1',
  nom: 'Dupont',
  prenom: 'Jean',
  matieresIds: ['m1'],
  maxHeuresParJour: 6,
));
```

### 3. Générer l'emploi du temps

```dart
bool success = await provider.genererEmploiDuTemps();

if (success) {
  print('Emploi du temps généré avec succès !');
  print('Score: ${provider.emploiDuTempsCourant?.score}');
}
```

### 4. Exporter en PDF

```dart
File pdf = await PdfExportService.exporterEmploiDuTemps(
  emploiDuTemps: provider.emploiDuTempsCourant!,
  classes: provider.classes,
  matieres: provider.matieres,
  professeurs: provider.professeurs,
  salles: provider.salles,
  classeId: 'c1', // Pour une classe spécifique
);

await PdfExportService.partagerPdf(pdf);
```

## 🧮 Algorithme de génération

### Contraintes dures (obligatoires)
- ✅ Un professeur ne peut être à deux endroits simultanément
- ✅ Une salle ne peut accueillir qu'une classe à la fois
- ✅ Une classe ne peut avoir qu'un cours à la fois
- ✅ Respect du volume horaire de chaque matière
- ✅ Respect des disponibilités des professeurs

### Contraintes souples (optimisation)
- 📈 Éviter les trous dans l'emploi du temps (-20 points)
- 🌅 Placer les matières difficiles le matin (+10 points)
- 🔄 Alterner théorie et pratique (+8 points)
- 🚗 Limiter les déplacements des professeurs (+5 points)
- ⚖️ Équilibrer la charge journalière (variance minimale)

### Fonction de score

```
Score final = (Cours placés / Cours total) × 1000
            + Bonus optimisations
            - Pénalités violations
```

## 📱 Captures d'écran

*(Ajoutez vos captures d'écran ici)*

## 🔮 Améliorations futures

- [ ] Drag & drop pour modification manuelle
- [ ] Import/Export Excel
- [ ] Gestion des absences
- [ ] Notifications push
- [ ] Mode multi-établissement
- [ ] Algorithme génétique avancé
- [ ] Support des demi-groupes
- [ ] Gestion des salles partagées
- [ ] Statistiques avancées
- [ ] Mode dark/light

## 🐛 Résolution de problèmes

### Problème : "Impossible de placer tous les cours"

**Solutions :**
1. Augmenter le nombre de salles
2. Vérifier les disponibilités des professeurs
3. Réduire le volume horaire de certaines matières
4. Augmenter la plage horaire (heureDebut/heureFin)

### Problème : "Score faible"

**Solutions :**
1. Ajuster les poids dans la fonction d'évaluation
2. Assouplir certaines contraintes souples
3. Ajouter plus de créneaux disponibles

## 📄 Licence

MIT License - Libre d'utilisation et de modification

## 👨‍💻 Auteur

Développé pour les établissements scolaires souhaitant automatiser leur gestion d'emploi du temps.

## 🤝 Contribution

Les contributions sont les bienvenues ! N'hésitez pas à :
1. Fork le projet
2. Créer une branche (`git checkout -b feature/AmazingFeature`)
3. Commit vos changements (`git commit -m 'Add AmazingFeature'`)
4. Push vers la branche (`git push origin feature/AmazingFeature`)
5. Ouvrir une Pull Request

## 📞 Support

Pour toute question ou problème :
- Ouvrez une issue sur GitHub
- Contactez-nous par email

---

**⭐ N'oubliez pas de star le repo si ce projet vous a aidé !**