import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DepotReceiptScreen extends StatefulWidget {
  final String farmId;
  final String depotId;
  final String depotName;

  const DepotReceiptScreen({
    super.key,
    required this.farmId,
    required this.depotId,
    required this.depotName,
  });

  @override
  State<DepotReceiptScreen> createState() => _DepotReceiptScreenState();
}

class _DepotReceiptScreenState extends State<DepotReceiptScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _grades = <String>['SMALL', 'MEDIUM', 'LARGE', 'XL'];

  // CTI constants: Carton=12 alvéoles, 1 alvéole=30 oeufs
  static const int _eggsPerTray = 30;
  static const int _traysPerCarton = 12;
  static const int _eggsPerCarton = _eggsPerTray * _traysPerCarton; // 360

  bool _saving = false;

  // ✅ stable dropdown value
  String? _selectedTransferId;
  Map<String, dynamic>? _selectedTransferData;

  // ✅ controllers for GOOD received per grade (CTI)
  final Map<String, TextEditingController> _goodCartonsCtrl = {
    for (final g in _grades) g: TextEditingController(text: '0'),
  };
  final Map<String, TextEditingController> _goodTraysCtrl = {
    for (final g in _grades) g: TextEditingController(text: '0'),
  };
  final Map<String, TextEditingController> _goodIsolatedCtrl = {
    for (final g in _grades) g: TextEditingController(text: '0'),
  };

  // ✅ controllers for BROKEN received (no grade) (CTI)
  final TextEditingController _brokenCartonsCtrl = TextEditingController(text: '0');
  final TextEditingController _brokenTraysCtrl = TextEditingController(text: '0');
  final TextEditingController _brokenIsolatedCtrl = TextEditingController(text: '0');

  // ✅ controllers for LOSSES (no grade) (CTI)
  final TextEditingController _lossCartonsCtrl = TextEditingController(text: '0');
  final TextEditingController _lossTraysCtrl = TextEditingController(text: '0');
  final TextEditingController _lossIsolatedCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    for (final c in _goodCartonsCtrl.values) c.dispose();
    for (final c in _goodTraysCtrl.values) c.dispose();
    for (final c in _goodIsolatedCtrl.values) c.dispose();

    _brokenCartonsCtrl.dispose();
    _brokenTraysCtrl.dispose();
    _brokenIsolatedCtrl.dispose();

    _lossCartonsCtrl.dispose();
    _lossTraysCtrl.dispose();
    _lossIsolatedCtrl.dispose();

    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _movementsCol =>
      _db.collection('farms').doc(widget.farmId).collection('egg_movements');

  DocumentReference<Map<String, dynamic>> get _farmRef =>
      _db.collection('farms').doc(widget.farmId);

  DocumentReference<Map<String, dynamic>> get _depotStockRef => _db
      .collection('farms')
      .doc(widget.farmId)
      .collection('stocks_eggs')
      .doc('DEPOT_${widget.depotId}');

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int _ctiToEggs({
    required int cartons,
    required int trays,
    required int isolated,
  }) {
    if (cartons < 0 || trays < 0 || isolated < 0) return -1;
    // trays can exceed 11, we still accept and normalize via conversion
    return (cartons * _eggsPerCarton) + (trays * _eggsPerTray) + isolated;
  }

  Map<String, int> _eggsToCti(int eggs) {
    if (eggs < 0) eggs = 0;
    final cartons = eggs ~/ _eggsPerCarton;
    final rem = eggs % _eggsPerCarton;
    final trays = rem ~/ _eggsPerTray;
    final isolated = rem % _eggsPerTray;
    return {'cartons': cartons, 'trays': trays, 'isolated': isolated};
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
        return 'XL';
      default:
        return g;
    }
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  void _prefillFromTransfer(Map<String, dynamic> transfer) {
    final sentGoodByGrade = _asMap(transfer['goodOutByGrade']);
    for (final g in _grades) {
      final eggs = _asInt(sentGoodByGrade[g]);
      final cti = _eggsToCti(eggs);
      _goodCartonsCtrl[g]!.text = '${cti['cartons']}';
      _goodTraysCtrl[g]!.text = '${cti['trays']}';
      _goodIsolatedCtrl[g]!.text = '${cti['isolated']}';
    }

    final sentBroken = _asInt(_asMap(transfer['brokenOut'])['totalBrokenEggs']);
    final bCti = _eggsToCti(sentBroken);
    _brokenCartonsCtrl.text = '${bCti['cartons']}';
    _brokenTraysCtrl.text = '${bCti['trays']}';
    _brokenIsolatedCtrl.text = '${bCti['isolated']}';

    // losses default 0
    _lossCartonsCtrl.text = '0';
    _lossTraysCtrl.text = '0';
    _lossIsolatedCtrl.text = '0';
  }

  int _receivedGoodEggsForGrade(String g) {
    return _ctiToEggs(
      cartons: _i(_goodCartonsCtrl[g]!),
      trays: _i(_goodTraysCtrl[g]!),
      isolated: _i(_goodIsolatedCtrl[g]!),
    );
  }

  int _receivedBrokenEggs() {
    return _ctiToEggs(
      cartons: _i(_brokenCartonsCtrl),
      trays: _i(_brokenTraysCtrl),
      isolated: _i(_brokenIsolatedCtrl),
    );
  }

  int _lossEggs() {
    return _ctiToEggs(
      cartons: _i(_lossCartonsCtrl),
      trays: _i(_lossTraysCtrl),
      isolated: _i(_lossIsolatedCtrl),
    );
  }

  Map<String, dynamic> _computeSummary() {
    final t = _selectedTransferData ?? <String, dynamic>{};

    final sentGoodByGrade = _asMap(t['goodOutByGrade']);
    final sentGoodTotal = _asInt(t['goodOutTotalEggs']);
    final sentBrokenTotal = _asInt(_asMap(t['brokenOut'])['totalBrokenEggs']);
    final sentTotal = sentGoodTotal + sentBrokenTotal;

    // received
    final receivedGoodByGrade = <String, int>{};
    int receivedGoodTotal = 0;
    bool invalid = false;

    for (final g in _grades) {
      final eggs = _receivedGoodEggsForGrade(g);
      if (eggs < 0) invalid = true;
      receivedGoodByGrade[g] = eggs < 0 ? 0 : eggs;
      receivedGoodTotal += eggs < 0 ? 0 : eggs;
    }

    final receivedBroken = _receivedBrokenEggs();
    final loss = _lossEggs();

    if (receivedBroken < 0 || loss < 0) invalid = true;

    final receivedTotal = receivedGoodTotal + (receivedBroken < 0 ? 0 : receivedBroken) + (loss < 0 ? 0 : loss);

    final diff = sentTotal - receivedTotal; // must be 0 when strict

    return {
      'sentGoodByGrade': sentGoodByGrade,
      'sentGoodTotal': sentGoodTotal,
      'sentBrokenTotal': sentBrokenTotal,
      'sentTotal': sentTotal,

      'receivedGoodByGrade': receivedGoodByGrade,
      'receivedGoodTotal': receivedGoodTotal,
      'receivedBroken': receivedBroken < 0 ? 0 : receivedBroken,
      'loss': loss < 0 ? 0 : loss,
      'receivedTotal': receivedTotal,

      'diff': diff,
      'invalid': invalid,
    };
  }

  Future<void> _confirmReceipt() async {
    final transferId = _selectedTransferId;
    final transfer = _selectedTransferData;

    if (transferId == null || transferId.isEmpty || transfer == null) {
      _snack("Sélectionnez un transfert.");
      return;
    }
    if (_saving) return;

    final summary = _computeSummary();
    final invalid = summary['invalid'] == true;
    final diff = (summary['diff'] as int?) ?? 0;

    if (invalid) {
      _snack("Valeurs invalides (négatives) interdites.");
      return;
    }

    // ✅ strict equality
    if (diff != 0) {
      _snack("Incohérence : envoyés ≠ reçus + casses + pertes (diff=$diff). Corrigez les champs.");
      return;
    }

    final receivedGoodByGrade = Map<String, int>.from(summary['receivedGoodByGrade'] as Map);
    final receivedGoodTotal = summary['receivedGoodTotal'] as int;
    final receivedBroken = summary['receivedBroken'] as int;
    final loss = summary['loss'] as int;

    setState(() => _saving = true);

    try {
      final movementRef = _movementsCol.doc(transferId);
      final lockRef = _farmRef.collection('idempotency').doc('DEPOT_RECEIPT_STRICT_$transferId');

      await _db.runTransaction((tx) async {
        // ✅ READS FIRST
        final lockSnap = await tx.get(lockRef);
        if (lockSnap.exists) return;

        final movementSnap = await tx.get(movementRef);
        if (!movementSnap.exists) throw Exception("Transfert introuvable.");

        final m = movementSnap.data() ?? <String, dynamic>{};
        if ((m['status'] ?? '').toString() == 'RECEIVED') {
          throw Exception("Ce transfert est déjà reçu.");
        }

        final to = _asMap(m['to']);
        final toDepotId = (to['depotId'] ?? '').toString();
        if (toDepotId != widget.depotId) {
          throw Exception("Ce transfert ne correspond pas à ce dépôt.");
        }

        final now = FieldValue.serverTimestamp();

        // ✅ DEPOT stock: only received eggs are credited (good by grade + broken total)
        final depotUpdates = <String, dynamic>{
          'updatedAt': now,
          'source': 'depot_receipt',
          'goodTotalEggs': FieldValue.increment(receivedGoodTotal),
          'brokenTotalEggs': FieldValue.increment(receivedBroken),
        };

        for (final g in _grades) {
          depotUpdates['eggsByGrade.$g'] = FieldValue.increment(receivedGoodByGrade[g] ?? 0);
        }

        tx.set(_depotStockRef, depotUpdates, SetOptions(merge: true));

        // ✅ movement status + payload receipt
        tx.update(movementRef, {
          'status': 'RECEIVED',
          'receivedAt': now,
          'receivedDepotId': widget.depotId,

          // received payload
          'receivedGoodByGrade': receivedGoodByGrade,
          'receivedGoodTotalEggs': receivedGoodTotal,
          'receivedBrokenTotalEggs': receivedBroken,

          // losses payload
          'lossTotalEggs': loss,

          'updatedAt': now,
        });

        tx.set(lockRef, {
          'kind': 'DEPOT_RECEIPT_STRICT',
          'createdAt': now,
        });
      });

      _snack("Réception confirmée ✅", ok: true);

      setState(() {
        _selectedTransferId = null;
        _selectedTransferData = null;

        for (final g in _grades) {
          _goodCartonsCtrl[g]!.text = '0';
          _goodTraysCtrl[g]!.text = '0';
          _goodIsolatedCtrl[g]!.text = '0';
        }
        _brokenCartonsCtrl.text = '0';
        _brokenTraysCtrl.text = '0';
        _brokenIsolatedCtrl.text = '0';

        _lossCartonsCtrl.text = '0';
        _lossTraysCtrl.text = '0';
        _lossIsolatedCtrl.text = '0';
      });
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _ctiRow({
    required String label,
    required TextEditingController cartonsCtrl,
    required TextEditingController traysCtrl,
    required TextEditingController isolatedCtrl,
    String? helper,
    void Function()? onChanged,
  }) {
    Widget field(String hint, TextEditingController ctrl) {
      return SizedBox(
        width: 96,
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => onChanged?.call(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper, style: const TextStyle(color: Colors.black54)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            field('Cartons', cartonsCtrl),
            field('Alvéoles', traysCtrl),
            field('Isolés', isolatedCtrl),
          ],
        ),
      ],
    );
  }

  Widget _gradeCard({
    required String grade,
    required int sentEggs,
  }) {
    final sentCti = _eggsToCti(sentEggs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_gradeFr(grade), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              "Envoyé : ${sentCti['cartons']} c / ${sentCti['trays']} a / ${sentCti['isolated']} i  (≈ $sentEggs œufs)",
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            _ctiRow(
              label: "Reçu (modifiable)",
              cartonsCtrl: _goodCartonsCtrl[grade]!,
              traysCtrl: _goodTraysCtrl[grade]!,
              isolatedCtrl: _goodIsolatedCtrl[grade]!,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _movementsCol
        .where('type', isEqualTo: 'TRANSFER_FARM_TO_DEPOT')
        .where('to.depotId', isEqualTo: widget.depotId)
        .where('status', isEqualTo: 'SENT')
        .orderBy('createdAt', descending: true);

    final summary = _computeSummary();
    final sentGoodByGrade = _asMap(summary['sentGoodByGrade']);
    final sentGoodTotal = summary['sentGoodTotal'] as int? ?? 0;
    final sentBrokenTotal = summary['sentBrokenTotal'] as int? ?? 0;
    final sentTotal = summary['sentTotal'] as int? ?? 0;

    final receivedGoodTotal = summary['receivedGoodTotal'] as int? ?? 0;
    final receivedBroken = summary['receivedBroken'] as int? ?? 0;
    final loss = summary['loss'] as int? ?? 0;
    final receivedTotal = summary['receivedTotal'] as int? ?? 0;

    final diff = summary['diff'] as int? ?? 0;
    final invalid = summary['invalid'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text("Réception dépôt - ${widget.depotName}"),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text("Erreur: ${snap.error}"));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;

          // if selection becomes invalid, reset
          if (_selectedTransferId != null && docs.every((d) => d.id != _selectedTransferId)) {
            _selectedTransferId = null;
            _selectedTransferData = null;
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (docs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text("Aucun transfert en attente."),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedTransferId,
                  items: docs.map((doc) {
                    final d = doc.data();
                    final date = (d['date'] ?? '').toString();
                    final total = _asInt(d['goodOutTotalEggs']) + _asInt(_asMap(d['brokenOut'])['totalBrokenEggs']);
                    return DropdownMenuItem<String>(
                      value: doc.id,
                      child: Text("$date — $total œufs"),
                    );
                  }).toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final doc = docs.firstWhere((d) => d.id == id);
                    setState(() {
                      _selectedTransferId = id;
                      _selectedTransferData = doc.data();
                      _prefillFromTransfer(_selectedTransferData!);
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: "Transfert à recevoir",
                    border: OutlineInputBorder(),
                  ),
                ),

              const SizedBox(height: 12),

              if (_selectedTransferData != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Résumé", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text("Envoyé : bons=$sentGoodTotal, cassés=$sentBrokenTotal, total=$sentTotal"),
                        const SizedBox(height: 6),
                        Text("Reçu : bons=$receivedGoodTotal, cassés=$receivedBroken, pertes=$loss, total=$receivedTotal"),
                        const SizedBox(height: 10),
                        Text(
                          "Diff (envoyé - reçu) : $diff",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: (invalid || diff != 0) ? Colors.red : Colors.green,
                          ),
                        ),
                        if (invalid) ...[
                          const SizedBox(height: 8),
                          const Text("⚠️ Valeurs négatives interdites.", style: TextStyle(color: Colors.red)),
                        ],
                        if (!invalid && diff != 0) ...[
                          const SizedBox(height: 8),
                          const Text(
                            "⚠️ Corrigez les champs pour que : bons reçus + cassés reçus + pertes = total envoyé.",
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ✅ per grade CTI cards
                for (final g in _grades)
                  _gradeCard(
                    grade: g,
                    sentEggs: _asInt(sentGoodByGrade[g]),
                  ),

                const SizedBox(height: 12),

                // ✅ broken received (no grade) CTI
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _ctiRow(
                      label: "Casses reçues (sans calibre)",
                      helper: "Pré-rempli avec les casses envoyées. Modifiable si besoin.",
                      cartonsCtrl: _brokenCartonsCtrl,
                      traysCtrl: _brokenTraysCtrl,
                      isolatedCtrl: _brokenIsolatedCtrl,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ✅ losses (no grade) CTI
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _ctiRow(
                      label: "Pertes (sans calibre)",
                      helper: "Œufs manquants (ni bons, ni cassés).",
                      cartonsCtrl: _lossCartonsCtrl,
                      traysCtrl: _lossTraysCtrl,
                      isolatedCtrl: _lossIsolatedCtrl,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                ElevatedButton.icon(
                  onPressed: (_saving || invalid || diff != 0) ? null : _confirmReceipt,
                  icon: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.check),
                  label: Text(_saving ? "Traitement..." : "Confirmer réception"),
                ),
              ],

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
