// lib/screens/egg_transfer_farm_to_depot_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EggTransferFarmToDepotScreen extends StatefulWidget {
  final String farmId;
  const EggTransferFarmToDepotScreen({super.key, required this.farmId});

  @override
  State<EggTransferFarmToDepotScreen> createState() => _EggTransferFarmToDepotScreenState();
}

class _EggTransferFarmToDepotScreenState extends State<EggTransferFarmToDepotScreen> {
  final _db = FirebaseFirestore.instance;

  static const List<String> _grades = ['SMALL', 'MEDIUM', 'LARGE', 'XL'];

  bool _loading = false;
  String? _message;

  String? _selectedDepotId;
  String? _selectedDepotName;

  // CTI inputs for GOOD eggs per grade
  final Map<String, TextEditingController> _goodCartons = {
    'SMALL': TextEditingController(text: '0'),
    'MEDIUM': TextEditingController(text: '0'),
    'LARGE': TextEditingController(text: '0'),
    'XL': TextEditingController(text: '0'),
  };
  final Map<String, TextEditingController> _goodTrays = {
    'SMALL': TextEditingController(text: '0'),
    'MEDIUM': TextEditingController(text: '0'),
    'LARGE': TextEditingController(text: '0'),
    'XL': TextEditingController(text: '0'),
  };
  final Map<String, TextEditingController> _goodIsolated = {
    'SMALL': TextEditingController(text: '0'),
    'MEDIUM': TextEditingController(text: '0'),
    'LARGE': TextEditingController(text: '0'),
    'XL': TextEditingController(text: '0'),
  };

  // Broken total (no grades)
  final TextEditingController _brokenCartonsCtrl = TextEditingController(text: '0');
  final TextEditingController _brokenTraysCtrl = TextEditingController(text: '0');
  final TextEditingController _brokenIsolatedCtrl = TextEditingController(text: '0');

  final TextEditingController _noteCtrl = TextEditingController();

