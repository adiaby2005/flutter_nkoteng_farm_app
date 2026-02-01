import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/building.dart';

class EggTransferToDepotScreen extends StatefulWidget {
  final String farmId;
  final Building building;

  const EggTransferToDepotScreen({
    super.key,
    required this.farmId,
    required this.building,
  });

  @override
  State<EggTransferToDepotScreen> createState() => _EggTransferToDepotScreenState();
}

class _EggTransferToDepotScreenState extends State<EggTransferToDepotScreen> {
  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  String? _message;
  DateTime _selectedDate = DateTime.now();

  // ✅ Dépôt destinataire via dropdown
  String? _selectedDepotId;
  String _selectedDepotName = "";

  // ✅ Stock bâtiment (bons par grade + casses)
  Map<String, int> _buildingGoodStockByGrade = {
    'SMALL': 0,
    'MEDIUM': 0,
    'LARGE': 0,
    'XL': 0,
  };
  int _buildingBrokenStockTotal = 0;

  // ✅ Sorties bons œufs (alvéoles + isolés)
  final Map<String, TextEditingController> _goodAlveolesCtrls = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };

  final Map<String, TextEditingController> _goodIsolatedCtrls = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };

  // ✅ Sorties casses (alvéoles + isolés) — pas par calibre (total)
  final TextEditingController _brokenAlveolesCtrl = TextEditingController(text: "0");
  final TextEditingController _brokenIsolatedCtrl = TextEditingController(text: "0");

  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in _goodAlveolesCtrls.values) c.dispose();
    for (final c in _goodIsolatedCtrls.values) c.dispose();
    _brokenAlveolesCtrl.dispose();
    _brokenIsolatedCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // On laisse le StreamBuilder alimenter le stock bâtiment en temps réel
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

  bool _validateIsolated0to29(int v) => v >= 0 && v <= 29;

  int _eggsForGrade({
    required Map<String, TextEditingController> alvCtrls,
    required Map<String, TextEditingController> isoCtrls,
    required String grade,
  }) {
    final alv = _parseInt(alvCtrls[grade]!);
    final iso = _parseInt(isoCtrls[grade]!);
    return (alv * 30) + iso;
  }

  Map<String, int> _goodOutByGrade() {
    return {
      'SMALL': _eggsForGrade(alvCtrls: _goodAlveolesCtrls, isoCtrls: _goodIsolatedCtrls, grade: 'SMALL'),
      'MEDIUM': _eggsForGrade(alvCtrls: _goodAlveolesCtrls, isoCtrls: _goodIsolatedCtrls, grade: 'MEDIUM'),
      'LARGE': _eggsForGrade(alvCtrls: _goodAlveolesCtrls, isoCtrls: _goodIsolatedCtrls, grade: 'LARGE'),
      'XL': _eggsForGrade(alvCtrls: _goodAlveolesCtrls, isoCtrls: _goodIsolatedCtrls, grade: 'XL'),
    };
  }

  int _brokenOutTotal() {
    final alv = _parseInt(_brokenAlveolesCtrl);
    final iso = _parseInt(_brokenIsolatedCtrl);
    return (alv * 30) + iso;
  }

  int _total(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

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

  Map<String, int> _readGoodByGrade(Map<String, dynamic> stockDoc) {
    // Priorité: goodByGrade, sinon eggsByGrade (compat)
    Map<String, dynamic> readMap(String key) {
      final raw = stockDoc[key];
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return <String, dynamic>{};
    }

    final m = readMap('goodByGrade');
    final fallback = readMap('eggsByGrade');
    int gi(Map<String, dynamic> map, String k) {
      final v = map[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    }

    int pick(String k) {
      final v = gi(m, k);
      if (v != 0) return v;
      return gi(fallback, k);
    }

    return {
      'SMALL': pick('SMALL'),
      'MEDIUM': pick('MEDIUM'),
      'LARGE': pick('LARGE'),
      'XL': pick('XL'),
    };
  }

  int _readBrokenTotal(Map<String, dynamic> stockDoc) {
    final v = stockDoc['brokenTotalEggs'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  void _validateUI() {
    if (_selectedDepotId == null || _selectedDepotId!.isEmpty) {
      throw Exception("Veuillez sélectionner le dépôt destinataire.");
    }

    // champs non négatifs + isolés 0..29
    for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      final alv = _parseInt(_goodAlveolesCtrls[g]!);
      final iso = _parseInt(_goodIsolatedCtrls[g]!);
      if (alv < 0) throw Exception("Bons œufs: alvéoles ($g) négatives interdites.");
      if (iso < 0) throw Exception("Bons œufs: isolés ($g) négatifs interdits.");
      if (!_validateIsolated0to29(iso)) {
        throw Exception("Bons œufs: isolés ($g) doit être entre 0 et 29.");
      }
    }

    final bAlv = _parseInt(_brokenAlveolesCtrl);
    final bIso = _parseInt(_brokenIsolatedCtrl);
    if (bAlv < 0 || bIso < 0) throw Exception("Casses: valeurs négatives interdites.");
    if (!_validateIsolated0to29(bIso)) throw Exception("Casses: isolés doit être entre 0 et 29.");

    final goodOut = _goodOutByGrade();
    final goodTotal = _total(goodOut);
    final brokenTotal = _brokenOutTotal();

    if (goodTotal == 0 && brokenTotal == 0) {
      throw Exception("Aucune sortie à enregistrer.");
    }

    // ✅ contrôle UI: pas dépasser stock
    for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      final need = goodOut[g] ?? 0;
      final have = _buildingGoodStockByGrade[g] ?? 0;
      if (need > have) {
        throw Exception("Stock bons œufs insuffisant (${_gradeFr(g)}). Stock=$have, sortie=$need.");
      }
    }
    if (brokenTotal > _buildingBrokenStockTotal) {
      throw Exception("Stock casses insuffisant. Stock=${_buildingBrokenStockTotal}, sortie=$brokenTotal.");
    }
  }

  Widget _stockPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _goodGradeRow({
    required String label,
    required String grade,
  }) {
    final stock = _buildingGoodStockByGrade[grade] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
            _stockPill("Stock: $stock"),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _goodAlveolesCtrls[grade],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Alvéoles (sortie)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_loading,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _goodIsolatedCtrls[grade],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Isolés (0..29)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_loading,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _brokenRow() {
    final stock = _buildingBrokenStockTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text("Casses", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            _stockPill("Stock: $stock"),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _brokenAlveolesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Alvéoles cassées (sortie)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_loading,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _brokenIsolatedCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Isolés (0..29)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_loading,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Future<void> _saveTransfer({
    required String depotId,
    required String depotName,
  }) async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      _validateUI();

      final farmRef = _db.collection('farms').doc(widget.farmId);
      final dateIso = _dateIso(_selectedDate);

      final goodOutByGrade = _goodOutByGrade();
      final goodOutTotal = _total(goodOutByGrade);

      final brokenOutTotal = _brokenOutTotal();
      final brokenAlv = _parseInt(_brokenAlveolesCtrl);
      final brokenIso = _parseInt(_brokenIsolatedCtrl);

      // Idempotency key stable
      final uniqueKey = [
        'EGG_TRANSFER',
        widget.farmId,
        dateIso,
        widget.building.id,
        'DEPOT',
        depotId,
        // bons
        goodOutByGrade['SMALL'].toString(),
        goodOutByGrade['MEDIUM'].toString(),
        goodOutByGrade['LARGE'].toString(),
        goodOutByGrade['XL'].toString(),
        // casses
        brokenOutTotal.toString(),
      ].join('|');

      final lockRef = farmRef.collection('idempotency').doc(uniqueKey);

      final fromStockRef = farmRef.collection('stocks_eggs').doc("BUILDING_${widget.building.id}");
      final toStockRef = farmRef.collection('stocks_eggs').doc("DEPOT_$depotId");

      final moveRef = farmRef.collection('egg_movements').doc();

      await _db.runTransaction((tx) async {
        // READS FIRST
        final lockSnap = await tx.get(lockRef);
        if (lockSnap.exists) return;

        final fromSnap = await tx.get(fromStockRef);
        if (!fromSnap.exists) {
          throw Exception("Stock bâtiment introuvable (BUILDING_${widget.building.id}).");
        }

        final fromData = fromSnap.data() ?? <String, dynamic>{};
        final fromGoodByGrade = _readGoodByGrade(fromData);
        final fromBrokenTotal = _readBrokenTotal(fromData);

        // sécurité: stock suffisant bons par grade
        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
          final need = goodOutByGrade[g] ?? 0;
          final have = fromGoodByGrade[g] ?? 0;
          if (need > have) {
            throw Exception("Stock insuffisant (${_gradeFr(g)}). Stock=$have, sortie=$need.");
          }
        }

        // sécurité: stock suffisant casses
        if (brokenOutTotal > fromBrokenTotal) {
          throw Exception("Stock casses insuffisant. Stock=$fromBrokenTotal, sortie=$brokenOutTotal.");
        }

        final toSnap = await tx.get(toStockRef);
        final toData = toSnap.data() ?? <String, dynamic>{};

        final toGoodByGrade = _readGoodByGrade(toData);
        final toBrokenTotal = _readBrokenTotal(toData);

        // Calcul nouveaux stocks
        final newFromGoodByGrade = <String, int>{};
        final newToGoodByGrade = <String, int>{};

        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
          newFromGoodByGrade[g] = (fromGoodByGrade[g] ?? 0) - (goodOutByGrade[g] ?? 0);
          newToGoodByGrade[g] = (toGoodByGrade[g] ?? 0) + (goodOutByGrade[g] ?? 0);
        }

        final fromGoodTotal = (fromData['goodTotalEggs'] is int)
            ? fromData['goodTotalEggs'] as int
            : _total(fromGoodByGrade);
        final toGoodTotal = (toData['goodTotalEggs'] is int) ? toData['goodTotalEggs'] as int : _total(toGoodByGrade);

        final newFromGoodTotal = fromGoodTotal - goodOutTotal;
        final newToGoodTotal = toGoodTotal + goodOutTotal;

        final newFromBrokenTotal = fromBrokenTotal - brokenOutTotal;
        final newToBrokenTotal = toBrokenTotal + brokenOutTotal;

        if (newFromGoodTotal < 0) throw Exception("Incohérence: stock bons œufs bâtiment négatif.");
        if (newFromBrokenTotal < 0) throw Exception("Incohérence: stock casses bâtiment négatif.");

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
          'from': {
            'kind': 'BUILDING',
            'id': widget.building.id,
            'name': widget.building.name,
          },
          'to': {
            'kind': 'DEPOT',
            'id': depotId,
            'name': depotName,
          },
          'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        });

        // BUILDING stock update
        tx.set(fromStockRef, {
          'kind': 'BUILDING',
          'locationType': 'BUILDING',
          'locationId': widget.building.id,
          'refId': widget.building.id,
          // bons
          'eggsByGrade': newFromGoodByGrade, // compat
          'goodByGrade': newFromGoodByGrade,
          'goodTotalEggs': newFromGoodTotal,
          // casses
          'brokenTotalEggs': newFromBrokenTotal,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // DEPOT stock update
        tx.set(toStockRef, {
          'kind': 'DEPOT',
          'locationType': 'DEPOT',
          'locationId': depotId,
          'refId': depotId,
          // bons
          'eggsByGrade': newToGoodByGrade,
          'goodByGrade': newToGoodByGrade,
          'goodTotalEggs': newToGoodTotal,
          // casses
          'brokenTotalEggs': newToBrokenTotal,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(lockRef, {
          'kind': 'EGG_TRANSFER',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      // reset UI (sans reset dépôt)
      for (final c in _goodAlveolesCtrls.values) c.text = "0";
      for (final c in _goodIsolatedCtrls.values) c.text = "0";
      _brokenAlveolesCtrl.text = "0";
      _brokenIsolatedCtrl.text = "0";
      _noteCtrl.clear();

      setState(() => _message = "Transfert OK (bons: +$goodOutTotal, casses: +$brokenOutTotal) vers $depotName");
    } catch (e) {
      setState(() => _message = "Erreur : ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = _message;

    final depotsQuery = _db
        .collection('farms')
        .doc(widget.farmId)
        .collection('depots')
        .where('active', isEqualTo: true)
        .orderBy('name');

    final buildingStockRef = _db
        .collection('farms')
        .doc(widget.farmId)
        .collection('stocks_eggs')
        .doc("BUILDING_${widget.building.id}");

    return Scaffold(
      appBar: AppBar(
        title: Text("Transfert dépôt – ${widget.building.name}"),
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
            Text(
              "Bâtiment : ${widget.building.name}",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),

            // ✅ Lecture stock bâtiment en temps réel pour afficher les stocks et valider UI
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: buildingStockRef.snapshots(),
              builder: (context, stockSnap) {
                if (stockSnap.hasError) {
                  return Text(
                    "Erreur chargement stock bâtiment: ${stockSnap.error}",
                    style: const TextStyle(color: Colors.red),
                  );
                }
                if (!stockSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  );
                }

                final stock = stockSnap.data!.data() ?? <String, dynamic>{};
                final good = _readGoodByGrade(stock);
                final brokenTotal = _readBrokenTotal(stock);

                // ✅ mise à jour cache UI (sans rebuild en boucle)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final changed =
                      good['SMALL'] != _buildingGoodStockByGrade['SMALL'] ||
                          good['MEDIUM'] != _buildingGoodStockByGrade['MEDIUM'] ||
                          good['LARGE'] != _buildingGoodStockByGrade['LARGE'] ||
                          good['XL'] != _buildingGoodStockByGrade['XL'] ||
                          brokenTotal != _buildingBrokenStockTotal;

                  if (changed) {
                    setState(() {
                      _buildingGoodStockByGrade = good;
                      _buildingBrokenStockTotal = brokenTotal;
                    });
                  }
                });

                return const SizedBox.shrink();
              },
            ),

            // ✅ Dropdown dépôts
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: depotsQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text(
                    "Erreur chargement dépôts : ${snap.error}",
                    style: const TextStyle(color: Colors.red),
                  );
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
                    "Aucun dépôt actif. Créez un dépôt dans le menu Dépôts.",
                    style: TextStyle(color: Colors.red),
                  );
                }

                // si pas encore choisi, prendre le 1er dépôt
                if (_selectedDepotId == null || !docs.any((d) => d.id == _selectedDepotId)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _selectedDepotId = docs.first.id;
                        _selectedDepotName = (docs.first.data()['name'] ?? docs.first.id).toString();
                      });
                    }
                  });
                } else {
                  // synchroniser le nom
                  final current = docs.where((d) => d.id == _selectedDepotId).toList();
                  if (current.isNotEmpty) {
                    final name = (current.first.data()['name'] ?? current.first.id).toString();
                    if (name != _selectedDepotName) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _selectedDepotName = name);
                      });
                    }
                  }
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
                  items: docs.map((d) {
                    final data = d.data();
                    final label = labelFor(d.id, data);
                    return DropdownMenuItem<String>(
                      value: d.id,
                      child: Text(label),
                    );
                  }).toList(),
                  onChanged: _loading
                      ? null
                      : (v) {
                    if (v == null) return;
                    final doc = docs.firstWhere((d) => d.id == v);
                    final name = (doc.data()['name'] ?? doc.id).toString();
                    setState(() {
                      _selectedDepotId = v;
                      _selectedDepotName = name;
                    });
                  },
                );
              },
            ),

            const Divider(height: 28),

            Text("Sorties vers dépôt (bons œufs)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),

            _goodGradeRow(label: "Petit calibre", grade: 'SMALL'),
            _goodGradeRow(label: "Moyen calibre", grade: 'MEDIUM'),
            _goodGradeRow(label: "Gros calibre", grade: 'LARGE'),
            _goodGradeRow(label: "Très gros calibre", grade: 'XL'),

            const Divider(height: 28),

            Text("Sorties vers dépôt (casses)", style: Theme.of(context).textTheme.titleLarge),
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
              onPressed: _loading
                  ? null
                  : () => _saveTransfer(
                depotId: _selectedDepotId ?? "",
                depotName: _selectedDepotName.isEmpty ? (_selectedDepotId ?? "") : _selectedDepotName,
              ),
              icon: const Icon(Icons.local_shipping),
              label: Text(_loading ? "Enregistrement..." : "Valider le transfert"),
            ),

            const SizedBox(height: 14),
            if (msg != null)
              Text(
                msg,
                style: TextStyle(
                  color: msg.startsWith("Erreur") ? Colors.red : Colors.green,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
