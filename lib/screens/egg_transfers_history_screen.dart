import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EggTransfersHistoryScreen extends StatefulWidget {
  final String farmId;

  const EggTransfersHistoryScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<EggTransfersHistoryScreen> createState() => _EggTransfersHistoryScreenState();
}

class _EggTransfersHistoryScreenState extends State<EggTransfersHistoryScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

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

  String _ymLabel(DateTime d) {
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    return "${months[d.month - 1]} ${d.year}";
  }

  String _dateIso(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);

  DateTime _monthEndExclusive(DateTime d) {
    if (d.month == 12) return DateTime(d.year + 1, 1, 1);
    return DateTime(d.year, d.month + 1, 1);
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(now.year - 3, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: "Choisir une date (le mois sera utilisé)",
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month, 1));
    }
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  String _receiptLockId({
    required String transferId,
    required String depotId,
  }) {
    return ['DEPOT_RECEIPT', widget.farmId, depotId, transferId].join('|');
  }

  /// ✅ Récupère le set des transferts "reçus" pour la page affichée.
  /// Compat cloud_firestore 6.x: Future.wait(docRef.get())
  Future<Set<String>> _fetchReceivedForVisibleDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    if (docs.isEmpty) return <String>{};

    final db = FirebaseFirestore.instance;
    final farmRef = db.collection('farms').doc(widget.farmId);

    final futures = docs.map((doc) {
      final d = doc.data();
      final to = _asMap(d['to']);
      final depotId = (to['id'] ?? '').toString().trim();
      if (depotId.isEmpty) {
        // pas un transfert vers dépôt => jamais "reçu" (dans notre sens)
        return Future.value(null);
      }
      final lockId = _receiptLockId(transferId: doc.id, depotId: depotId);
      return farmRef.collection('idempotency').doc(lockId).get();
    }).toList();

    final snaps = await Future.wait(futures);

    final received = <String>{};
    for (int i = 0; i < docs.length; i++) {
      final snap = snaps[i];
      if (snap != null && snap.exists) {
        received.add(docs[i].id);
      }
    }
    return received;
  }

  Widget _statusChip({required bool received}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: received ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: received ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Text(
        received ? "Reçu" : "En attente",
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: received ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final farmRef = db.collection('farms').doc(widget.farmId);

    final start = _monthStart(_selectedMonth);
    final endExcl = _monthEndExclusive(_selectedMonth);

    final startIso = _dateIso(start);
    final endIso = _dateIso(endExcl);

    final query = farmRef
        .collection('egg_movements')
        .where('type', isEqualTo: 'TRANSFER')
        .where('date', isGreaterThanOrEqualTo: startIso)
        .where('date', isLessThan: endIso)
        .orderBy('date', descending: true)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historique transferts"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text("Période"),
                subtitle: Text(_ymLabel(_selectedMonth)),
                trailing: TextButton(
                  onPressed: _pickMonth,
                  child: const Text("Changer"),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text("Erreur: ${snap.error}", style: const TextStyle(color: Colors.red)),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      "Aucun transfert pour ${_ymLabel(_selectedMonth)}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                // ✅ Badge "Reçu" basé sur idempotency
                return FutureBuilder<Set<String>>(
                  future: _fetchReceivedForVisibleDocs(docs),
                  builder: (context, receivedSnap) {
                    final receivedIds = receivedSnap.data ?? <String>{};

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();

                        final date = (d['date'] ?? '').toString();

                        final from = _asMap(d['from']);
                        final to = _asMap(d['to']);

                        final fromName = (from['name'] ?? from['id'] ?? '').toString();
                        final toName = (to['name'] ?? to['id'] ?? '').toString();
                        final fromKind = (from['kind'] ?? '').toString();
                        final toKind = (to['kind'] ?? '').toString();

                        String labelFrom() {
                          if (fromName.isEmpty) return "Origine";
                          if (fromKind.isEmpty) return fromName;
                          return "$fromKind : $fromName";
                        }

                        String labelTo() {
                          if (toName.isEmpty) return "Destination";
                          if (toKind.isEmpty) return toName;
                          return "$toKind : $toName";
                        }

                        final goodByGrade = (d['goodOutByGrade'] is Map)
                            ? Map<String, dynamic>.from(d['goodOutByGrade'])
                            : <String, dynamic>{};

                        final goodTotal = _asInt(d['goodOutTotal']);

                        final broken = _asMap(d['brokenOut']);
                        final brokenTotal = _asInt(broken['totalBrokenEggs']);

                        final note = (d['note'] ?? '').toString().trim();

                        final gradeLines = <Widget>[];
                        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
                          final v = goodByGrade[g];
                          final qty = (v is num) ? v.toInt() : 0;
                          if (qty <= 0) continue;
                          gradeLines.add(Text("- ${_gradeFr(g)} : $qty"));
                        }

                        final received = receivedIds.contains(doc.id);

                        return Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "Date : $date",
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                                    _statusChip(received: received),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    const Icon(Icons.upload, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(labelFrom())),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.download, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(labelTo())),
                                  ],
                                ),

                                const Divider(height: 18),

                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    "Bons: $goodTotal • Casses: $brokenTotal",
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                const Text("Détails (bons œufs)", style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                if (gradeLines.isEmpty)
                                  const Text("- Aucun", style: TextStyle(color: Colors.grey))
                                else
                                  ...gradeLines,

                                if (note.isNotEmpty) ...[
                                  const Divider(height: 18),
                                  Text("Note : $note", style: const TextStyle(fontStyle: FontStyle.italic)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
