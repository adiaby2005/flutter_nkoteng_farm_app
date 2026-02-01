import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FarmEggTransferToDepotScreen extends StatefulWidget {
  final String farmId;

  const FarmEggTransferToDepotScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<FarmEggTransferToDepotScreen> createState() => _FarmEggTransferToDepotScreenState();
}

class _FarmEggTransferToDepotScreenState extends State<FarmEggTransferToDepotScreen> {
  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  String? _message;
  DateTime _selectedDate = DateTime.now();

  String? _selectedDepotId;
  String _selectedDepotName = "";

  Map<String, int> _farmGoodStockByGrade = {'SMALL': 0, 'MEDIUM': 0, 'LARGE': 0, 'XL': 0};
  int _farmBrokenStockTotal = 0;

  final Map<String, TextEditingController> _goodAlv = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };
  final Map<String, TextEditingController> _goodIso = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };

  final TextEditingController _brokenAlvCtrl = TextEditingController(text: "0");
  final TextEditingController _brokenIsoCtrl = TextEditingController(text: "0");
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in _goodAlv.values) c.dispose();
    for (final c in _goodIso.values) c.dispose();
    _brokenAlvCtrl.dispose();
    _brokenIsoCtrl.dispose();
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
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  int _parseInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  bool _isolatedOk(int v) => v >= 0 && v <= 29;

  int _eggsForGrade(String g) => _parseInt(_goodAlv[g]!) * 30 + _parseInt(_goodIso[g]!);

  Map<String, int> _goodOutByGrade() => {
    'SMALL': _eggsForGrade('SMALL'),
    'MEDIUM': _eggsForGrade('MEDIUM'),
    'LARGE': _eggsForGrade('LARGE'),
    'XL': _eggsForGrade('XL'),
  };

  int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

  int _brokenOutTotal() => _parseInt(_brokenAlvCtrl) * 30 + _parseInt(_brokenIsoCtrl);

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

  int _getInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  Map<String, int> _readGrades(Map<String, dynamic> doc, String key) {
    final raw = doc[key];
    final m = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return {
      'SMALL': _getInt(m['SMALL']),
      'MEDIUM': _getInt(m['MEDIUM']),
      'LARGE': _getInt(m['LARGE']),
      'XL': _getInt(m['XL']),
    };
  }

  void _validateUI() {
    if (_selectedDepotId == null || _selectedDepotId!.isEmpty) {
      throw Exception("Veuillez sélectionner le dépôt destinataire.");
    }

    for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      final alv = _parseInt(_goodAlv[g]!);
      final iso = _parseInt(_goodIso[g]!);
      if (alv < 0) throw Exception("Bons œufs: alvéoles ($g) négatives interdites.");
      if (iso < 0) throw Exception("Bons œufs: isolés ($g) négatifs interdits.");
      if (!_isolatedOk(iso)) throw Exception("Bons œufs: isolés ($g) doit être entre 0 et 29.");
    }

    final bAlv = _parseInt(_brokenAlvCtrl);
    final bIso = _parseInt(_brokenIsoCtrl);
    if (bAlv < 0 || bIso < 0) throw Exception("Casses: valeurs négatives interdites.");
    if (!_isolatedOk(bIso)) throw Exception("Casses: isolés doit être entre 0 et 29.");

    final goodOut = _goodOutByGrade();
    final goodTotal = _sum(goodOut);
    final brokenTotal = _brokenOutTotal();
    if (goodTotal == 0 && brokenTotal == 0) throw Exception("Aucune sortie à enregistrer.");

    // contrôle UI stock
    for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      final need = goodOut[g] ?? 0;
      final have = _farmGoodStockByGrade[g] ?? 0;
      if (need > have) {
        throw Exception("Stock ferme insuffisant (${_gradeFr(g)}). Stock=$have, sortie=$need.");
      }
    }
    if (brokenTotal > _farmBrokenStockTotal) {
      throw Exception("Stock ferme (casses) insuffisant. Stock=${_farmBrokenStockTotal}, sortie=$brokenTotal.");
    }
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _goodRow(String label, String g) {
    final stock = _farmGoodStockByGrade[g] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
            _pill("Stock: $stock"),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _goodAlv[g],
                keyboardType: TextInputType.number,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: "Alvéoles (sortie)",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _goodIso[g],
                keyboardType: TextInputType.number,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: "Isolés (0..29)",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _brokenRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text("Casses", style: TextStyle(fontWeight: FontWeight.bold))),
            _pill("Stock: $_farmBrokenStockTotal"),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _brokenAlvCtrl,
                keyboardType: TextInputType.number,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: "Alvéoles cassées (sortie)",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _brokenIsoCtrl,
                keyboardType: TextInputType.number,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: "Isolés (0..29)",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      _validateUI();

      final farmRef = _db.collection('farms').doc(widget.farmId);
      final dateIso = _dateIso(_selectedDate);

      final depotId = _selectedDepotId!;
      final depotName = _selectedDepotName.isEmpty ? depotId : _selectedDepotName;

      final goodOutByGrade = _goodOutByGrade();
      final goodOutTotal = _sum(goodOutByGrade);

      final brokenAlv = _parseInt(_brokenAlvCtrl);
      final brokenIso = _parseInt(_brokenIsoCtrl);
      final brokenOutTotal = _brokenOutTotal();

      final uniqueKey = [
        'EGG_TRANSFER_FARM',
        widget.farmId,
        dateIso,
        'FARM_GLOBAL',
        'DEPOT',
        depotId,
        goodOutByGrade['SMALL'].toString(),
        goodOutByGrade['MEDIUM'].toString(),
        goodOutByGrade['LARGE'].toString(),
        goodOutByGrade['XL'].toString(),
        brokenOutTotal.toString(),
      ].join('|');

      final lockRef = farmRef.collection('idempotency').doc(uniqueKey);
      final fromRef = farmRef.collection('stocks_eggs').doc('FARM_GLOBAL');
      final toRef = farmRef.collection('stocks_eggs').doc('DEPOT_$depotId');
      final moveRef = farmRef.collection('egg_movements').doc();

      await _db.runTransaction((tx) async {
        // READS FIRST
        final lockSnap = await tx.get(lockRef);
        if (lockSnap.exists) return;

        final fromSnap = await tx.get(fromRef);
        if (!fromSnap.exists) {
          throw Exception("Stock global introuvable (stocks_eggs/FARM_GLOBAL). "
              "Va dans Stock global et appuie sur ↻ pour initialiser.");
        }

        final fromData = fromSnap.data() ?? <String, dynamic>{};
        final fromGood = _readGrades(fromData, 'goodByGrade');
        final fromBroken = _getInt(fromData['brokenTotalEggs']);
        final fromGoodTotal = _getInt(fromData['goodTotalEggs']);

        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
          final need = goodOutByGrade[g] ?? 0;
          final have = fromGood[g] ?? 0;
          if (need > have) {
            throw Exception("Stock global insuffisant (${_gradeFr(g)}). Stock=$have, sortie=$need.");
          }
        }
        if (brokenOutTotal > fromBroken) {
          throw Exception("Stock global (casses) insuffisant. Stock=$fromBroken, sortie=$brokenOutTotal.");
        }

        final toSnap = await tx.get(toRef);
        final toData = toSnap.data() ?? <String, dynamic>{};
        final toGood = _readGrades(toData, 'goodByGrade');
        final toBroken = _getInt(toData['brokenTotalEggs']);
        final toGoodTotal = _getInt(toData['goodTotalEggs']);

        final newFromGood = <String, int>{};
        final newToGood = <String, int>{};
        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
          newFromGood[g] = (fromGood[g] ?? 0) - (goodOutByGrade[g] ?? 0);
          newToGood[g] = (toGood[g] ?? 0) + (goodOutByGrade[g] ?? 0);
        }

        final newFromGoodTotal = fromGoodTotal - goodOutTotal;
        final newToGoodTotal = toGoodTotal + goodOutTotal;

        final newFromBroken = fromBroken - brokenOutTotal;
        final newToBroken = toBroken + brokenOutTotal;

        if (newFromGoodTotal < 0 || newFromBroken < 0) {
          throw Exception("Incohérence: stock global deviendrait négatif.");
        }

        // WRITES
        tx.set(moveRef, {
          'date': dateIso,
          'type': 'TRANSFER',
          'goodOutByGrade': goodOutByGrade,
          'goodOutTotal': goodOutTotal,
          'brokenOut': {
            'brokenAlveoles': brokenAlv,
            'brokenIsolated': brokenIso,
            'totalBrokenEggs': brokenOutTotal,
          },
          'from': {'kind': 'FARM', 'id': 'FARM_GLOBAL', 'name': 'Stock global'},
          'to': {'kind': 'DEPOT', 'id': depotId, 'name': depotName},
          'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        });

        tx.set(fromRef, {
          'kind': 'FARM',
          'locationType': 'FARM',
          'locationId': 'FARM',
          'refId': 'FARM',
          'goodByGrade': newFromGood,
          'eggsByGrade': newFromGood,
          'goodTotalEggs': newFromGoodTotal,
          'brokenTotalEggs': newFromBroken,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(toRef, {
          'kind': 'DEPOT',
          'locationType': 'DEPOT',
          'locationId': depotId,
          'refId': depotId,
          'goodByGrade': newToGood,
          'eggsByGrade': newToGood,
          'goodTotalEggs': newToGoodTotal,
          'brokenTotalEggs': newToBroken,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(lockRef, {'kind': 'EGG_TRANSFER_FARM', 'createdAt': FieldValue.serverTimestamp()});
      });

      // reset
      for (final c in _goodAlv.values) c.text = "0";
      for (final c in _goodIso.values) c.text = "0";
      _brokenAlvCtrl.text = "0";
      _brokenIsoCtrl.text = "0";
      _noteCtrl.clear();

      setState(() => _message = "Transfert OK vers $depotName (bons: +$goodOutTotal, casses: +$brokenOutTotal)");
    } catch (e) {
      setState(() => _message = "Erreur : ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmRef = _db.collection('farms').doc(widget.farmId);
    final farmStockRef = farmRef.collection('stocks_eggs').doc('FARM_GLOBAL');

    final depotsQuery = farmRef
        .collection('depots')
        .where('active', isEqualTo: true)
        .orderBy('name');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Transfert œufs → dépôt (stock global)"),
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
            // Stock global live (pour affichage + cache UI)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: farmStockRef.snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  );
                }

                if (!snap.data!.exists) {
                  return const Text(
                    "Stock global (FARM_GLOBAL) introuvable.\n"
                        "Va dans “Stock global (ferme)” et appuie sur ↻ pour initialiser.",
                    style: TextStyle(color: Colors.red),
                  );
                }

                final data = snap.data!.data() ?? <String, dynamic>{};
                final good = _readGrades(data, 'goodByGrade');
                final broken = _getInt(data['brokenTotalEggs']);

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final changed =
                      good['SMALL'] != _farmGoodStockByGrade['SMALL'] ||
                          good['MEDIUM'] != _farmGoodStockByGrade['MEDIUM'] ||
                          good['LARGE'] != _farmGoodStockByGrade['LARGE'] ||
                          good['XL'] != _farmGoodStockByGrade['XL'] ||
                          broken != _farmBrokenStockTotal;
                  if (changed) {
                    setState(() {
                      _farmGoodStockByGrade = good;
                      _farmBrokenStockTotal = broken;
                    });
                  }
                });

                return const SizedBox.shrink();
              },
            ),

            // Dropdown dépôt
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: depotsQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text("Erreur chargement dépôts : ${snap.error}",
                      style: const TextStyle(color: Colors.red));
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  );
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Text(
                    "Aucun dépôt actif. Crée un dépôt dans le menu Dépôts.",
                    style: TextStyle(color: Colors.red),
                  );
                }

                if (_selectedDepotId == null || !docs.any((d) => d.id == _selectedDepotId)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _selectedDepotId = docs.first.id;
                      _selectedDepotName = (docs.first.data()['name'] ?? docs.first.id).toString();
                    });
                  });
                }

                String labelFor(String depotId, Map<String, dynamic> data) {
                  final name = (data['name'] ?? depotId).toString().trim();
                  final location = (data['location'] ?? '').toString().trim();
                  return location.isEmpty ? name : "$name — $location";
                }

                return DropdownButtonFormField<String>(
                  value: _selectedDepotId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Dépôt destinataire",
                    border: OutlineInputBorder(),
                  ),
                  items: docs
                      .map((d) => DropdownMenuItem<String>(
                    value: d.id,
                    child: Text(labelFor(d.id, d.data())),
                  ))
                      .toList(),
                  onChanged: _loading
                      ? null
                      : (v) {
                    if (v == null) return;
                    final doc = docs.firstWhere((d) => d.id == v);
                    setState(() {
                      _selectedDepotId = v;
                      _selectedDepotName = (doc.data()['name'] ?? doc.id).toString();
                    });
                  },
                );
              },
            ),

            const Divider(height: 28),

            Text("Sorties (bons œufs)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            _goodRow("Petit calibre", 'SMALL'),
            _goodRow("Moyen calibre", 'MEDIUM'),
            _goodRow("Gros calibre", 'LARGE'),
            _goodRow("Très gros calibre", 'XL'),

            const Divider(height: 28),

            Text("Sorties (casses)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            _brokenRow(),

            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: "Note (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 18),

            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.local_shipping),
              label: Text(_loading ? "Enregistrement..." : "Valider le transfert"),
            ),

            const SizedBox(height: 14),
            if (_message != null)
              Text(
                _message!,
                style: TextStyle(
                  color: _message!.startsWith("Erreur") ? Colors.red : Colors.green,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
