import 'package:flutter/material.dart';

import '../models/building.dart';
import '../services/building_service.dart';

import 'building_detail_screen.dart';
import 'daily_entries_history_screen.dart';
import 'daily_entry_screen.dart';

// ✅ Lots / sujets
import 'subject_entry_screen.dart';
import 'subjects_overview_screen.dart';
import 'active_lot_edit_screen.dart';

class BuildingsScreen extends StatelessWidget {
  const BuildingsScreen({super.key});

  static const String _farmId = 'farm_nkoteng';

  void _openBuildingDetail(BuildContext context, Building b) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BuildingDetailScreen(building: b)),
    );
  }

  void _openDailyEntry(BuildContext context, Building b) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DailyEntryScreen(building: b)),
    );
  }

  void _openHistory(BuildContext context, Building b) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DailyEntriesHistoryScreen(building: b, farmId: _farmId),
      ),
    );
  }

  void _openSubjectEntry(BuildContext context, Building b) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubjectEntryScreen(buildingId: b.id, buildingName: b.name),
      ),
    );
  }

  void _openActiveLotEdit(BuildContext context, Building b) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveLotEditScreen(buildingId: b.id, buildingName: b.name),
      ),
    );
  }

  void _openSubjectsOverview(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubjectsOverviewScreen()),
    );
  }

  Future<void> _showBuildingActions(BuildContext context, Building b) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.home_work),
                    title: Text(b.name),
                    subtitle: Text('Capacité : ${b.capacity}'),
                  ),
                  const Divider(height: 0),

                  // =========================
                  // JOURNALIER
                  // =========================
                  ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text("Saisie journalière"),
                    subtitle: const Text("Enregistrer ponte, casses, eau, alim, véto…"),
                    onTap: () {
                      Navigator.pop(context);
                      _openDailyEntry(context, b);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text("Historique journalier"),
                    subtitle: const Text("Voir les saisies par date"),
                    onTap: () {
                      Navigator.pop(context);
                      _openHistory(context, b);
                    },
                  ),

                  const Divider(height: 0),

                  // =========================
                  // LOTS / SUJETS
                  // =========================
                  ListTile(
                    leading: const Icon(Icons.playlist_add),
                    title: const Text("Entrée lot (activation)"),
                    subtitle: const Text("Créer le lot actif du bâtiment (strict : 1 lot actif)"),
                    onTap: () {
                      Navigator.pop(context);
                      _openSubjectEntry(context, b);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text("Modifier lot actif"),
                    subtitle: const Text("Modifier souche / âge / date de démarrage"),
                    onTap: () {
                      Navigator.pop(context);
                      _openActiveLotEdit(context, b);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.groups),
                    title: const Text("Sujets / lots (vue ferme)"),
                    subtitle: const Text("Totaux ferme + détails par bâtiment"),
                    onTap: () {
                      Navigator.pop(context);
                      _openSubjectsOverview(context);
                    },
                  ),

                  const Divider(height: 0),

                  // =========================
                  // DETAILS
                  // =========================
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text("Détails du bâtiment"),
                    subtitle: const Text("Infos / lots / configuration"),
                    onTap: () {
                      Navigator.pop(context);
                      _openBuildingDetail(context, b);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bâtiments')),
      body: StreamBuilder<List<Building>>(
        stream: BuildingService.streamBuildings(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erreur: ${snap.error}'));
          }

          final buildings = snap.data ?? [];
          if (buildings.isEmpty) {
            return const Center(child: Text('Aucun bâtiment'));
          }

          return ListView.separated(
            itemCount: buildings.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final b = buildings[i];

              return ListTile(
                leading: const Icon(Icons.home_work),
                title: Text(b.name),
                subtitle: Text('Capacité : ${b.capacity}'),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: "Actions",
                  onPressed: () => _showBuildingActions(context, b),
                ),
                onTap: () => _showBuildingActions(context, b),
                onLongPress: () => _showBuildingActions(context, b),
              );
            },
          );
        },
      ),
    );
  }
}
