import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/building.dart';

class DailyEntryEditScreen extends StatefulWidget {
  final String farmId;
  final Building building;
  final String dailyEntryDocId; // ex: {buildingId}_{dateIso}
  final String dateIso;

  const DailyEntryEditScreen({
    super.key,
    required this.farmId,
    required this.building,
    required this.dailyEntryDocId,
    required this.dateIso,
  });

  @override
  State<DailyEntryEditScreen> createState() => _DailyEntryEditScreenState();
}

class _DailyEntryEditScreenState extends State<DailyEntryEditScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _saving = false;
  String? _message;

  // --- Production (bons œufs) : alvéoles + isolés
  final Map<String, TextEditingController> _alvCtrls = {
    'SMALL': TextEditingController(),
    'MEDIUM': TextEditingController(),
    'LARGE': TextEditingController(),
    'XL': TextEditingController(),
  };
  final Map<String, TextEditingController> _isoCtrls = {
    'SMALL': TextEditingController(),
    'MEDIUM': TextEditingController(),
    'LARGE': TextEditingController(),
    'XL': TextEditingController(),
  };

  // --- Casses : alvéoles + isolés
  final _brokenAlvCtrl = TextEditingController(text: "0");
  final _brokenIsoCtrl = TextEditingController(text: "0");
  final _brokenNoteCtrl = TextEditingController();

  // --- Eau
  String _waterMode = 'MANUAL'; // MANUAL | ESTIMATE
  final _waterLitersCtrl = TextEditingController(text: "0");
  final _waterNoteCtrl = TextEditingController();

  // --- Mortalité
  final _mortQtyCtrl = TextEditingController(text: "0");
  final _mortCauseCtrl = TextEditingController();
  final _mortNoteCtrl = TextEditingController();

  // --- Véto (optionnel)
  bool _noVet = true;
  String? _vetItemId;
  final _vetQtyCtrl = TextEditingController(text: "0");
  final _vetUnitCtrl = TextEditingController(text: "unité");
  final _vetNoteCtrl = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    for (final c in _alvCtrls.values) {
      c.dispose();
    }
    for (final c in _isoCtrls.values) {
      c.dispose();
    }
    _brokenAlvCtrl.dispose();
    _brokenIsoCtrl.dispose();
    _brokenNoteCtrl.dispose();

    _waterLitersCtrl.dispose();
    _waterNoteCtrl.dispose();

    _mortQtyCtrl.dispose();
    _mortCauseCtrl.dispose();
    _mortNoteCtrl.dispose();

    _vetQtyCtrl.dispose();
    _vetUnitCtrl.dispose();
    _vetNoteCtrl.dispose();
    super.dispose();
  }

  int _parseInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  bool _validateIsolated0to29(int v) => v >= 0 && v <= 29;

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

  // Convertit des oeufs (ex: 353) en (alvéoles=11, isolés=23)
  void _setEggsToCtrls(String grade, int eggs) {
    final alv = eggs ~/ 30;
    final iso = eggs % 30;
    _alvCtrls[grade]!.text = alv.toString();
    _isoCtrls[grade]!.text = iso.toString();
  }

  int _eggsForGrade(String grade) {
    final alv = _parseInt(_alvCtrls[grade]!);
    final iso = _parseInt(_isoCtrls[grade]!);
    return (alv * 30) + iso;
  }

  Map<String, int> _newEggsByGrade() {
    return {
      'SMALL': _eggsForGrade('SMALL'),
      'MEDIUM': _eggsForGrade('MEDIUM'),
      'LARGE': _eggsForGrade('LARGE'),
      'XL': _eggsForGrade('XL'),
    };
  }

  int _sumEggs(Map<String, int> eggsByGrade) {
    int t = 0;
    for (final v in eggsByGrade.values) {
      t += v;
    }
    return t;
  }

  void _initFromDoc(Map<String, dynamic> entry) {
    if (_initialized) return;

    final prod = _getMap(entry, 'production');
    final broken = _getMap(entry, 'broken');
    final water = _getMap(entry, 'water');
    final mort = _getMap(entry, 'mortality');
    final vet = _getMap(entry, 'vet');

    final eggsByGrade = _getMap(prod, 'eggsByGrade');
    _setEggsToCtrls('SMALL', (eggsByGrade['SMALL'] ?? 0) as int);
    _setEggsToCtrls('MEDIUM', (eggsByGrade['MEDIUM'] ?? 0) as int);
    _setEggsToCtrls('LARGE', (eggsByGrade['LARGE'] ?? 0) as int);
    _setEggsToCtrls('XL', (eggsByGrade['XL'] ?? 0) as int);

    _brokenAlvCtrl.text = _getInt(broken, 'brokenAlveoles', 0).toString();
    _brokenIsoCtrl.text = _getInt(broken, 'brokenIsolated', 0).toString();
    _brokenNoteCtrl.text = _getStr(broken, 'note', "");

    _waterMode = _getStr(water, 'mode', 'MANUAL');
    _waterLitersCtrl.text = _getInt(water, 'liters', 0).toString();
    _waterNoteCtrl.text = _getStr(water, 'note', "");

    _mortQtyCtrl.text = _getInt(mort, 'qty', 0).toString();
    _mortCauseCtrl.text = _getStr(mort, 'cause', "");
    _mortNoteCtrl.text = _getStr(mort, 'note', "");

    if (vet.isEmpty || vet['none'] == true) {
      _noVet = true;
      _vetItemId = null;
      _vetQtyCtrl.text = "0";
      _vetUnitCtrl.text = "unité";
      _vetNoteCtrl.text = "";
    } else {
      _noVet = false;
      _vetItemId = _getStr(vet, 'itemId', "");
      _vetQtyCtrl.text = _getInt(vet, 'qtyUsed', 0).toString();
      _vetUnitCtrl.text = _getStr(vet, 'unitLabel', "unité");
      _vetNoteCtrl.text = _getStr(vet, 'note', "");
    }

    _initialized = true;
  }

  void _validateInputs() {
    // isolés 0..29
    for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      final iso = _parseInt(_isoCtrls[g]!);
      if (!_validateIsolated0to29(iso)) {
        throw Exception("Œufs isolés (${_gradeFr(g)}) doit être entre 0 et 29.");
      }
      final alv = _parseInt(_alvCtrls[g]!);
      if (alv < 0) throw Exception("Alvéoles (${_gradeFr(g)}) négatives interdites.");
    }

    final bAlv = _parseInt(_brokenAlvCtrl);
    final bIso = _parseInt(_brokenIsoCtrl);
    if (bAlv < 0 || bIso < 0) throw Exception("Casses : valeurs négatives interdites.");
    if (!_validateIsolated0to29(bIso)) {
      throw Exception("Casses : œufs isolés doit être entre 0 et 29.");
    }

    final waterL = _parseInt(_waterLitersCtrl);
    if (waterL < 0) throw Exception("Eau : litres négatifs interdits.");

    final mortQty = _parseInt(_mortQtyCtrl);
    if (mortQty < 0) throw Exception("Mortalité : quantité négative interdite.");

    if (!_noVet) {
      final qty = _parseInt(_vetQtyCtrl);
      if (qty < 0) throw Exception("Véto : quantité négative interdite.");
      if ((_vetItemId ?? '').trim().isEmpty && qty > 0) {
        throw Exception("Véto : produit obligatoire si quantité > 0.");
      }
    }
  }

  String _gradeFr(String g) {
    switch (g) {
      case 'SMALL':
        return "Petit calibre";
      case 'MEDIUM':
        return "Moyen calibre";
      case 'LARGE':
        return "Gros calibre";
      case 'XL':
        return "Très gros calibre";
      default:
        return g;
    }
  }

  Future<void> _saveCorrection(DocumentSnapshot<Map<String, dynamic>> entrySnap) async {
    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      _validateInputs();

      final entryRef = _db
          .collection('farms')
          .doc(widget.farmId)
          .collection('daily_entries')
          .doc(widget.dailyEntryDocId);

      final stockRef = _db
          .collection('farms')
          .doc(widget.farmId)
          .collection('stocks_eggs')
          .doc("BUILDING_${widget.building.id}");

      final adjRef = _db
          .collection('farms')
          .doc(widget.farmId)
          .collection('daily_entry_adjustments')
          .doc(); // auto id

      final user = _auth.currentUser;

      // Nouvelle saisie
      final newEggsByGrade = _newEggsByGrade();
      final newGoodTotal = _sumEggs(newEggsByGrade);

      final newBrokenAlv = _parseInt(_brokenAlvCtrl);
      final newBrokenIso = _parseInt(_brokenIsoCtrl);
      final newBrokenTotal = (newBrokenAlv * 30) + newBrokenIso;

      final newWater = {
        'mode': _waterMode,
        'liters': _parseInt(_waterLitersCtrl),
        'note': _waterNoteCtrl.text.trim().isEmpty ? null : _waterNoteCtrl.text.trim(),
        'savedAt': FieldValue.serverTimestamp(),
      };

      final newMortality = {
        'qty': _parseInt(_mortQtyCtrl),
        'cause': _mortCauseCtrl.text.trim().isEmpty ? null : _mortCauseCtrl.text.trim(),
        'note': _mortNoteCtrl.text.trim().isEmpty ? null : _mortNoteCtrl.text.trim(),
        'savedAt': FieldValue.serverTimestamp(),
      };

      final newVet = _noVet
          ? {'none': true, 'savedAt': FieldValue.serverTimestamp()}
          : {
        'none': false,
        'itemId': (_vetItemId ?? '').trim().isEmpty ? null : (_vetItemId ?? '').trim(),
        'qtyUsed': _parseInt(_vetQtyCtrl),
        'unitLabel': _vetUnitCtrl.text.trim().isEmpty ? 'unité' : _vetUnitCtrl.text.trim(),
        'note': _vetNoteCtrl.text.trim().isEmpty ? null : _vetNoteCtrl.text.trim(),
        'savedAt': FieldValue.serverTimestamp(),
      };

      await _db.runTransaction((tx) async {
        // READS FIRST
        final freshEntrySnap = await tx.get(entryRef);
        if (!freshEntrySnap.exists) {
          throw Exception("Le rapport agrégé n’existe pas (daily_entries).");
        }
        final freshStockSnap = await tx.get(stockRef);

        final before = freshEntrySnap.data() ?? <String, dynamic>{};
        final beforeProd = _getMap(before, 'production');
        final beforeBroken = _getMap(before, 'broken');

        final beforeEggsMapRaw = _getMap(beforeProd, 'eggsByGrade');
        final beforeEggsByGrade = <String, int>{
          'SMALL': _getInt(beforeEggsMapRaw, 'SMALL', 0),
          'MEDIUM': _getInt(beforeEggsMapRaw, 'MEDIUM', 0),
          'LARGE': _getInt(beforeEggsMapRaw, 'LARGE', 0),
          'XL': _getInt(beforeEggsMapRaw, 'XL', 0),
        };
        final beforeGoodTotal = _getInt(beforeProd, 'totalEggs', _sumEggs(beforeEggsByGrade));

        final beforeBrokenTotal = _getInt(beforeBroken, 'totalBrokenEggs', 0);

        // DELTAS
        final deltaGoodTotal = newGoodTotal - beforeGoodTotal;
        final deltaBrokenTotal = newBrokenTotal - beforeBrokenTotal;

        // Stock snapshot
        final stock = freshStockSnap.data() ?? <String, dynamic>{};
        final stockEggsByGradeRaw = (stock['eggsByGrade'] is Map)
            ? Map<String, dynamic>.from(stock['eggsByGrade'] as Map)
            : <String, dynamic>{};

        final currentStockByGrade = <String, int>{
          'SMALL': _getInt(stockEggsByGradeRaw, 'SMALL', 0),
          'MEDIUM': _getInt(stockEggsByGradeRaw, 'MEDIUM', 0),
          'LARGE': _getInt(stockEggsByGradeRaw, 'LARGE', 0),
          'XL': _getInt(stockEggsByGradeRaw, 'XL', 0),
        };

        final currentGoodTotal = (stock['goodTotalEggs'] is int)
            ? stock['goodTotalEggs'] as int
            : _sumEggs(currentStockByGrade);

        final currentBrokenTotal = (stock['brokenTotalEggs'] is int)
            ? stock['brokenTotalEggs'] as int
            : 0;

        // Nouvelles valeurs de stock (par grade via delta grade)
        final newStockByGrade = <String, int>{};
        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
          final deltaG = (newEggsByGrade[g] ?? 0) - (beforeEggsByGrade[g] ?? 0);
          newStockByGrade[g] = (currentStockByGrade[g] ?? 0) + deltaG;
          if (newStockByGrade[g]! < 0) {
            throw Exception("Correction invalide: stock négatif sur $g.");
          }
        }

        final newStockGoodTotal = currentGoodTotal + deltaGoodTotal;
        if (newStockGoodTotal < 0) {
          throw Exception("Correction invalide: stock bons œufs négatif.");
        }

        final newStockBrokenTotal = currentBrokenTotal + deltaBrokenTotal;
        if (newStockBrokenTotal < 0) {
          throw Exception("Correction invalide: stock casses négatif.");
        }

        // WRITES
        final afterProd = {
          'eggsByGrade': newEggsByGrade,
          'totalEggs': newGoodTotal,
          // on garde lotId existant si présent
          'lotId': beforeProd['lotId'],
          'savedAt': FieldValue.serverTimestamp(),
        };

        final afterBroken = {
          'brokenAlveoles': newBrokenAlv,
          'brokenIsolated': newBrokenIso,
          'totalBrokenEggs': newBrokenTotal,
          'note': _brokenNoteCtrl.text.trim().isEmpty ? null : _brokenNoteCtrl.text.trim(),
          'savedAt': FieldValue.serverTimestamp(),
        };

        final updateEntry = <String, dynamic>{
          'date': widget.dateIso,
          'buildingId': widget.building.id,
          'production': afterProd,
          'broken': afterBroken,
          'water': newWater,
          'mortality': newMortality,
          'vet': newVet,
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'adjustment',
        };

        tx.set(entryRef, updateEntry, SetOptions(merge: true));

        // Mise à jour stock agrégé eggs
        tx.set(stockRef, {
          'kind': 'BUILDING',
          'locationType': 'BUILDING',
          'locationId': widget.building.id,
          'refId': widget.building.id,
          'eggsByGrade': newStockByGrade,     // ✅ ton champ principal
          'goodByGrade': newStockByGrade,     // ✅ on le synchronise aussi
          'goodTotalEggs': newStockGoodTotal, // ✅
          'brokenTotalEggs': newStockBrokenTotal,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Audit / traçabilité
        tx.set(adjRef, {
          'date': widget.dateIso,
          'buildingId': widget.building.id,
          'dailyEntryId': widget.dailyEntryDocId,
          'createdAt': FieldValue.serverTimestamp(),
          'user': {
            'uid': user?.uid,
            'email': user?.email,
          },
          'before': {
            'production': beforeProd,
            'broken': beforeBroken,
            'water': _getMap(before, 'water'),
            'mortality': _getMap(before, 'mortality'),
            'vet': _getMap(before, 'vet'),
          },
          'after': {
            'production': afterProd,
            'broken': afterBroken,
            'water': newWater,
            'mortality': newMortality,
            'vet': newVet,
          },
          'delta': {
            'goodTotalEggs': deltaGoodTotal,
            'brokenTotalEggs': deltaBrokenTotal,
            'goodByGrade': {
              'SMALL': (newEggsByGrade['SMALL'] ?? 0) - (beforeEggsByGrade['SMALL'] ?? 0),
              'MEDIUM': (newEggsByGrade['MEDIUM'] ?? 0) - (beforeEggsByGrade['MEDIUM'] ?? 0),
              'LARGE': (newEggsByGrade['LARGE'] ?? 0) - (beforeEggsByGrade['LARGE'] ?? 0),
              'XL': (newEggsByGrade['XL'] ?? 0) - (beforeEggsByGrade['XL'] ?? 0),
            },
          },
        });
      });

      if (mounted) {
        setState(() => _message = "Correction enregistrée ✅");
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _message = "Erreur : ${e.toString()}");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _gradeRow(String label, String grade) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _alvCtrls[grade],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Alvéoles',
                  border: OutlineInputBorder(),
                ),
                enabled: !_saving,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _isoCtrls[grade],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Œufs isolés (0..29)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_saving,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entryRef = _db
        .collection('farms')
        .doc(widget.farmId)
        .collection('daily_entries')
        .doc(widget.dailyEntryDocId);

    return Scaffold(
      appBar: AppBar(
        title: Text("Modifier – ${widget.dateIso}"),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: entryRef.snapshots(),
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
            return const Center(child: Text("Rapport introuvable"));
          }

          final entry = snap.data!.data() ?? <String, dynamic>{};

          // init une seule fois (pour remplir les champs)
          if (!_initialized) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _initFromDoc(entry));
            });
          }

          final msg = _message;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Text(
                  "Bâtiment : ${widget.building.name}",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text("Date : ${widget.dateIso}"),
                const Divider(height: 24),

                // PONTE
                Text("Ponte (bons œufs)", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                _gradeRow("Petit calibre", 'SMALL'),
                _gradeRow("Moyen calibre", 'MEDIUM'),
                _gradeRow("Gros calibre", 'LARGE'),
                _gradeRow("Très gros calibre", 'XL'),

                const Divider(height: 24),

                // CASSES
                Text("Casses (collecte bâtiment)", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _brokenAlvCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Alvéoles cassées',
                          border: OutlineInputBorder(),
                        ),
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _brokenIsoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Œufs isolés (0..29)',
                          border: OutlineInputBorder(),
                        ),
                        enabled: !_saving,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _brokenNoteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_saving,
                ),

                const Divider(height: 24),

                // EAU
                Text("Eau", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'MANUAL',
                        groupValue: _waterMode,
                        title: const Text("Manuel"),
                        onChanged: _saving ? null : (v) => setState(() => _waterMode = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'ESTIMATE',
                        groupValue: _waterMode,
                        title: const Text("Estimé"),
                        onChanged: _saving ? null : (v) => setState(() => _waterMode = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _waterLitersCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Litres",
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_saving,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _waterNoteCtrl,
                  decoration: const InputDecoration(
                    labelText: "Note eau (optionnel)",
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_saving,
                ),

                const Divider(height: 24),

                // MORTALITÉ
                Text("Mortalité", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                TextField(
                  controller: _mortQtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Quantité",
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_saving,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _mortCauseCtrl,
                  decoration: const InputDecoration(
                    labelText: "Cause (optionnel)",
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_saving,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _mortNoteCtrl,
                  decoration: const InputDecoration(
                    labelText: "Note (optionnel)",
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_saving,
                ),

                const Divider(height: 24),

                // VÉTO
                Text("Vétérinaire (correction)", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _noVet,
                  onChanged: _saving
                      ? null
                      : (v) {
                    setState(() {
                      _noVet = v ?? true;
                      if (_noVet) {
                        _vetItemId = null;
                        _vetQtyCtrl.text = "0";
                        _vetUnitCtrl.text = "unité";
                        _vetNoteCtrl.text = "";
                      }
                    });
                  },
                  title: const Text("Aucun traitement vétérinaire"),
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Produit (itemId) – optionnel",
                    border: OutlineInputBorder(),
                    helperText:
                    "Pour l’instant on corrige au niveau agrégé. (On pourra lier à une liste items plus tard.)",
                  ),
                  enabled: !_saving && !_noVet,
                  controller: TextEditingController(text: _vetItemId ?? "")
                    ..selection = TextSelection.fromPosition(
                      TextPosition(offset: (_vetItemId ?? "").length),
                    ),
                  onChanged: (v) => _vetItemId = v.trim(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _vetQtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Quantité",
                          border: OutlineInputBorder(),
                        ),
                        enabled: !_saving && !_noVet,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _vetUnitCtrl,
                        decoration: const InputDecoration(
                          labelText: "Unité",
                          border: OutlineInputBorder(),
                        ),
                        enabled: !_saving && !_noVet,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _vetNoteCtrl,
                  decoration: const InputDecoration(
                    labelText: "Note véto (optionnel)",
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_saving && !_noVet,
                ),

                const SizedBox(height: 18),

                FilledButton.icon(
                  onPressed: _saving ? null : () => _saveCorrection(snap.data!),
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? "Enregistrement..." : "Enregistrer la correction"),
                ),

                const SizedBox(height: 12),
                if (msg != null)
                  Text(
                    msg,
                    style: TextStyle(
                      color: msg.startsWith("Erreur") ? Colors.red : Colors.green,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
