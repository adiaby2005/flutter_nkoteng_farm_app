// lib/screens/egg_transfer_farm_to_depot_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EggTransferFarmToDepotScreen extends StatefulWidget {
  final String farmId;

  const EggTransferFarmToDepotScreen({
    super.key,
    required this.farmId,
  });

  @override
  State<EggTransferFarmToDepotScreen> createState() => _EggTransferFarmToDepotScreenState();
}

class _EggTransferFarmToDepotScreenState extends State<EggTransferFarmToDepotScreen> {
  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  String? _message;

  DateTime _date = DateTime.now();

  String? _selectedDepotId;
  Map<String, dynamic>? _selectedDepot;

  // Sorties (en cartons + alvéoles + isolés)
  final _goodSmallCartonsCtrl = TextEditingController();
  final _goodSmallAlveolesCtrl = TextEditingController();
  final _goodSmallIsolatedCtrl = TextEditingController();

  final _goodMedCartonsCtrl = TextEditingController();
  final _goodMedAlveolesCtrl = TextEditingController();
  final _goodMedIsolatedCtrl = TextEditingController();

  final _goodLargeCartonsCtrl = TextEditingController();
  final _goodLargeAlveolesCtrl = TextEditingController();
  final _goodLargeIsolatedCtrl = TextEditingController();

  final _goodXlCartonsCtrl = TextEditingController();
  final _goodXlAlveolesCtrl = TextEditingController();
  final _goodXlIsolatedCtrl = TextEditingController();

  final _brokenEggsCtrl = TextEditingController();

  @override
  void dispose() {
    _goodSmallCartonsCtrl.dispose();
    _goodSmallAlveolesCtrl.dispose();
    _goodSmallIsolatedCtrl.dispose();

    _goodMedCartonsCtrl.dispose();
    _goodMedAlveolesCtrl.dispose();
    _goodMedIsolatedCtrl.dispose();

    _goodLargeCartonsCtrl.dispose();
    _goodLargeAlveolesCtrl.dispose();
    _goodLargeIsolatedCtrl.dispose();

    _goodXlCartonsCtrl.dispose();
    _goodXlAlveolesCtrl.dispose();
    _goodXlIsolatedCtrl.dispose();

    _brokenEggsCtrl.dispose();

    super.dispose();
  }

  String _dateIso(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    final m = dd.month.toString().padLeft(2, '0');
    final day = dd.day.toString().padLeft(2, '0');
    return '${dd.year}-$m-$day';
  }

  int _toInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int _getInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  int _eggsFromCartonsAlveolesIsolated({
    required int cartons,
    required int alveoles,
    required int isolated,
  }) {
    const eggsPerAlveole = 30;
    const alveolesPerCarton = 12;
    const eggsPerCarton = eggsPerAlveole * alveolesPerCarton; // 360
    return cartons * eggsPerCarton + alveoles * eggsPerAlveole + isolated;
  }

  bool _validateIsolated0to29(int v) => v >= 0 && v <= 29;

  Map<String, int> _goodOutByGrade() {
    final s = _eggsFromCartonsAlveolesIsolated(
      cartons: _toInt(_goodSmallCartonsCtrl),
      alveoles: _toInt(_goodSmallAlveolesCtrl),
      isolated: _toInt(_goodSmallIsolatedCtrl),
    );
    final m = _eggsFromCartonsAlveolesIsolated(
      cartons: _toInt(_goodMedCartonsCtrl),
      alveoles: _toInt(_goodMedAlveolesCtrl),
      isolated: _toInt(_goodMedIsolatedCtrl),
    );
    final l = _eggsFromCartonsAlveolesIsolated(
      cartons: _toInt(_goodLargeCartonsCtrl),
      alveoles: _toInt(_goodLargeAlveolesCtrl),
      isolated: _toInt(_goodLargeIsolatedCtrl),
    );
    final xl = _eggsFromCartonsAlveolesIsolated(
      cartons: _toInt(_goodXlCartonsCtrl),
      alveoles: _toInt(_goodXlAlveolesCtrl),
      isolated: _toInt(_goodXlIsolatedCtrl),
    );

    return {
      'SMALL': s,
      'MEDIUM': m,
      'LARGE': l,
      'XL': xl,
    };
  }

  int _brokenOutTotal() => _toInt(_brokenEggsCtrl);

  int _sumGrades(Map<String, int> byGrade) =>
      byGrade.values.fold<int>(0, (a, b) => a + b);

