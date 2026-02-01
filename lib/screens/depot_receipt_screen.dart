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
  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  String? _message;

  DateTime _selectedDate = DateTime.now();

  String? _selectedTransferId;
  Map<String, dynamic>? _selectedTransferData;

  // Saisie: bons par grade (cartons, alvéoles, isolés)
  final Map<String, TextEditingController> _goodCartons = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };
  final Map<String, TextEditingController> _goodTrays = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };
  final Map<String, TextEditingController> _goodIsolated = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };

  // Casses total
  final TextEditingController _brokenCartonsCtrl = TextEditingController(text: "0");
  final TextEditingController _brokenTraysCtrl = TextEditingController(text: "0");
  final TextEditingController _brokenIsolatedCtrl = TextEditingController(text: "0");

  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in _goodCartons.values) c.dispose();
    for (final c in _goodTrays.values) c.dispose();
    for (final c in _goodIsolated.values) c.dispose();
    _brokenCartonsCtrl.dispose();
    _brokenTraysCtrl.dispose();
    _brokenIsolatedCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _dateIso(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
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

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int _eggsFromCTI({required int cartons, required int trays, required int isolated}) {
    // 1 carton = 12 alvéoles ; 1 alvéole = 30 oeufs
    return ((cartons * 12 + trays) * 30) + isolated;
  }

  void _ctiFromEggs(int eggs, TextEditingController cCartons, TextEditingController cTrays, TextEditingController cIso) {
    if (eggs < 0) eggs = 0;
    final trays = eggs ~/ 30;
    final iso = eggs % 30;
    final cartons = trays ~/ 12;
    final traysR = trays % 12;
    cCartons.text = cartons.toString();
    cTrays.text = traysR.toString();
    cIso.text = iso.toString();
  }

  int _goodEggsForGrade(String g) {
    return _eggsFromCTI(
      cartons: _parse(_goodCartons[g]!),
      trays: _parse(_goodTrays[g]!),
      isolated: _parse(_goodIsolated[g]!),
    );
  }

  int _brokenEggsTotal() {
    return _eggsFromCTI(
      cartons: _parse(_brokenCartonsCtrl),
      trays: _parse(_brokenTraysCtrl),
      isolated: _parse(_brokenIsolatedCtrl),
    );
  }

  void _validateCTI({required String label, required int cartons, required int trays, required int isolated}) {
    if (cartons < 0 || trays < 0 || isolated < 0) throw Exception("$label : valeurs négatives interdites.");
    if (trays > 11) throw Exception("$label : alvéoles doit être entre 0 et 11 (par carton).");
    if (isolated > 29) throw Exception("$label : œufs isolés doit être entre 0 et 29.");
  }

  void _prefillFromTransfer(Map<String, dynamic> t) {
    final goodByGrade = _asMap(t['goodOutByGrade']);
    final brokenOut = _asMap(t['brokenOut']);

    for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      final eggs = _asInt(goodByGrade[g]);
      _ctiFromEggs(eggs, _goodCartons[g]!, _goodTrays[g]!, _goodIsolated[g]!);
    }

    final brokenTotal = _asInt(brokenOut['totalBrokenEggs']);
    _ctiFromEggs(brokenTotal, _brokenCartonsCtrl, _brokenTraysCtrl, _brokenIsolatedCtrl);

    _noteCtrl.text = "";
  }

  String _receiptLockId(String transferId) => ['DEPOT_RECEIPT', widget.farmId, widget.depotId, transferId].join('|');

  /// ✅ Option B sans getAll(): Future.wait(ref.get())
  Future<Set<String>> _fetchReceivedTransferIds(List<QueryDocumentSnapshot<Map<String, dynamic>>> transfers) async {
    if (transfers.isEmpty) return <String>{};

    final farmRef = _db.collection('farms').doc(widget.farmId);

    final futures = transfers.map((t) {
      final lockId = _receiptLockId(t.id);
      return farmRef.collection('idempotency').doc(lockId).get();
    }).toList();

    final snaps = await Future.wait(futures);

    final received = <String>{};
    for (int i = 0; i < snaps.length; i++) {
      if (snaps[i].exists) {
        received.add(transfers[i].id);
      }
    }
    return received;
  }

  Future<void> _saveReceipt() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final transferId = _selectedTransferId;
      final transfer = _selectedTransferData;

      if (transferId == null || transferId.isEmpty || transfer == null) {
        throw Exception("Veuillez sélectionner un transfert à réceptionner.");
      }

      for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
        _validateCTI(
          label: "Bons (${_gradeFr(g)})",
          cartons: _parse(_goodCartons[g]!),
          trays: _parse(_goodTrays[g]!),
          isolated: _parse(_goodIsolated[g]!),
        );
      }
      _validateCTI(
        label: "Casses",
        cartons: _parse(_brokenCartonsCtrl),
        trays: _parse(_brokenTraysCtrl),
        isolated: _parse(_brokenIsolatedCtrl),
      );

      final dateIso = _dateIso(_selectedDate);

      final receivedGood = <String, int>{
        'SMALL': _goodEggsForGrade('SMALL'),
        'MEDIUM': _goodEggsForGrade('MEDIUM'),
        'LARGE': _goodEggsForGrade('LARGE'),
        'XL': _goodEggsForGrade('XL'),
      };
      final receivedGoodTotal = receivedGood.values.fold<int>(0, (a, b) => a + b);
      final receivedBrokenTotal = _brokenEggsTotal();

      final farmRef = _db.collection('farms').doc(widget.farmId);
      final stockRef = farmRef.collection('stocks_eggs').doc("DEPOT_${widget.depotId}");
      final receiptRef = farmRef.collection('egg_movements').doc();

      final uniqueKey = _receiptLockId(transferId);
      final lockRef = farmRef.collection('idempotency').doc(uniqueKey);

      final from = _asMap(transfer['from']);
      final to = _asMap(transfer['to']);
      final transferDate = (transfer['date'] ?? '').toString();

      await _db.runTransaction((tx) async {
        final lockSnap = await tx.get(lockRef);
        if (lockSnap.exists) return;

        final stockSnap = await tx.get(stockRef);
        final stockData = stockSnap.data() ?? <String, dynamic>{};

        Map<String, int> pickGoodByGrade(Map<String, dynamic> data) {
          Map<String, int> readGrades(String key) {
            final raw = data[key];
            final m = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
            int gi(String k) => _asInt(m[k]);
            return {'SMALL': gi('SMALL'), 'MEDIUM': gi('MEDIUM'), 'LARGE': gi('LARGE'), 'XL': gi('XL')};
          }

          final good = readGrades('goodByGrade');
          final eggs = readGrades('eggsByGrade');

          int pick(String g) {
            final v = good[g] ?? 0;
            if (v != 0) return v;
            return eggs[g] ?? 0;
          }

          return {'SMALL': pick('SMALL'), 'MEDIUM': pick('MEDIUM'), 'LARGE': pick('LARGE'), 'XL': pick('XL')};
        }

        final currentGood = pickGoodByGrade(stockData);
        final currentBroken = _asInt(stockData['brokenTotalEggs']);

        final newGood = <String, int>{
          'SMALL': (currentGood['SMALL'] ?? 0) + receivedGood['SMALL']!,
          'MEDIUM': (currentGood['MEDIUM'] ?? 0) + receivedGood['MEDIUM']!,
          'LARGE': (currentGood['LARGE'] ?? 0) + receivedGood['LARGE']!,
          'XL': (currentGood['XL'] ?? 0) + receivedGood['XL']!,
        };
        final newBroken = currentBroken + receivedBrokenTotal;

        tx.set(receiptRef, {
          'date': dateIso,
          'type': 'DEPOT_RECEIPT',
          'depot': {'id': widget.depotId, 'name': widget.depotName},
          'refTransferId': transferId,
          'refTransferDate': transferDate,
          'from': from,
          'to': to,
          'receivedGoodInByGrade': receivedGood,
          'receivedGoodInTotal': receivedGoodTotal,
          'receivedBrokenIn': {'totalBrokenEggs': receivedBrokenTotal},
          'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        });

        tx.set(stockRef, {
          'kind': 'DEPOT',
          'locationType': 'DEPOT',
          'locationId': widget.depotId,
          'refId': widget.depotId,
          'goodByGrade': newGood,
          'eggsByGrade': newGood,
          'goodTotalEggs': newGood.values.fold<int>(0, (a, b) => a + b),
          'brokenTotalEggs': newBroken,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(lockRef, {
          'kind': 'DEPOT_RECEIPT',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // ❌ NE PAS updater le doc transfert (update interdit dans rules)
      });

      setState(() {
        _message = "Réception enregistrée ✅";
        _selectedTransferId = null;
        _selectedTransferData = null;
      });

      for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
        _goodCartons[g]!.text = "0";
        _goodTrays[g]!.text = "0";
        _goodIsolated[g]!.text = "0";
      }
      _brokenCartonsCtrl.text = "0";
      _brokenTraysCtrl.text = "0";
      _brokenIsolatedCtrl.text = "0";
      _noteCtrl.clear();
    } catch (e) {
      setState(() => _message = "Erreur : ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _ctiRow({
    required String title,
    required TextEditingController cCartons,
    required TextEditingController cTrays,
    required TextEditingController cIso,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: cCartons,
                keyboardType: TextInputType.number,
                enabled: !_loading,
                decoration: const InputDecoration(labelText: "Cartons", border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: cTrays,
                keyboardType: TextInputType.number,
                enabled: !_loading,
                decoration: const InputDecoration(labelText: "Alvéoles (0..11)", border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: cIso,
                keyboardType: TextInputType.number,
                enabled: !_loading,
                decoration: const InputDecoration(labelText: "Isolés (0..29)", border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final msg = _message;
    final farmRef = _db.collection('farms').doc(widget.farmId);

    final now = DateTime.now();
    final fromDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 60));
    final fromIso = _dateIso(fromDate);

    final transfersQuery = farmRef
        .collection('egg_movements')
        .where('type', isEqualTo: 'TRANSFER')
        .where('to.kind', isEqualTo: 'DEPOT')
        .where('to.id', isEqualTo: widget.depotId)
        .where('date', isGreaterThanOrEqualTo: fromIso)
        .orderBy('date', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(100);

    return Scaffold(
      appBar: AppBar(
        title: Text("Réception – ${widget.depotName}"),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : _pickDate,
            icon: const Icon(Icons.date_range),
            label: Text(_dateIso(_selectedDate)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text("Sélectionner un transfert à réceptionner", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: transfersQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text("Erreur transferts: ${snap.error}", style: const TextStyle(color: Colors.red));
                }
                if (!snap.hasData) return const LinearProgressIndicator();

                final allTransfers = snap.data!.docs;

                if (allTransfers.isEmpty) {
                  return const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text("Aucun transfert"),
                      subtitle: Text("Aucun transfert récent détecté pour ce dépôt."),
                    ),
                  );
                }

                return FutureBuilder<Set<String>>(
                  future: _fetchReceivedTransferIds(allTransfers),
                  builder: (context, receivedSnap) {
                    if (receivedSnap.connectionState == ConnectionState.waiting) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Expanded(child: Text("Chargement des transferts non réceptionnés...")),
                            ],
                          ),
                        ),
                      );
                    }

                    final receivedIds = receivedSnap.data ?? <String>{};
                    final pendingTransfers = allTransfers.where((t) => !receivedIds.contains(t.id)).toList();

                    if (pendingTransfers.isEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (_selectedTransferId != null) {
                          setState(() {
                            _selectedTransferId = null;
                            _selectedTransferData = null;
                          });
                        }
                      });

                      return const Card(
                        child: ListTile(
                          leading: Icon(Icons.check_circle_outline),
                          title: Text("Tout est déjà réceptionné"),
                          subtitle: Text("Aucun transfert en attente de réception pour ce dépôt."),
                        ),
                      );
                    }

                    if (_selectedTransferId != null && !pendingTransfers.any((t) => t.id == _selectedTransferId)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _selectedTransferId = null;
                          _selectedTransferData = null;
                        });
                      });
                    }

                    String fmtCTI(int eggs) {
                      final trays = eggs ~/ 30;
                      final cartons = trays ~/ 12;
                      final traysR = trays % 12;
                      final iso = eggs % 30;
                      return "$cartons c • $traysR a • $iso i";
                    }

                    return DropdownButtonFormField<String>(
                      value: _selectedTransferId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Transfert (non réceptionné)",
                        border: OutlineInputBorder(),
                      ),
                      items: pendingTransfers.map((d) {
                        final data = d.data();
                        final date = (data['date'] ?? '').toString();
                        final from = _asMap(data['from']);
                        final fromName = (from['name'] ?? from['id'] ?? 'FARM').toString();

                        final goodOutTotal = _asInt(data['goodOutTotal']);
                        final brokenOut = _asMap(data['brokenOut']);
                        final brokenTotal = _asInt(brokenOut['totalBrokenEggs']);

                        final label =
                            "$date — depuis $fromName — Bons: ${fmtCTI(goodOutTotal)} — Casses: ${fmtCTI(brokenTotal)}";

                        return DropdownMenuItem<String>(
                          value: d.id,
                          child: Text(label, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: _loading
                          ? null
                          : (v) {
                        if (v == null) return;
                        final doc = pendingTransfers.firstWhere((d) => d.id == v);
                        final data = doc.data();
                        setState(() {
                          _selectedTransferId = v;
                          _selectedTransferData = data;
                        });
                        _prefillFromTransfer(data);
                      },
                    );
                  },
                );
              },
            ),

            const Divider(height: 28),

            Text("Quantités reçues (bons œufs)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),

            _ctiRow(title: "Petit calibre", cCartons: _goodCartons['SMALL']!, cTrays: _goodTrays['SMALL']!, cIso: _goodIsolated['SMALL']!),
            const SizedBox(height: 12),
            _ctiRow(title: "Moyen calibre", cCartons: _goodCartons['MEDIUM']!, cTrays: _goodTrays['MEDIUM']!, cIso: _goodIsolated['MEDIUM']!),
            const SizedBox(height: 12),
            _ctiRow(title: "Gros calibre", cCartons: _goodCartons['LARGE']!, cTrays: _goodTrays['LARGE']!, cIso: _goodIsolated['LARGE']!),
            const SizedBox(height: 12),
            _ctiRow(title: "Très gros calibre", cCartons: _goodCartons['XL']!, cTrays: _goodTrays['XL']!, cIso: _goodIsolated['XL']!),

            const Divider(height: 28),

            Text("Casses reçues", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),

            _ctiRow(title: "Casses (total)", cCartons: _brokenCartonsCtrl, cTrays: _brokenTraysCtrl, cIso: _brokenIsolatedCtrl),

            const Divider(height: 28),

            TextField(
              controller: _noteCtrl,
              enabled: !_loading,
              decoration: const InputDecoration(labelText: "Note (optionnel)", border: OutlineInputBorder()),
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _loading ? null : _saveReceipt,
              icon: const Icon(Icons.save),
              label: Text(_loading ? "Enregistrement..." : "Enregistrer la réception"),
            ),

            const SizedBox(height: 12),

            if (msg != null)
              Text(
                msg,
                style: TextStyle(color: msg.startsWith("Erreur") ? Colors.red : Colors.green),
              ),
          ],
        ),
      ),
    );
  }
}
