import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'depot_form_screen.dart';
import 'depot_receipt_screen.dart';
import 'depot_sale_screen.dart';
import 'depot_stock_adjustment_screen.dart';

class DepotDetailScreen extends StatelessWidget {
  final String depotId;
  final String depotName;

  const DepotDetailScreen({
    super.key,
    required this.depotId,
    required this.depotName,
  });

  static const String farmId = 'farm_nkoteng';

  Map<String, dynamic> _getMap(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  int _getInt(Map<String, dynamic> m, String key, [int def = 0]) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return def;
  }

  int _sumGrade(Map<String, dynamic> byGrade) {
    int t = 0;
    for (final k in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      t += _getInt(byGrade, k, 0);
    }
    return t;
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

  // Cartons / Alvéoles / Isolés helper for display
  String _cti(int eggs) {
    if (eggs < 0) eggs = 0;
    final trays = eggs ~/ 30;
    final cartons = trays ~/ 12;
    final traysR = trays % 12;
    final iso = eggs % 30;
    return "$cartons c • $traysR a • $iso i";
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    final depotRef = db.collection('farms').doc(farmId).collection('depots').doc(depotId);
    final stockRef = db.collection('farms').doc(farmId).collection('stocks_eggs').doc("DEPOT_$depotId");

    return Scaffold(
      appBar: AppBar(
        title: Text(depotName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: "Modifier",
            onPressed: () async {
              final res = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => DepotFormScreen(depotId: depotId)),
              );
              if (res == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Dépôt mis à jour ✅")),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: depotRef.snapshots(),
          builder: (context, depotSnap) {
            if (depotSnap.hasError) return Center(child: Text("Erreur: ${depotSnap.error}"));
            if (!depotSnap.hasData) return const Center(child: CircularProgressIndicator());
            if (!depotSnap.data!.exists) return const Center(child: Text("Dépôt introuvable"));

            final depot = depotSnap.data!.data() ?? {};
            final location = (depot['location'] ?? '').toString();
            final active = (depot['active'] ?? true) == true;

            return ListView(
              children: [
                Text(
                  "Informations dépôt",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info),
                  title: const Text("Identifiant"),
                  subtitle: Text(depotId),
                ),
                if (location.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place),
                    title: const Text("Localisation"),
                    subtitle: Text(location),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(active ? Icons.check_circle : Icons.pause_circle),
                  title: const Text("Statut"),
                  subtitle: Text(active ? "Actif" : "Inactif"),
                ),

                const Divider(height: 24),

                Text(
                  "Actions",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),

                // ✅ Réception dépôt
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.download_done),
                    title: const Text("Réception dépôt"),
                    subtitle: const Text("Pré-rempli depuis les transferts en attente"),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DepotReceiptScreen(
                            farmId: farmId,
                            depotId: depotId,
                            depotName: depotName,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ✅ Vente dépôt
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.point_of_sale),
                    title: const Text("Vente dépôt"),
                    subtitle: const Text("Sortie vers client (cartons / alvéoles / isolés)"),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DepotSaleScreen(
                            farmId: farmId,
                            depotId: depotId,
                            depotName: depotName,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ✅ Ajustement dépôt
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text("Ajustement dépôt"),
                    subtitle: const Text("Correction manuelle (erreurs, écarts)"),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DepotStockAdjustmentScreen(
                            farmId: farmId,
                            depotId: depotId,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const Divider(height: 24),

                Text(
                  "Stock dépôt (bons œufs)",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),

                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: stockRef.snapshots(),
                  builder: (context, stockSnap) {
                    if (stockSnap.hasError) {
                      return Text("Erreur stock: ${stockSnap.error}", style: const TextStyle(color: Colors.red));
                    }
                    if (!stockSnap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      );
                    }

                    final stock = stockSnap.data!.data() ?? {};
                    final byGrade = _getMap(stock, 'eggsByGrade');
                    final goodTotal =
                    (stock['goodTotalEggs'] is int) ? stock['goodTotalEggs'] as int : _sumGrade(byGrade);
                    final brokenTotal = (stock['brokenTotalEggs'] is int) ? stock['brokenTotalEggs'] as int : 0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Total : $goodTotal œufs (${_cti(goodTotal)})",
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL'])
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.egg_alt_outlined),
                            title: Text(_gradeFr(g)),
                            subtitle: Text(_cti(_getInt(byGrade, g, 0))),
                            trailing: Text("${_getInt(byGrade, g, 0)}"),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          "Casses : $brokenTotal œufs (${_cti(brokenTotal)})",
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