  void _validate() {
    if (_selectedDepotId == null) throw Exception("Veuillez sélectionner un dépôt.");

    final isoSmall = _toInt(_goodSmallIsolatedCtrl);
    final isoMed = _toInt(_goodMedIsolatedCtrl);
    final isoLarge = _toInt(_goodLargeIsolatedCtrl);
    final isoXl = _toInt(_goodXlIsolatedCtrl);

    if (!_validateIsolated0to29(isoSmall)) throw Exception("Petit isolés: 0..29");
    if (!_validateIsolated0to29(isoMed)) throw Exception("Moyen isolés: 0..29");
    if (!_validateIsolated0to29(isoLarge)) throw Exception("Gros isolés: 0..29");
    if (!_validateIsolated0to29(isoXl)) throw Exception("XL isolés: 0..29");

    final goodOut = _goodOutByGrade();
    final goodTotal = _sumGrades(goodOut);
    final brokenTotal = _brokenOutTotal();

    if (goodTotal == 0 && brokenTotal == 0) throw Exception("Aucune sortie à enregistrer.");
  }

  // ✅ Recalcul FARM_GLOBAL à partir des BUILDING_* uniquement (et l'écrit)
  Future<void> _recomputeFarmGlobal() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final farmRef = _db.collection('farms').doc(widget.farmId);
      final stocks = await farmRef.collection('stocks_eggs').get();

      final Map<String, int> agg = {
        'SMALL': 0,
        'MEDIUM': 0,
        'LARGE': 0,
        'XL': 0,
      };

      int total = 0;

      for (final doc in stocks.docs) {
        if (!doc.id.startsWith('BUILDING_')) continue;
        final data = doc.data();
        final raw = data['eggsByGrade'];
        final m = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

        agg['SMALL'] = (agg['SMALL'] ?? 0) + _getInt(m['SMALL']);
        agg['MEDIUM'] = (agg['MEDIUM'] ?? 0) + _getInt(m['MEDIUM']);
        agg['LARGE'] = (agg['LARGE'] ?? 0) + _getInt(m['LARGE']);
        agg['XL'] = (agg['XL'] ?? 0) + _getInt(m['XL']);
      }

      total = agg.values.fold<int>(0, (a, b) => a + b);

