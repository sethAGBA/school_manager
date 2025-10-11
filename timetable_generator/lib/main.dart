// main.dart
import 'package:flutter/material.dart';
import 'package:timetable_generator/models/models.dart';
import 'package:timetable_generator/services/timetable_generator.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Générateur d\'emploi du temps',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: TimetableHomePage(),
    );
  }
}

class TimetableHomePage extends StatefulWidget {
  @override
  State<TimetableHomePage> createState() => _TimetableHomePageState();
}

class _TimetableHomePageState extends State<TimetableHomePage> {
  EmploiDuTemps? emploiDuTemps;
  bool isLoading = false;

  // Données de test
  final List<Classe> classes = [
    Classe(id: 'c1', nom: '6ème A', niveau: '6ème', section: 'A', nombreEleves: 30),
    Classe(id: 'c2', nom: '6ème B', niveau: '6ème', section: 'B', nombreEleves: 28),
  ];

  final List<Professeur> professeurs = [
    Professeur(
      id: 'p1',
      nom: 'Dupont',
      prenom: 'Jean',
      matieresIds: ['m1', 'm2'],
      maxHeuresParJour: 6,
    ),
    Professeur(
      id: 'p2',
      nom: 'Martin',
      prenom: 'Marie',
      matieresIds: ['m3'],
      maxHeuresParJour: 5,
    ),
    Professeur(
      id: 'p3',
      nom: 'Bernard',
      prenom: 'Paul',
      matieresIds: ['m4'],
      maxHeuresParJour: 6,
    ),
  ];

  final List<Matiere> matieres = [
    Matiere(
      id: 'm1',
      nom: 'Mathématiques',
      volumeHoraireHebdo: 4,
      dureeSceance: 60,
      niveauDifficulte: 5,
      type: TypeMatiere.theorique,
    ),
    Matiere(
      id: 'm2',
      nom: 'Français',
      volumeHoraireHebdo: 4,
      dureeSceance: 60,
      niveauDifficulte: 4,
      type: TypeMatiere.theorique,
    ),
    Matiere(
      id: 'm3',
      nom: 'Anglais',
      volumeHoraireHebdo: 3,
      dureeSceance: 60,
      niveauDifficulte: 3,
      type: TypeMatiere.theorique,
    ),
    Matiere(
      id: 'm4',
      nom: 'EPS',
      volumeHoraireHebdo: 2,
      dureeSceance: 120,
      type: TypeMatiere.sport,
      necessiteSalleSpeciale: true,
    ),
  ];

  final List<Salle> salles = [
    Salle(id: 's1', nom: 'Salle 101', capacite: 35, type: TypeSalle.standard),
    Salle(id: 's2', nom: 'Salle 102', capacite: 35, type: TypeSalle.standard),
    Salle(id: 's3', nom: 'Salle 103', capacite: 35, type: TypeSalle.standard),
    Salle(id: 's4', nom: 'Gymnase', capacite: 50, type: TypeSalle.sport),
  ];

  Future<void> genererEmploiDuTemps() async {
    setState(() {
      isLoading = true;
    });

    try {
      final generator = TimetableGenerator(
        classes: classes,
        professeurs: professeurs,
        matieres: matieres,
        salles: salles,
        config: ConfigurationHoraire(),
      );

      final result = await generator.generer();

      setState(() {
        emploiDuTemps = result;
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Emploi du temps généré ! Score: ${result.score.toStringAsFixed(2)}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Générateur d\'emploi du temps'),
        elevation: 2,
      ),
      body: Column(
        children: [
          // Statistiques
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard('Classes', classes.length.toString(), Icons.school),
                _buildStatCard('Professeurs', professeurs.length.toString(), Icons.person),
                _buildStatCard('Matières', matieres.length.toString(), Icons.book),
                _buildStatCard('Salles', salles.length.toString(), Icons.meeting_room),
              ],
            ),
          ),

          // Bouton de génération
          Padding(
            padding: EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : genererEmploiDuTemps,
              icon: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.auto_awesome),
              label: Text(
                isLoading ? 'Génération en cours...' : 'Générer l\'emploi du temps',
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),

          // Affichage de l'emploi du temps
          if (emploiDuTemps != null)
            Expanded(
              child: TimetableView(
                emploiDuTemps: emploiDuTemps!,
                classes: classes,
                matieres: matieres,
                professeurs: professeurs,
                salles: salles,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: Colors.blue, size: 28),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// Widget d'affichage de l'emploi du temps
class TimetableView extends StatelessWidget {
  final EmploiDuTemps emploiDuTemps;
  final List<Classe> classes;
  final List<Matiere> matieres;
  final List<Professeur> professeurs;
  final List<Salle> salles;

  const TimetableView({
    required this.emploiDuTemps,
    required this.classes,
    required this.matieres,
    required this.professeurs,
    required this.salles,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: classes.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: classes.map((c) => Tab(text: c.nom)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: classes.map((classe) {
                return ClasseTimetableGrid(
                  classe: classe,
                  cours: emploiDuTemps.getCoursParClasse(classe.id),
                  matieres: matieres,
                  professeurs: professeurs,
                  salles: salles,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// Grille d'emploi du temps pour une classe
class ClasseTimetableGrid extends StatelessWidget {
  final Classe classe;
  final List<Cours> cours;
  final List<Matiere> matieres;
  final List<Professeur> professeurs;
  final List<Salle> salles;

  const ClasseTimetableGrid({
    required this.classe,
    required this.cours,
    required this.matieres,
    required this.professeurs,
    required this.salles,
  });

  @override
  Widget build(BuildContext context) {
    final jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi'];
    final heures = ['8h-9h', '9h-10h', '10h-11h', '11h-12h', '14h-15h', '15h-16h', '16h-17h'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.blue.shade100),
          border: TableBorder.all(color: Colors.grey.shade300),
          columns: [
            DataColumn(label: Text('Heures', style: TextStyle(fontWeight: FontWeight.bold))),
            ...jours.map((jour) => DataColumn(
              label: Text(jour, style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ],
          rows: List.generate(heures.length, (index) {
            return DataRow(
              cells: [
                DataCell(Text(heures[index], style: TextStyle(fontWeight: FontWeight.w500))),
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
                    return DataCell(Container());
                  }

                  final matiere = matieres.firstWhere((m) => m.id == coursAuCreneau.matiereId);
                  final prof = professeurs.firstWhere((p) => p.id == coursAuCreneau.professeurId);
                  final salle = salles.firstWhere(
                    (s) => s.id == coursAuCreneau.salleId,
                    orElse: () => Salle(id: '', nom: 'N/A', capacite: 0),
                  );

                  return DataCell(
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getColorForMatiere(matiere.type),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            matiere.nom,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${prof.prenom} ${prof.nom}',
                            style: TextStyle(fontSize: 10),
                          ),
                          Text(
                            salle.nom,
                            style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
        ),
      ),
    );
  }

  Color _getColorForMatiere(TypeMatiere type) {
    switch (type) {
      case TypeMatiere.theorique:
        return Colors.blue.shade100;
      case TypeMatiere.pratique:
        return Colors.green.shade100;
      case TypeMatiere.sport:
        return Colors.orange.shade100;
      case TypeMatiere.artistique:
        return Colors.purple.shade100;
    }
  }
}