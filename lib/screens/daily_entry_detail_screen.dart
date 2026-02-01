import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/building.dart';
import 'daily_entry_edit_screen.dart';

class DailyEntryDetailScreen extends StatelessWidget {
  final String farmId;
  final Building building;
  final String dailyEntryDocId;
  final String dateIso;

  const DailyEntryDetailScreen({
    super.key,
    required this.farmId,
    required this.building,
    required this.dailyEntryDocId,
    required this.dateIso,
  });

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

  String _getStr(Map<String, dynamic> m, String key, [String def = ""]) {
    final v = m[key];
    if (v == null) return def;
    return v.toString();
  }

  String _gradeFr(String grade) {
    switch (grade) {
      case 'SMALL':
        return 'Petit calibre';
      case 'MEDIUM':
        return 'Moyen calibre';
      case 'LARGE':
        return 'Gros calibre';
      case 'XL':
        return 'Très gros calibre';
      default:
        return grade;
    }
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        t,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  /// ✅ itemId -> name (items/{itemId}.name)
  Widget _itemName(String itemId) {
    final ref = FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('items')
        .doc(itemId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return Text(itemId);
        if (!snap.data!.exists) return Text(itemId);
        final data = snap.data!.data() ?? <String, dynamic>{};
        final name = (data['name'] ?? '').toString().trim();
        return Text(name.isEmpty ? itemId : name);
      },
    );
  }

  /// ✅ lotId -> label (lots/{lotId}.name ou code)
  Widget _lotLabel(String lotId) {
    final ref = FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('lots')
        .doc(lotId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return Text(lotId);
        if (!snap.data!.exists) return Text(lotId);

        final data = snap.data!.data() ?? <String, dynamic>{};
        final name = (data['name'] ?? '').toString().trim();
        final code = (data['code'] ?? '').toString().trim();
        final label = name.isNotEmpty ? name : (code.isNotEmpty ? code : lotId);
        return Text(label);
      },
    );
  }

  Widget _lotRow(String title, String lotId) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: lotId.trim().isEmpty ? const Text("(non défini)") : _lotLabel(lotId),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('daily_entries')
        .doc(dailyEntryDocId);

    return Scaffold(
      appBar: AppBar(
        title: Text("Détail – $dateIso"),
        actions: [
          IconButton(
            tooltip: "Modifier",
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final res = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => DailyEntryEditScreen(
                    farmId: farmId,
                    building: building,
                    dailyEntryDocId: dailyEntryDocId,
                    dateIso: dateIso,
                  ),
                ),
              );
              if (res == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Correction enregistrée ✅")),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                "Erreur: ${snap.error}",
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text("Document introuvable"));
          }

          final data = snap.data!.data() ?? <String, dynamic>{};

          final prod = _getMap(data, 'production');
          final broken = _getMap(data, 'broken');
          final feed = _getMap(data, 'feed');
          final water = _getMap(data, 'water');
          final vet = _getMap(data, 'vet');
          final mort = _getMap(data, 'mortality');

          final eggsByGrade = _getMap(prod, 'eggsByGrade');

          final lotIdProd = _getStr(prod, 'lotId', "");
          final feedItemId = _getStr(feed, 'feedItemId', "");
          final vetItemId = _getStr(vet, 'itemId', "");
          final lotIdVet = _getStr(vet, 'lotId', "");
          final lotIdMort = _getStr(mort, 'lotId', "");

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Text(
                  "Bâtiment : ${building.name}",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text("Date : $dateIso"),
                const Divider(height: 24),

                // =========================
                // PONTE
                // =========================
                _sectionTitle("Ponte"),
                if (prod.isEmpty)
                  const Text("Aucune donnée")
                else ...[
                  _kv("Total", "${_getInt(prod, 'totalEggs')} œufs"),
                  _lotRow("Lot", lotIdProd),
                  const SizedBox(height: 8),
                  _kv(_gradeFr('SMALL'), "${_getInt(eggsByGrade, 'SMALL')}"),
                  _kv(_gradeFr('MEDIUM'), "${_getInt(eggsByGrade, 'MEDIUM')}"),
                  _kv(_gradeFr('LARGE'), "${_getInt(eggsByGrade, 'LARGE')}"),
                  _kv(_gradeFr('XL'), "${_getInt(eggsByGrade, 'XL')}"),
                ],

                // =========================
                // CASSES
                // =========================
                _sectionTitle("Casses"),
                if (broken.isEmpty)
                  const Text("Aucune donnée")
                else ...[
                  _kv("Total", "${_getInt(broken, 'totalBrokenEggs')} œufs"),
                  _kv("Alvéoles", "${_getInt(broken, 'brokenAlveoles')}"),
                  _kv("Isolés", "${_getInt(broken, 'brokenIsolated')}"),
                  _kv("Note", _getStr(broken, 'note', "")),
                ],

                // =========================
                // ALIMENTS
                // =========================
                _sectionTitle("Aliments"),
                if (feed.isEmpty)
                  const Text("Aucune donnée")
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 140,
                        child: Text("Aliment", style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: feedItemId.isEmpty
                            ? const Text("(non défini)")
                            : _itemName(feedItemId),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _kv("Sacs (50 kg)", "${_getInt(feed, 'bags50')}"),
                  _kv("Kg total", "${_getInt(feed, 'kgTotal')}"),
                ],

                // =========================
                // EAU
                // =========================
                _sectionTitle("Eau"),
                if (water.isEmpty)
                  const Text("Aucune donnée")
                else ...[
                  _kv("Mode", _getStr(water, 'mode', "")),
                  _kv("Litres", "${_getInt(water, 'liters')}"),
                  _kv("Note", _getStr(water, 'note', "")),
                ],

                // =========================
                // VÉTÉRINAIRE
                // =========================
                _sectionTitle("Vétérinaire"),
                if (vet.isEmpty)
                  const Text("Aucune donnée")
                else if (vet['none'] == true)
                  const Text("Aucun traitement vétérinaire")
                else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: 140,
                          child: Text("Produit", style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: vetItemId.isEmpty
                              ? const Text("(non défini)")
                              : _itemName(vetItemId),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _kv(
                      "Quantité",
                      "${_getInt(vet, 'qtyUsed')} ${_getStr(vet, 'unitLabel', '')}".trim(),
                    ),
                    _lotRow("Lot", lotIdVet),
                    _kv("Note", _getStr(vet, 'note', "")),
                  ],

                // =========================
                // MORTALITÉ
                // =========================
                _sectionTitle("Mortalité"),
                if (mort.isEmpty)
                  const Text("Aucune donnée")
                else ...[
                  _kv("Quantité", "${_getInt(mort, 'qty')}"),
                  _kv("Cause", _getStr(mort, 'cause', "")),
                  _kv("Note", _getStr(mort, 'note', "")),
                  _lotRow("Lot", lotIdMort),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
