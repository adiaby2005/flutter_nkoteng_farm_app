import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DepotStockAdjustmentScreen extends StatefulWidget {
  final String farmId;
  final String depotId;

  const DepotStockAdjustmentScreen({
    super.key,
    required this.farmId,
    required this.depotId,
  });

  @override
  State<DepotStockAdjustmentScreen> createState() => _DepotStockAdjustmentScreenState();
}

class _DepotStockAdjustmentScreenState extends State<DepotStockAdjustmentScreen> {
  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  String? _message;

  DateTime _selectedDate = DateTime.now();

  // --- Recalibrage (déplacer qty eggs : fromGrade -> toGrade)
  String _recalFrom = 'MEDIUM';
  String _recalTo = 'LARGE';
  final TextEditingController _recalQtyCtrl = TextEditingController(text: "0");

  // --- Casses (déclarer qty cassés depuis un calibre)
  String _brokenFromGrade = 'MEDIUM';
  final TextEditingController _brokenQtyCtrl = TextEditingController(text: "0");

  // --- Note
  final TextEditingController _noteCtrl = TextEditingController();

  // --- Cache du stock courant (pour validation UI)
  Map<String, int> _goodStock = {'SMALL': 0, 'MEDIUM': 0, 'LARGE': 0, 'XL': 0};
  int _brokenStock = 0;
  String _depotName = "";

