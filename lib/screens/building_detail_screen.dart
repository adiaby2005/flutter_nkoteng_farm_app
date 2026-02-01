import 'package:flutter/material.dart';

import '../models/building.dart';
import 'daily_entry_screen.dart';
import 'daily_entries_history_screen.dart';
import 'egg_transfer_to_depot_screen.dart';

class BuildingDetailScreen extends StatelessWidget {
  final Building building;

  const BuildingDetailScreen({super.key, required this.building});

  static const String _farmId = 'farm_nkoteng';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(building.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              building.name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.people),
                const SizedBox(width: 8),
                Text('Capacité : ${building.capacity} poules'),
              ],
            ),
            const Divider(height: 32),
            const Text(
              'Actions',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Saisie
            ListTile(
              leading: const Icon(Icons.add_chart),
              title: const Text('Saisie journalière'),
              subtitle: const Text('Ponte, mortalité, aliments, eau, véto'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyEntryScreen(building: building),
                  ),
                );
              },
            ),

            // Historique
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Historique journalier'),
              subtitle: const Text('Voir / corriger les saisies par date'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyEntriesHistoryScreen(
                      building: building,
                      farmId: _farmId,
                    ),
                  ),
                );
              },
            ),

            // ✅ Transfert vers dépôt
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text('Transfert vers dépôt'),
              subtitle: const Text('Déplacer les bons œufs vers un dépôt'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EggTransferToDepotScreen(
                      farmId: _farmId,
                      building: building,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