  // Stock cache (farm global)
  Map<String, int> _farmGoodByGrade = {'SMALL': 0, 'MEDIUM': 0, 'LARGE': 0, 'XL': 0};
  int _farmGoodTotal = 0;
  int _farmBrokenTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadFarmStock(server: false);
  }

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

  DocumentReference<Map<String, dynamic>> get _farmRef =>
      _db.collection('farms').doc(widget.farmId);

  DocumentReference<Map<String, dynamic>> get _farmGlobalStockRef =>
      _farmRef.collection('stocks_eggs').doc('FARM_GLOBAL');

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

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? 0}') ?? 0;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  // 1 alvéole = 30 oeufs ; 1 carton = 12 alvéoles
  static const int _eggsPerTray = 30;
  static const int _traysPerCarton = 12;

  int _eggsFromCTI({required int cartons, required int trays, required int isolated}) {
    return ((cartons * _traysPerCarton + trays) * _eggsPerTray) + isolated;
  }

  Map<String, int> _ctiFromEggs(int eggs) {
    if (eggs < 0) eggs = 0;
    final perCarton = _traysPerCarton * _eggsPerTray;
    final cartons = eggs ~/ perCarton;
    final rem1 = eggs % perCarton;
    final trays = rem1 ~/ _eggsPerTray;
    final isolated = rem1 % _eggsPerTray;
    return {'cartons': cartons, 'trays': trays, 'isolated': isolated};
  }

  void _validateCTI({required String label, required int cartons, required int trays, required int isolated}) {
    if (cartons < 0 || trays < 0 || isolated < 0) {
      throw Exception("$label : valeurs négatives interdites.");
    }
    if (trays > 11) {
      throw Exception("$label : alvéoles doit être entre 0 et 11 (par carton).");
    }
    if (isolated > 29) {
      throw Exception("$label : œufs isolés doit être entre 0 et 29.");
    }
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

  Future<void> _loadFarmStock({required bool server}) async {
    try {
      final snap = await _farmGlobalStockRef.get(GetOptions(
        source: server ? Source.server : Source.serverAndCache,
      ));
      final data = snap.data() ?? <String, dynamic>{};

      final eggsByGrade = _asMap(data['eggsByGrade']);
      final goodTotal = _asInt(data['goodTotalEggs']);
      final brokenTotal = _asInt(data['brokenTotalEggs']);

      final map = <String, int>{
        'SMALL': _asInt(eggsByGrade['SMALL']),
        'MEDIUM': _asInt(eggsByGrade['MEDIUM']),
        'LARGE': _asInt(eggsByGrade['LARGE']),
        'XL': _asInt(eggsByGrade['XL']),
      };

      if (!mounted) return;
      setState(() {
        _farmGoodByGrade = map;
        _farmGoodTotal = goodTotal;
        _farmBrokenTotal = brokenTotal;
      });
    } catch (_) {
      // ne bloque pas l'écran
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

  String _transferLockId(String depotId, String payloadHash) =>
      ['EGG_TRANSFER_FARM_TO_DEPOT', widget.farmId, depotId, payloadHash].join('|');

  Future<void> _saveTransfer() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final depotId = _selectedDepotId;
      final depotName = _selectedDepotName;

      if (depotId == null || depotId.isEmpty) {
        throw Exception("Veuillez sélectionner un dépôt.");
      }

      // Validate inputs
      for (final g in _grades) {
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

      // Build eggs to transfer
      final goodOutByGrade = <String, int>{
        'SMALL': _goodEggsForGrade('SMALL'),
        'MEDIUM': _goodEggsForGrade('MEDIUM'),
        'LARGE': _goodEggsForGrade('LARGE'),
        'XL': _goodEggsForGrade('XL'),
      };
      final goodOutTotal = goodOutByGrade.values.fold<int>(0, (a, b) => a + b);
      final brokenOutTotal = _brokenEggsTotal();

      if (goodOutTotal == 0 && brokenOutTotal == 0) {
        throw Exception("Aucune quantité saisie.");
      }

      // Prepare refs
      final farmGlobalRef = _farmGlobalStockRef;
      final depotStockRef = _farmRef.collection('stocks_eggs').doc('DEPOT_$depotId');
      final movementRef = _farmRef.collection('egg_movements').doc();

      // Idempotency lock based on payload (simple & stable)
      final payloadHash = [
        DateTime.now().toIso8601String().substring(0, 10), // day
        goodOutByGrade['SMALL'],
        goodOutByGrade['MEDIUM'],
        goodOutByGrade['LARGE'],
        goodOutByGrade['XL'],
        brokenOutTotal,
        depotId,
      ].join('_');

      final lockRef = _farmRef.collection('idempotency').doc(_transferLockId(depotId, payloadHash));

      await _db.runTransaction((tx) async {
        // ✅ IMPORTANT: all reads first
        final lockSnap = await tx.get(lockRef);
        if (lockSnap.exists) return;

        final farmSnap = await tx.get(farmGlobalRef);
        final depotSnap = await tx.get(depotStockRef);

        final farmData = farmSnap.data() ?? <String, dynamic>{};
        final farmEggsByGrade = _asMap(farmData['eggsByGrade']);

        int farmGood(String g) => _asInt(farmEggsByGrade[g]);
        final farmGoodTotal = _asInt(farmData['goodTotalEggs']);
        final farmBrokenTotal = _asInt(farmData['brokenTotalEggs']);

        // Validate availability (farm)
        for (final g in _grades) {
          final want = goodOutByGrade[g] ?? 0;
          final have = farmGood(g);
          if (want > have) {
            throw Exception("Stock ferme insuffisant (${_gradeFr(g)}) : $have dispo, $want demandé.");
          }
        }
        if (brokenOutTotal > farmBrokenTotal) {
          throw Exception("Stock ferme insuffisant (cassés) : $farmBrokenTotal dispo, $brokenOutTotal demandé.");
        }

        final now = FieldValue.serverTimestamp();

        // ---- Update FARM_GLOBAL (decrement)
        final Map<String, dynamic> farmUpdates = {
          'updatedAt': now,
          'source': 'farm_to_depot_transfer',
          'computedFrom': 'MOVEMENTS', // optionnel, indicatif
          'goodTotalEggs': FieldValue.increment(-goodOutTotal),
          'brokenTotalEggs': FieldValue.increment(-brokenOutTotal),
        };
        for (final g in _grades) {
          final v = goodOutByGrade[g] ?? 0;
          if (v != 0) {
            farmUpdates['eggsByGrade.$g'] = FieldValue.increment(-v);
          }
        }
        tx.set(farmGlobalRef, {'updatedAt': now}, SetOptions(merge: true));
        tx.update(farmGlobalRef, farmUpdates);

        // ---- Update DEPOT stock (increment)
        final Map<String, dynamic> depotUpdates = {
          'updatedAt': now,
          'source': 'farm_to_depot_transfer',
          'depotId': depotId,
          'goodTotalEggs': FieldValue.increment(goodOutTotal),
          'brokenTotalEggs': FieldValue.increment(brokenOutTotal),
        };
        for (final g in _grades) {
          final v = goodOutByGrade[g] ?? 0;
          if (v != 0) {
            depotUpdates['eggsByGrade.$g'] = FieldValue.increment(v);
          }
        }
        tx.set(depotStockRef, {'updatedAt': now}, SetOptions(merge: true));
        // depotSnap is read above (ok) even if doc doesn't exist yet; update requires existence -> so use set(merge)
        tx.set(depotStockRef, depotUpdates, SetOptions(merge: true));

        // ---- Movement doc (for receipt dropdown on depot side)
        tx.set(movementRef, {
          'type': 'TRANSFER_FARM_TO_DEPOT',
          'status': 'SENT', // réception fera un lock et/ou un mouvement RECEIPT
          'date': DateTime.now().toIso8601String().substring(0, 10),
          'from': {
            'kind': 'FARM',
            'farmId': widget.farmId,
          },
          'to': {
            'kind': 'DEPOT',
            'depotId': depotId,
            'depotName': depotName ?? depotId,
          },
          'goodOutByGrade': goodOutByGrade,
          'goodOutTotalEggs': goodOutTotal,
          'brokenOut': {
            'totalBrokenEggs': brokenOutTotal,
          },
          'note': _noteCtrl.text.trim(),
          'createdAt': now,
          'source': 'mobile_app',
        });

        // ---- Lock
        tx.set(lockRef, {
          'kind': 'EGG_TRANSFER_FARM_TO_DEPOT',
          'createdAt': now,
        });
      });

      // reload stock server
      await _loadFarmStock(server: true);

      // reset inputs
      for (final g in _grades) {
        _goodCartons[g]!.text = '0';
        _goodTrays[g]!.text = '0';
        _goodIsolated[g]!.text = '0';
      }
      _brokenCartonsCtrl.text = '0';
      _brokenTraysCtrl.text = '0';
      _brokenIsolatedCtrl.text = '0';
      _noteCtrl.clear();

      if (!mounted) return;
      setState(() {
        _message = "✅ Transfert enregistré";
      });
      _snack("✅ Transfert enregistré", ok: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = "❌ ${e.toString()}";
      });
      _snack("❌ ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k : ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v),
      ],
    );
  }

  Widget _ctiInputs(String grade) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _goodCartons[grade],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cartons',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _goodTrays[grade],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Alvéoles',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _goodIsolated[grade],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Isolés',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _brokenInputs() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _brokenCartonsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cartons',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _brokenTraysCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Alvéoles',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _brokenIsolatedCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Isolés',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _gradeCard(String grade) {
    final farmEggs = _farmGoodByGrade[grade] ?? 0;
    final cti = _ctiFromEggs(farmEggs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_gradeFr(grade), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              "Stock ferme dispo : ${cti['cartons']} carton(s) / ${cti['trays']} alvéole(s) / ${cti['isolated']} isolé(s) (≈ $farmEggs œufs)",
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            _ctiInputs(grade),
          ],
        ),
      ),
    );
  }

  Widget _brokenCard() {
    final cti = _ctiFromEggs(_farmBrokenTotal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Casses (total)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              "Stock ferme dispo : ${cti['cartons']} carton(s) / ${cti['trays']} alvéole(s) / ${cti['isolated']} isolé(s) (≈ $_farmBrokenTotal œufs)",
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            _brokenInputs(),
            const SizedBox(height: 8),
            Text(
              "NB: les casses ne sont pas ventilées par calibre (logique finale).",
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goodSumMap = _farmGoodByGrade.values.fold<int>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfert Ferme → Dépôt'),
        actions: [
          IconButton(
            tooltip: 'Actualiser stock (serveur)',
            onPressed: () async {
              await _loadFarmStock(server: true);
              _snack("Stock ferme actualisé ✅", ok: true);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Résumé stock ferme', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _kv('Bons (stockés)', '$_farmGoodTotal'),
                      _kv('Bons (recalcul map)', '$goodSumMap'),
                      _kv('Cassés', '$_farmBrokenTotal'),
                    ],
                  ),
                  if (_farmGoodTotal != goodSumMap) ...[
                    const SizedBox(height: 8),
                    Text(
                      "⚠️ Incohérence détectée: goodTotalEggs($_farmGoodTotal) ≠ somme eggsByGrade($goodSumMap).\n"
                          "L'écran se base sur eggsByGrade (plus fiable).",
                      style: const TextStyle(color: Colors.deepOrange, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Depot selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dépôt destination', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _farmRef.collection('depots').orderBy('name').snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) return Text("Erreur dépôts: ${snap.error}");
                      if (!snap.hasData) return const LinearProgressIndicator();

                      final docs = snap.data!.docs;
                      if (docs.isEmpty) return const Text("Aucun dépôt.");

                      return DropdownButtonFormField<String>(
                        value: _selectedDepotId,
                        items: docs.map((d) {
                          final name = (d.data()['name'] ?? '').toString().trim();
                          final label = name.isEmpty ? d.id : name;
                          return DropdownMenuItem(
                            value: d.id,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          final doc = docs.firstWhere((x) => x.id == v);
                          final name = (doc.data()['name'] ?? '').toString().trim();
                          setState(() {
                            _selectedDepotId = v;
                            _selectedDepotName = name.isEmpty ? v : name;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Choisir un dépôt',
                          border: OutlineInputBorder(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Grade cards (stock shown inside each grade card)
          for (final g in _grades) _gradeCard(g),

          // Broken (total)
          _brokenCard(),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _message!,
                style: TextStyle(
                  color: (_message!.startsWith('✅')) ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          FilledButton.icon(
            onPressed: _loading ? null : _saveTransfer,
            icon: _loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.swap_horiz),
            label: Text(_loading ? 'Enregistrement...' : 'Enregistrer le transfert'),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
