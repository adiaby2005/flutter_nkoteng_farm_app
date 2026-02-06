import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/subject_lot_service.dart';

class SubjectsOverviewScreen extends StatelessWidget {
  const SubjectsOverviewScreen({super.key});

  static const String _farmId = SubjectLotService.farmId;

  String _asStr(dynamic v) => (v ?? '').toString();
  int _asInt(dynamic v) => (v is num) ? v.toInt() : 0;

  @override
  Widget build(BuildContext context) {
    final farmRef = FirebaseFirestore.instance.collection('farms').doc(_farmId);

    final activeLotsStream = farmRef.collection('building_active_lots').snapshots();
    final buildingsStream = farmRef.collection('buildings').snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text("Sujets - Vue ferme")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: activeLotsStream,
        builder: (context, activeSnap) {
          if (activeSnap.hasError) {
            return _err("Erreur active lots: ${activeSnap.error}");
          }
          if (!activeSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final activeDocs = activeSnap.data!.docs.where((d) => d.data()['active'] == true).toList();

          // Map buildingId -> activeLot
          final activeByBuilding = <String, Map<String, dynamic>>{};
          for (final d in activeDocs) {
            activeByBuilding[d.id] = d.data();
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: buildingsStream,
            builder: (context, bSnap) {
              if (bSnap.hasError) return _err("Erreur buildings: ${bSnap.error}");
              if (!bSnap.hasData) return const Center(child: CircularProgressIndicator());

              final buildings = bSnap.data!.docs;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryCard(farmRef, buildings, activeByBuilding),
                  const SizedBox(height: 12),
                  const Text("Détails par bâtiment",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),

                  ...buildings.map((b) {
                    final bId = b.id;
                    final bData = b.data();
                    final bName = _asStr(bData['name']).trim().isEmpty ? bId : _asStr(bData['name']);
                    final active = activeByBuilding[bId];

                    return _buildingCard(
                      context: context,
                      farmRef: farmRef,
                      buildingId: bId,
                      buildingName: bName,
                      activeLot: active,
                    );
                  }),

                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _err(String msg) =>
      Center(child: Text(msg, style: const TextStyle(color: Colors.red)));

  Widget _summaryCard(
      DocumentReference<Map<String, dynamic>> farmRef,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> buildings,
      Map<String, Map<String, dynamic>> activeByBuilding,
      ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Résumé ferme", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            FutureBuilder<int>(
              future: _computeFarmTotal(farmRef, buildings),
              builder: (context, snap) => Text("Total sujets (ferme) : ${snap.data ?? 0}"),
            ),
            const SizedBox(height: 10),
            FutureBuilder<Map<String, int>>(
              future: _computeByStrain(farmRef, activeByBuilding),
              builder: (context, snap) {
                final map = snap.data ?? {};
                if (map.isEmpty) return const Text("Aucun lot actif.");
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Par souche (lots actifs) :"),
                    const SizedBox(height: 6),
                    ...map.entries.map((e) => Text("• ${e.key} : ${e.value}")),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<int> _computeFarmTotal(
      DocumentReference<Map<String, dynamic>> farmRef,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> buildings,
      ) async {
    int sum = 0;
    for (final b in buildings) {
      final stockSnap = await farmRef
          .collection('stocks_subjects')
          .doc('BUILDING_${b.id}')
          .get(const GetOptions(source: Source.serverAndCache));
      sum += _asInt(stockSnap.data()?['totalOnHand']);
    }
    return sum;
  }

  Future<Map<String, int>> _computeByStrain(
      DocumentReference<Map<String, dynamic>> farmRef,
      Map<String, Map<String, dynamic>> activeByBuilding,
      ) async {
    final out = <String, int>{};

    for (final entry in activeByBuilding.entries) {
      final bId = entry.key;
      final active = entry.value;

      final strain = _asStr(active['strain']).trim().isEmpty ? 'INCONNU' : _asStr(active['strain']).trim();

      final stockSnap = await farmRef
          .collection('stocks_subjects')
          .doc('BUILDING_$bId')
          .get(const GetOptions(source: Source.serverAndCache));

      final qty = _asInt(stockSnap.data()?['totalOnHand']);
      out[strain] = (out[strain] ?? 0) + qty;
    }
    return out;
  }

  Widget _buildingCard({
    required BuildContext context,
    required DocumentReference<Map<String, dynamic>> farmRef,
    required String buildingId,
    required String buildingName,
    required Map<String, dynamic>? activeLot,
  }) {
    final hasActive = activeLot != null && activeLot['active'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(buildingName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: farmRef
                  .collection('stocks_subjects')
                  .doc('BUILDING_$buildingId')
                  .get(const GetOptions(source: Source.serverAndCache)),
              builder: (context, snap) {
                final qty = _asInt(snap.data?.data()?['totalOnHand']);
                return Text("Stock sujets : $qty");
              },
            ),

            const SizedBox(height: 8),
            if (!hasActive)
              const Text("Lot actif : aucun", style: TextStyle(color: Colors.grey))
            else
              _activeLotLine(activeLot!),
          ],
        ),
      ),
    );
  }

  Widget _activeLotLine(Map<String, dynamic> active) {
    final strain = _asStr(active['strain']).trim().isEmpty ? 'INCONNU' : _asStr(active['strain']).trim();

    DateTime? startedAt;
    final ts = active['startedAt'];
    if (ts is Timestamp) startedAt = ts.toDate();

    final startAgeWeeks = _asInt(active['startAgeWeeks']);
    final startAgeDays = _asInt(active['startAgeDays']);

    String ageLabel = "âge: ?";
    if (startedAt != null) {
      final age = SubjectLotService.computeAge(
        startedAt: startedAt,
        startAgeWeeks: startAgeWeeks,
        startAgeDays: startAgeDays,
      );
      ageLabel = "âge: ${age['weeks']} sem + ${age['days']} j";
    }

    return Text("Lot actif : $strain, $ageLabel");
  }
}