      await farmRef.collection('stocks_eggs').doc('FARM_GLOBAL').set(
        {
          'kind': 'FARM_GLOBAL',
          'refId': widget.farmId,
          'eggsByGrade': agg,
          'goodTotalEggs': total,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      setState(() => _message = "Stock ferme recalculé ✅");
    } catch (e) {
      setState(() => _message = "Erreur recalcul: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2022, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _saveTransfer() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      _validate();

      final dateIso = _dateIso(_date);
      final farmRef = _db.collection('farms').doc(widget.farmId);

      final goodOut = _goodOutByGrade();
      final brokenOut = _brokenOutTotal();

      final movementRef = farmRef.collection('egg_movements').doc();

      final uniqueKey = [
        'TRANSFER_FARM_TO_DEPOT',
        widget.farmId,
        dateIso,
        _selectedDepotId!,
        _sumGrades(goodOut).toString(),
        brokenOut.toString(),
      ].join('|');

      final lockRef = farmRef.collection('idempotency').doc(uniqueKey);

      final farmGlobalRef = farmRef.collection('stocks_eggs').doc('FARM_GLOBAL');
      final depotStockRef =
      farmRef.collection('stocks_eggs').doc('DEPOT_${_selectedDepotId!}');

      await _db.runTransaction((tx) async {
        final lock = await tx.get(lockRef);
        if (lock.exists) return;

        final fgSnap = await tx.get(farmGlobalRef);
        final fgData = fgSnap.data() ?? <String, dynamic>{};

        final fgByGradeDyn =
        (fgData['eggsByGrade'] is Map) ? Map<String, dynamic>.from(fgData['eggsByGrade']) : <String, dynamic>{};

        int fgCur(String g) => (fgByGradeDyn[g] is num) ? (fgByGradeDyn[g] as num).toInt() : 0;

        // vérifier dispo
        for (final g in const ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
          final need = goodOut[g] ?? 0;
          final cur = fgCur(g);
          if (need > cur) {
            throw Exception("Stock insuffisant ($g): demandé=$need disponible=$cur");
          }
        }

        // Update FARM_GLOBAL (sortie)
        final Map<String, int> fgNewByGrade = {
          'SMALL': fgCur('SMALL') - (goodOut['SMALL'] ?? 0),
          'MEDIUM': fgCur('MEDIUM') - (goodOut['MEDIUM'] ?? 0),
          'LARGE': fgCur('LARGE') - (goodOut['LARGE'] ?? 0),
          'XL': fgCur('XL') - (goodOut['XL'] ?? 0),
        };

        final fgGoodTotal = (fgData['goodTotalEggs'] ?? fgData['totalGoodEggs'] ?? 0) is num
            ? ((fgData['goodTotalEggs'] ?? fgData['totalGoodEggs'] ?? 0) as num).toInt()
            : 0;

        final goodTotalOut = _sumGrades(goodOut);

        tx.set(
          farmGlobalRef,
          {
            'eggsByGrade': fgNewByGrade,
            'goodTotalEggs': fgGoodTotal - goodTotalOut,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // Update depot stock (entrée)
        final dsSnap = await tx.get(depotStockRef);
        final dsData = dsSnap.data() ?? <String, dynamic>{};

        final dsByGradeDyn =
        (dsData['eggsByGrade'] is Map) ? Map<String, dynamic>.from(dsData['eggsByGrade']) : <String, dynamic>{};

        int dsCur(String g) => (dsByGradeDyn[g] is num) ? (dsByGradeDyn[g] as num).toInt() : 0;

        final Map<String, int> dsNewByGrade = {
          'SMALL': dsCur('SMALL') + (goodOut['SMALL'] ?? 0),
          'MEDIUM': dsCur('MEDIUM') + (goodOut['MEDIUM'] ?? 0),
          'LARGE': dsCur('LARGE') + (goodOut['LARGE'] ?? 0),
          'XL': dsCur('XL') + (goodOut['XL'] ?? 0),
        };

        final dsGoodTotal = (dsData['goodTotalEggs'] ?? dsData['totalGoodEggs'] ?? 0) is num
            ? ((dsData['goodTotalEggs'] ?? dsData['totalGoodEggs'] ?? 0) as num).toInt()
            : 0;

        tx.set(
          depotStockRef,
          {
            'kind': 'DEPOT',
            'refId': _selectedDepotId!,
            'eggsByGrade': dsNewByGrade,
            'goodTotalEggs': dsGoodTotal + goodTotalOut,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // Movement
        tx.set(movementRef, {
          'type': 'FARM_TO_DEPOT',
          'date': dateIso,
          'from': {'kind': 'FARM', 'farmId': widget.farmId},
          'to': {'kind': 'DEPOT', 'depotId': _selectedDepotId, 'depotName': _selectedDepot?['name']},
          'goodOutByGrade': goodOut,
          'goodTotalOut': goodTotalOut,
          'brokenOut': brokenOut,
          'createdAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        });

        tx.set(lockRef, {'createdAt': FieldValue.serverTimestamp(), 'kind': 'TRANSFER_FARM_TO_DEPOT'});
      });

      setState(() => _message = "Transfert enregistré ✅");
    } catch (e) {
      setState(() => _message = "Erreur: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateIso = _dateIso(_date);

    final depotsQuery = _db
        .collection('farms')
        .doc(widget.farmId)
        .collection('depots')
        .orderBy('name');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Transfert œufs → dépôt"),
        actions: [
          IconButton(
            tooltip: "Recalculer stock ferme",
            onPressed: _loading ? null : _recomputeFarmGlobal,
            icon: const Icon(Icons.refresh),
          ),
          TextButton.icon(
            onPressed: _loading ? null : _pickDate,
            icon: const Icon(Icons.date_range),
            label: Text(dateIso),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _message!,
                style: TextStyle(
                  color: (_message!.startsWith('Erreur')) ? Colors.red : Colors.green,
                ),
              ),
            ),

          const Text("Dépôt", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: depotsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snap.hasError) {
                return Text("Erreur dépôts: ${snap.error}", style: const TextStyle(color: Colors.red));
              }

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const Text("Aucun dépôt.");

              return DropdownButtonFormField<String>(
                value: _selectedDepotId,
                items: docs
                    .map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text((d.data()['name'] ?? d.id).toString()),
                ))
                    .toList(),
                onChanged: _loading
                    ? null
                    : (v) {
                  setState(() {
                    _selectedDepotId = v;
                    _selectedDepot = docs.firstWhere((e) => e.id == v).data();
                  });
                },
                decoration: const InputDecoration(border: OutlineInputBorder()),
              );
            },
          ),

          const SizedBox(height: 16),
          const Text("Sortie (bons œufs) - par cartons / alvéoles / isolés",
              style: TextStyle(fontWeight: FontWeight.bold)),

          const SizedBox(height: 12),
          _gradeBlock("Petit", _goodSmallCartonsCtrl, _goodSmallAlveolesCtrl, _goodSmallIsolatedCtrl),
          _gradeBlock("Moyen", _goodMedCartonsCtrl, _goodMedAlveolesCtrl, _goodMedIsolatedCtrl),
          _gradeBlock("Gros", _goodLargeCartonsCtrl, _goodLargeAlveolesCtrl, _goodLargeIsolatedCtrl),
          _gradeBlock("XL", _goodXlCartonsCtrl, _goodXlAlveolesCtrl, _goodXlIsolatedCtrl),

          const SizedBox(height: 12),
          TextField(
            controller: _brokenEggsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Casses (œufs)",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _saveTransfer,
              icon: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_loading ? "Enregistrement..." : "Enregistrer"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeBlock(
      String label,
      TextEditingController cartonsCtrl,
      TextEditingController alveolesCtrl,
      TextEditingController isolatedCtrl,
      ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cartonsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Cartons",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: alveolesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Alvéoles",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: isolatedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Isolés (0..29)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
