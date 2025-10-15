# Guide d'utilisation du système de signatures et cachets

## Vue d'ensemble

Le système de signatures et cachets permet d'associer des signatures numériques et des cachets aux classes et aux rôles administratifs pour automatiser leur inclusion dans les bulletins et reçus de paiement.

## Fonctionnalités principales

### 1. Gestion des signatures et cachets
- **Création** : Ajouter de nouvelles signatures et cachets avec images
- **Association** : Lier les signatures aux classes et rôles spécifiques
- **Gestion** : Modifier, supprimer et organiser les signatures

### 2. Assignation par classe
- **Titulaires** : Signature du titulaire de chaque classe
- **Directeurs** : Signature du directeur pour toutes les classes
- **Cachets** : Cachet officiel de l'établissement

### 3. Intégration automatique
- **Bulletins** : Signatures automatiquement incluses dans les bulletins
- **Reçus** : Signatures et cachets sur les reçus de paiement

## Utilisation

### Étape 1 : Créer des signatures et cachets

1. Accédez à l'écran "Signatures et Cachets"
2. Onglets disponibles:
   - Signatures: signatures liées aux classes/rôles (ex: Titulaire)
   - Cachets: cachets de l'établissement
   - Administration: signatures de l'administration (Directeur, Proviseur, Vice‑Directeur)
3. Cliquez sur "Ajouter" dans l'onglet concerné
3. Remplissez les informations :
   - **Nom** : Nom de la personne ou du cachet
   - **Description** : Description optionnelle
   - **Image** : Sélectionnez une image de signature/cachet
   - **Classe associée** : (Optionnel) Classe spécifique
   - **Rôle associé** : Titulaire, Directeur, etc.
   - **Membre du personnel** : (Optionnel) Lier à un membre du personnel
   - **Par défaut** : Définir comme signature par défaut

### Étape 2 : Assigner les signatures aux classes

1. Cliquez sur le bouton "Assigner" dans l'écran des signatures
2. Sélectionnez une classe
3. Choisissez le rôle (Titulaire, Directeur, etc.)
4. Sélectionnez la signature à assigner
5. Optionnellement, liez à un membre du personnel
6. Définissez comme signature par défaut si nécessaire
7. Pour un usage global (toutes classes), choisissez « Aucune classe (global) »

### Astuces pour l'apparition dans les documents

- Reçus de paiement: onglet Administration → ajoutez une signature « Directeur » par défaut (global). Onglet Cachets → ajoutez un cachet « Directeur » par défaut (global).
- Bulletins: 
  - Titulaire: onglet Signatures → assignez une signature « Titulaire » par défaut pour chaque classe.
  - Directeur/Proviseur: onglet Administration → ajoutez la signature « Directeur » (collèges/primaires) ou « Proviseur » (lycées) par défaut (global). L'app choisit automatiquement selon le niveau.
  - Cachet: onglet Cachets → ajoutez un cachet « Directeur » par défaut (global).

Si aucune image n'est disponible pour une signature ou un cachet, le PDF affichera un indicateur "non disponible" et, pour le bulletin, les lignes de signature restent visibles.

### Étape 3 : Vérifier les assignations

L'écran d'assignation montre pour chaque classe :
- ✅ **Signature Titulaire** : Assignée/Non assignée
- ✅ **Signature Directeur** : Assignée/Non assignée  
- ✅ **Cachet** : Assigné/Non assigné

## Rôles supportés

### Rôles par classe
- **Titulaire** : Signature du professeur titulaire de la classe
- **Directeur** : Signature du directeur pour cette classe spécifique

### Rôles globaux
- **Directeur** : Signature du directeur pour tous les documents
- **Vice-Directeur** : Signature du vice-directeur (substitution)

## Intégration dans les documents

### Bulletins scolaires
Les signatures sont automatiquement intégrées dans les bulletins :
- Signature du titulaire (côté droit)
- Signature du directeur (côté gauche)
- Cachet de l'établissement (côté directeur)

### Reçus de paiement
Les reçus incluent :
- Signature du directeur
- Cachet officiel de l'établissement

## Gestion des images

### Formats supportés
- **Images** : JPG, PNG, GIF
- **Taille recommandée** : 200x100 pixels pour les signatures
- **Qualité** : Images nettes et contrastées

### Optimisation
- Les images sont automatiquement redimensionnées
- Compression pour optimiser la taille des PDFs
- Support des images haute résolution

## Bonnes pratiques

### Organisation
1. **Nommage cohérent** : Utilisez des noms clairs (ex: "Signature M. Dupont")
2. **Descriptions** : Ajoutez des descriptions pour faciliter l'identification
3. **Hiérarchie** : Définissez des signatures par défaut pour chaque rôle

### Sécurité
1. **Images de qualité** : Utilisez des signatures nettes et lisibles
2. **Sauvegarde** : Les images sont stockées localement
3. **Accès** : Seuls les utilisateurs autorisés peuvent modifier les signatures

### Maintenance
1. **Mises à jour** : Mettez à jour les signatures lors des changements de personnel
2. **Vérification** : Vérifiez régulièrement les assignations
3. **Archivage** : Conservez les anciennes signatures pour l'historique

## Dépannage

### Problèmes courants

**Signature non affichée dans le PDF**
- Vérifiez que l'image est correctement chargée
- Vérifiez l'assignation à la classe/rôle
- Vérifiez que la signature est définie comme par défaut

**Image de mauvaise qualité**
- Utilisez des images haute résolution
- Vérifiez le format (JPG/PNG recommandés)
- Évitez les images floues ou pixellisées

**Assignation incorrecte**
- Vérifiez la classe sélectionnée
- Vérifiez le rôle assigné
- Vérifiez que la signature est active

### Support technique

En cas de problème :
1. Vérifiez les logs d'erreur
2. Redémarrez l'application
3. Vérifiez la base de données
4. Contactez le support technique

## Évolutions futures

### Fonctionnalités prévues
- **Signatures électroniques** : Intégration de signatures numériques
- **Templates** : Modèles de signatures prédéfinis
- **Historique** : Suivi des modifications des signatures
- **Export/Import** : Sauvegarde et restauration des signatures
- **API** : Intégration avec des systèmes externes

### Améliorations
- **Interface** : Amélioration de l'interface utilisateur
- **Performance** : Optimisation du chargement des images
- **Sécurité** : Chiffrement des signatures sensibles
- **Mobilité** : Support des signatures sur mobile