  @override
  void dispose() {
    _recalQtyCtrl.dispose();
    _brokenQtyCtrl.dispose();
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

  Map<String, int> _readGrades(Map<String, dynamic> doc, String key) {
    final raw = doc[key];
    final m = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return {
      'SMALL': _asInt(m['SMALL']),
      'MEDIUM': _asInt(m['MEDIUM']),
      'LARGE': _asInt(m['LARGE']),
      'XL': _asInt(m['XL']),
    };
  }

  Map<String, int> _pickGoodByGrade(Map<String, dynamic> data) {
    // Priorité: goodByGrade, sinon eggsByGrade
    final good = _readGrades(data, 'goodByGrade');
    final eggs = _readGrades(data, 'eggsByGrade');

    int pick(String g) {
      final v = good[g] ?? 0;
      if (v != 0) return v;
      return eggs[g] ?? 0;
    }

    return {
      'SMALL': pick('SMALL'),
      'MEDIUM': pick('MEDIUM'),
      'LARGE': pick('LARGE'),
      'XL': pick('XL'),
    };
  }

  int _parseInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

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

  int _trays(int eggs) => eggs ~/ 30;
  int _isolated(int eggs) => eggs % 30;

  Widget _stockLine(String grade, int eggs) {
    return Row(
      children: [
        Expanded(child: Text(_gradeFr(grade), style: const TextStyle(fontWeight: FontWeight.w600))),
        Text("Total: $eggs  •  Alv: ${_trays(eggs)}  •  Isolés: ${_isolated(eggs)}"),
      ],
    );
  }

  void _validateUI() {
    final recalQty = _parseInt(_recalQtyCtrl);
    final brokenQty = _parseInt(_brokenQtyCtrl);

    if (recalQty < 0) throw Exception("Recalibrage: quantité négative interdite.");
    if (brokenQty < 0) throw Exception("Casses: quantité négative interdite.");

    final hasRecal = recalQty > 0;
    final hasBroken = brokenQty > 0;

    if (!hasRecal && !hasBroken) {
      throw Exception("Aucun ajustement à enregistrer.");
    }

    if (hasRecal) {
      if (_recalFrom == _recalTo) {
        throw Exception("Recalibrage: le calibre source et destination doivent être différents.");
      }
      final fromStock = _goodStock[_recalFrom] ?? 0;
      if (recalQty > fromStock) {
        throw Exception(
          "Recalibrage: stock insuffisant en ${_gradeFr(_recalFrom)}. Stock=$fromStock, déplacement=$recalQty.",
        );
      }
    }

    if (hasBroken) {
      final fromStock = _goodStock[_brokenFromGrade] ?? 0;
      if (brokenQty > fromStock) {
        throw Exception(
          "Casses: stock insuffisant en ${_gradeFr(_brokenFromGrade)}. Stock=$fromStock, casses=$brokenQty.",
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      _validateUI();

      final farmRef = _db.collection('farms').doc(widget.farmId);
      final depotRef = farmRef.collection('depots').doc(widget.depotId);
      final stockRef = farmRef.collection('stocks_eggs').doc("DEPOT_${widget.depotId}");
      final movementsCol = farmRef.collection('egg_movements');

      final dateIso = _dateIso(_selectedDate);

      final recalQty = _parseInt(_recalQtyCtrl);
      final brokenQty = _parseInt(_brokenQtyCtrl);

      final hasRecal = recalQty > 0;
      final hasBroken = brokenQty > 0;

      String kind;
      if (hasRecal && hasBroken) {
        kind = 'MIXED';
      } else if (hasRecal) {
        kind = 'RECALIBRATION';
      } else {
        kind = 'BROKEN_DECLARATION';
      }

      final uniqueKey = [
        'DEPOT_ADJ',
        widget.farmId,
        dateIso,
        widget.depotId,
        kind,
        hasRecal ? _recalFrom : '-',
        hasRecal ? _recalTo : '-',
        recalQty.toString(),
        hasBroken ? _brokenFromGrade : '-',
        brokenQty.toString(),
      ].join('|');

      final lockRef = farmRef.collection('idempotency').doc(uniqueKey);
      final movementRef = movementsCol.doc();

      await _db.runTransaction((tx) async {
        // READS FIRST
        final lockSnap = await tx.get(lockRef);
        if (lockSnap.exists) return;

        final depotSnap = await tx.get(depotRef);
        final depotName = (depotSnap.data()?['name'] ?? widget.depotId).toString();

        final stockSnap = await tx.get(stockRef);
        if (!stockSnap.exists) {
          // On crée un stock dépôt vide si absent
          // (mais on a quand même besoin d'une base)
        }

        final stockData = stockSnap.data() ?? <String, dynamic>{};
        final currentGood = _pickGoodByGrade(stockData);
        final currentBroken = _asInt(stockData['brokenTotalEggs']);
        final currentGoodTotal = _asInt(stockData['goodTotalEggs']);

        // Re-valider côté transaction
        if (hasRecal) {
          final fromHave = currentGood[_recalFrom] ?? 0;
          if (recalQty > fromHave) {
            throw Exception("Recalibrage: stock insuffisant (transaction).");
          }
        }
        if (hasBroken) {
          final fromHave = currentGood[_brokenFromGrade] ?? 0;
          if (brokenQty > fromHave) {
            throw Exception("Casses: stock insuffisant (transaction).");
          }
        }

        // Calculs nouveaux stocks
        final newGood = Map<String, int>.from(currentGood);
        var newBroken = currentBroken;
        var newGoodTotal = currentGoodTotal;

        if (hasRecal) {
          newGood[_recalFrom] = (newGood[_recalFrom] ?? 0) - recalQty;
          newGood[_recalTo] = (newGood[_recalTo] ?? 0) + recalQty;
          // total bons inchangé
        }

        if (hasBroken) {
          newGood[_brokenFromGrade] = (newGood[_brokenFromGrade] ?? 0) - brokenQty;
          newBroken = newBroken + brokenQty;
          newGoodTotal = newGoodTotal - brokenQty;
        }

        // Guardrails
        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
          if ((newGood[g] ?? 0) < 0) throw Exception("Incohérence: stock négatif ($g).");
        }
        if (newBroken < 0 || newGoodTotal < 0) throw Exception("Incohérence: stock négatif.");

        // WRITES
        tx.set(movementRef, {
          'date': dateIso,
          'type': 'DEPOT_ADJUSTMENT',
          'adjustmentKind': kind,
          'depot': {
            'id': widget.depotId,
            'name': depotName,
          },
          'recalibration': hasRecal
              ? {
            'fromGrade': _recalFrom,
            'toGrade': _recalTo,
            'qtyEggs': recalQty,
          }
              : null,
          'brokenDeclaration': hasBroken
              ? {
            'fromGrade': _brokenFromGrade,
            'qtyEggs': brokenQty,
          }
              : null,
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
          'eggsByGrade': newGood, // compat
          'goodTotalEggs': newGood.values.fold<int>(0, (a, b) => a + b),
          'brokenTotalEggs': newBroken,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(lockRef, {
          'kind': 'DEPOT_ADJUSTMENT',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      // reset UI
      _recalQtyCtrl.text = "0";
      _brokenQtyCtrl.text = "0";
      _noteCtrl.clear();

      setState(() => _message = "Ajustement dépôt enregistré ✅");
    } catch (e) {
      setState(() => _message = "Erreur : ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmRef = _db.collection('farms').doc(widget.farmId);
    final depotRef = farmRef.collection('depots').doc(widget.depotId);
    final stockRef = farmRef.collection('stocks_eggs').doc("DEPOT_${widget.depotId}");

    final msg = _message;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ajustements dépôt"),
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
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: depotRef.snapshots(),
              builder: (context, snap) {
                final name = (snap.data?.data()?['name'] ?? widget.depotId).toString();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (name != _depotName) setState(() => _depotName = name);
                });
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.store),
                  title: const Text("Dépôt"),
                  subtitle: Text(name),
                );
              },
            ),

            const Divider(height: 24),

            // STOCK LIVE
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: stockRef.snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  );
                }

                final data = snap.data!.data() ?? <String, dynamic>{};
                final good = _pickGoodByGrade(data);
                final broken = _asInt(data['brokenTotalEggs']);

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final changed = (good['SMALL'] != _goodStock['SMALL']) ||
                      (good['MEDIUM'] != _goodStock['MEDIUM']) ||
                      (good['LARGE'] != _goodStock['LARGE']) ||
                      (good['XL'] != _goodStock['XL']) ||
                      (broken != _brokenStock);
                  if (changed) {
                    setState(() {
                      _goodStock = good;
                      _brokenStock = broken;
                    });
                  }
                });

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Stock actuel dépôt", style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 10),
                        _stockLine('SMALL', good['SMALL'] ?? 0),
                        const SizedBox(height: 6),
                        _stockLine('MEDIUM', good['MEDIUM'] ?? 0),
                        const SizedBox(height: 6),
                        _stockLine('LARGE', good['LARGE'] ?? 0),
                        const SizedBox(height: 6),
                        _stockLine('XL', good['XL'] ?? 0),
                        const Divider(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text("Casses", style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            Text(
                              "$broken",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const Divider(height: 24),

            // RECALIBRAGE
            Text("Recalibrage (déplacer entre calibres)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _recalFrom,
                    decoration: const InputDecoration(
                      labelText: "Depuis",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'SMALL', child: Text("Petit")),
                      DropdownMenuItem(value: 'MEDIUM', child: Text("Moyen")),
                      DropdownMenuItem(value: 'LARGE', child: Text("Gros")),
                      DropdownMenuItem(value: 'XL', child: Text("Très gros")),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _recalFrom = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _recalTo,
                    decoration: const InputDecoration(
                      labelText: "Vers",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'SMALL', child: Text("Petit")),
                      DropdownMenuItem(value: 'MEDIUM', child: Text("Moyen")),
                      DropdownMenuItem(value: 'LARGE', child: Text("Gros")),
                      DropdownMenuItem(value: 'XL', child: Text("Très gros")),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _recalTo = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _recalQtyCtrl,
              keyboardType: TextInputType.number,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: "Quantité à déplacer (œufs)",
                border: OutlineInputBorder(),
                helperText: "Ex: 60 = 2 alvéoles",
              ),
            ),

            const Divider(height: 24),

            // CASSES
            Text("Déclaration de casses (au dépôt)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: _brokenFromGrade,
              decoration: const InputDecoration(
                labelText: "Calibre impacté",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'SMALL', child: Text("Petit")),
                DropdownMenuItem(value: 'MEDIUM', child: Text("Moyen")),
                DropdownMenuItem(value: 'LARGE', child: Text("Gros")),
                DropdownMenuItem(value: 'XL', child: Text("Très gros")),
              ],
              onChanged: _loading ? null : (v) => setState(() => _brokenFromGrade = v!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _brokenQtyCtrl,
              keyboardType: TextInputType.number,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: "Quantité cassée (œufs)",
                border: OutlineInputBorder(),
              ),
            ),

            const Divider(height: 24),

            TextField(
              controller: _noteCtrl,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: "Note (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_loading ? "Enregistrement..." : "Enregistrer"),
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
