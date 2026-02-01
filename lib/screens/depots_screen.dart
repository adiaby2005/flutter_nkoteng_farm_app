import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'depot_receipt_screen.dart';
import 'depot_stock_adjustment_screen.dart';
import 'egg_transfers_history_screen.dart';
import 'depot_sale_screen.dart';
import 'depot_sales_history_screen.dart';
import 'depot_recoveries_screen.dart';

class DepotsScreen extends StatelessWidget {
  final String farmId;

  const DepotsScreen({
    super.key,
    required this.farmId,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    final depotsQuery = db
        .collection('farms')
        .doc(farmId)
        .collection('depots')
        .where('active', isEqualTo: true)
        .orderBy('name');

    return Scaffold(
      appBar: AppBar(title: const Text("Dépôts")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: depotsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text("Erreur: ${snap.error}", style: const TextStyle(color: Colors.red)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("Aucun dépôt"));

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              final name = (data['name'] ?? d.id).toString().trim();
              final location = (data['location'] ?? '').toString().trim();

              return ListTile(
                leading: const Icon(Icons.store),
                title: Text(name),
                subtitle: location.isEmpty ? null : Text(location),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DepotDetailScreen(
                        farmId: farmId,
                        depotId: d.id,
                        depotName: name,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class DepotDetailScreen extends StatelessWidget {
  final String farmId;
  final String depotId;
  final String depotName;

  const DepotDetailScreen({
    super.key,
    required this.farmId,
    required this.depotId,
    required this.depotName,
  });

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  Map<String, int> _readGrades(Map<String, dynamic> doc, String key) {
    final raw = doc[key];
    final m = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return {
      'SMALL': _asInt(m['SMALL']),
      'MEDIUM': _asInt(m['MEDIUM']),
      'LARGE': _asInt(m['LARGE']),
      'XL': _asInt(m['XL']),
    };
  }

  Map<String, int> _pickGoodByGrade(Map<String, dynamic> data) {
    final good = _readGrades(data, 'goodByGrade');
    final eggs = _readGrades(data, 'eggsByGrade');

    int pick(String g) {
      final v = good[g] ?? 0;
      if (v != 0) return v;
      return eggs[g] ?? 0;
    }

    return {'SMALL': pick('SMALL'), 'MEDIUM': pick('MEDIUM'), 'LARGE': pick('LARGE'), 'XL': pick('XL')};
  }

  String _gradeFr(String g) {
    switch (g) {
      case 'SMALL':
        return 'Petit';
      case 'MEDIUM':
        return 'Moyen';
      case 'LARGE':
        return 'Gros';
      case 'XL':
        return 'Très gros';
      default:
        return g;
    }
  }

  String _fmtCTI(int eggs) {
    final trays = eggs ~/ 30;
    final cartons = trays ~/ 12;
    final traysR = trays % 12;
    final iso = eggs % 30;
    return "$cartons carton(s) • $traysR alvéole(s) • $iso isolé(s)";
  }

  Widget _stockRow(BuildContext context, String grade, int eggs) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.egg_alt_outlined),
        title: Text(_gradeFr(grade)),
        subtitle: Text(_fmtCTI(eggs)),
        trailing: Text("$eggs", style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final stockRef = db.collection('farms').doc(farmId).collection('stocks_eggs').doc("DEPOT_$depotId");

    return Scaffold(
      appBar: AppBar(title: Text(depotName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text("Stock du dépôt", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: stockRef.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text("Erreur stock: ${snap.error}", style: const TextStyle(color: Colors.red));
                }
                if (!snap.hasData) return const LinearProgressIndicator();

                final data = snap.data!.data() ?? <String, dynamic>{};
                final good = _pickGoodByGrade(data);
                final goodTotal = _asInt(data['goodTotalEggs']);
                final brokenTotal = _asInt(data['brokenTotalEggs']);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text("Total bons œufs"),
                        subtitle: Text(_fmtCTI(goodTotal)),
                        trailing: Text("$goodTotal", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.broken_image_outlined),
                        title: const Text("Casses (total)"),
                        subtitle: Text(_fmtCTI(brokenTotal)),
                        trailing: Text(
                          "$brokenTotal",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _stockRow(context, 'SMALL', good['SMALL'] ?? 0),
                    _stockRow(context, 'MEDIUM', good['MEDIUM'] ?? 0),
                    _stockRow(context, 'LARGE', good['LARGE'] ?? 0),
                    _stockRow(context, 'XL', good['XL'] ?? 0),
                  ],
                );
              },
            ),

            const Divider(height: 32),

            Text("Actions", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text("Réception dépôt"),
              subtitle: const Text("Valider / ajuster les quantités reçues"),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DepotReceiptScreen(farmId: farmId, depotId: depotId, depotName: depotName),
                ),
              ),
            ),
            const Divider(height: 0),

            ListTile(
              leading: const Icon(Icons.point_of_sale),
              title: const Text("Vente dépôt"),
              subtitle: const Text("Vente par carton + prix + total"),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DepotSaleScreen(farmId: farmId, depotId: depotId, depotName: depotName),
                ),
              ),
            ),
            const Divider(height: 0),

            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text("Historique ventes"),
              subtitle: const Text("Badge Payé / Non payé"),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DepotSalesHistoryScreen(farmId: farmId, depotId: depotId, depotName: depotName),
                ),
              ),
            ),
            const Divider(height: 0),

            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text("Recouvrements"),
              subtitle: const Text("Lister les impayés + marquer Payé"),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DepotRecoveriesScreen(farmId: farmId, depotId: depotId, depotName: depotName),
                ),
              ),
            ),
            const Divider(height: 0),

            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text("Ajustements dépôt"),
              subtitle: const Text("Recalibrage & déclaration de casses"),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DepotStockAdjustmentScreen(farmId: farmId, depotId: depotId)),
              ),
            ),
            const Divider(height: 0),

            ListTile(
              leading: const Icon(Icons.history),
              title: const Text("Historique transferts"),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EggTransfersHistoryScreen(farmId: farmId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
