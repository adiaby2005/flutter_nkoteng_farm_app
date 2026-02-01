import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'clients_screen.dart';

class DepotSaleScreen extends StatefulWidget {
  final String farmId;
  final String depotId;
  final String depotName;

  const DepotSaleScreen({
    super.key,
    required this.farmId,
    required this.depotId,
    required this.depotName,
  });

  @override
  State<DepotSaleScreen> createState() => _DepotSaleScreenState();
}

class _DepotSaleScreenState extends State<DepotSaleScreen> {
  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  String? _message;
  DateTime _selectedDate = DateTime.now();

  // Client sélectionné
  String? _selectedCustomerId;
  String? _selectedCustomerName;

  // Paiement au moment de la vente
  bool _takePaymentNow = false;
  final TextEditingController _paidNowCtrl = TextEditingController(text: "0");

  // Saisie : cartons + prix unitaire/carton (par calibre)
  final Map<String, TextEditingController> _cartonsCtrls = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };

  final Map<String, TextEditingController> _unitPriceCtrls = {
    'SMALL': TextEditingController(text: "0"),
    'MEDIUM': TextEditingController(text: "0"),
    'LARGE': TextEditingController(text: "0"),
    'XL': TextEditingController(text: "0"),
  };

  final TextEditingController _noteCtrl = TextEditingController();

  // Stock dépôt (œufs) par grade
  Map<String, int> _depotEggsByGrade = {'SMALL': 0, 'MEDIUM': 0, 'LARGE': 0, 'XL': 0};

  static const int eggsPerTray = 30;
  static const int traysPerCarton = 12;
  static const int eggsPerCarton = eggsPerTray * traysPerCarton; // 360

  @override
  void initState() {
    super.initState();
    for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      _cartonsCtrls[g]!.addListener(_recalc);
      _unitPriceCtrls[g]!.addListener(_recalc);
    }
    _paidNowCtrl.addListener(_recalc);
  }

  @override
  void dispose() {
    for (final c in _cartonsCtrls.values) c.dispose();
    for (final c in _unitPriceCtrls.values) c.dispose();
    _noteCtrl.dispose();
    _paidNowCtrl.dispose();
    super.dispose();
  }

  void _recalc() {
    if (!mounted) return;
    setState(() {});
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

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int _availableCartons(int eggs) {
    final trays = eggs ~/ eggsPerTray;
    return trays ~/ traysPerCarton;
  }

  String _remainderInfo(int eggs) {
    final trays = eggs ~/ eggsPerTray;
    final cartons = trays ~/ traysPerCarton;
    final traysR = trays % traysPerCarton;
    final iso = eggs % eggsPerTray;
    return "Dispo: $cartons c + $traysR a + $iso i";
  }

  int _lineTotal(String g) {
    final cartons = _parse(_cartonsCtrls[g]!);
    final unit = _parse(_unitPriceCtrls[g]!);
    if (cartons <= 0 || unit <= 0) return 0;
    return cartons * unit;
  }

  int _grandTotal() {
    int t = 0;
    for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
      t += _lineTotal(g);
    }
    return t;
  }

  Map<String, int> _readGoodByGrade(Map<String, dynamic> data) {
    Map<String, int> readGrades(String key) {
      final m = _asMap(data[key]);
      return {
        'SMALL': _asInt(m['SMALL']),
        'MEDIUM': _asInt(m['MEDIUM']),
        'LARGE': _asInt(m['LARGE']),
        'XL': _asInt(m['XL']),
      };
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

  String _paymentStatus(int total, int paid) {
    if (total <= 0) return 'UNPAID';
    if (paid <= 0) return 'UNPAID';
    if (paid >= total) return 'PAID';
    return 'PARTIAL';
  }

  Future<void> _saveSale() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      // Validations: cartons >=0, unit>=0
      for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
        final cartons = _parse(_cartonsCtrls[g]!);
        final unit = _parse(_unitPriceCtrls[g]!);
        if (cartons < 0 || unit < 0) throw Exception("Valeurs négatives interdites.");
      }

      // Il faut au moins 1 ligne avec cartons>0
      final hasQty = ['SMALL', 'MEDIUM', 'LARGE', 'XL'].any((g) => _parse(_cartonsCtrls[g]!) > 0);
      if (!hasQty) throw Exception("Renseigne au moins un nombre de cartons à vendre.");

      // Client: optionnel
      final customer = {
        'id': _selectedCustomerId,
        'name': _selectedCustomerName,
      };

      final dateIso = _dateIso(_selectedDate);

      final farmRef = _db.collection('farms').doc(widget.farmId);
      final depotStockRef = farmRef.collection('stocks_eggs').doc("DEPOT_${widget.depotId}");
      final saleRef = farmRef.collection('egg_movements').doc();

      // Calcul vente en cartons => eggs
      final soldCartonsByGrade = <String, int>{
        'SMALL': _parse(_cartonsCtrls['SMALL']!),
        'MEDIUM': _parse(_cartonsCtrls['MEDIUM']!),
        'LARGE': _parse(_cartonsCtrls['LARGE']!),
        'XL': _parse(_cartonsCtrls['XL']!),
      };

      final unitPriceByGrade = <String, int>{
        'SMALL': _parse(_unitPriceCtrls['SMALL']!),
        'MEDIUM': _parse(_unitPriceCtrls['MEDIUM']!),
        'LARGE': _parse(_unitPriceCtrls['LARGE']!),
        'XL': _parse(_unitPriceCtrls['XL']!),
      };

      final lineTotalByGrade = <String, int>{
        'SMALL': _lineTotal('SMALL'),
        'MEDIUM': _lineTotal('MEDIUM'),
        'LARGE': _lineTotal('LARGE'),
        'XL': _lineTotal('XL'),
      };

      final totalAmount = _grandTotal();
      if (totalAmount <= 0) throw Exception("Montant total invalide (vérifie prix/unités).");

      final soldEggsByGrade = <String, int>{
        'SMALL': soldCartonsByGrade['SMALL']! * eggsPerCarton,
        'MEDIUM': soldCartonsByGrade['MEDIUM']! * eggsPerCarton,
        'LARGE': soldCartonsByGrade['LARGE']! * eggsPerCarton,
        'XL': soldCartonsByGrade['XL']! * eggsPerCarton,
      };

      // Paiement initial
      int amountPaid = 0;
      if (_takePaymentNow) {
        amountPaid = _parse(_paidNowCtrl);
        if (amountPaid < 0) throw Exception("Montant encaissé invalide.");
        if (amountPaid > totalAmount) amountPaid = totalAmount;
      }
      final amountDue = totalAmount - amountPaid;
      final status = _paymentStatus(totalAmount, amountPaid);
      final paidBool = (status == 'PAID');

      // Validation stock dispo: uniquement cartons entiers possibles
      for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
        final eggsAvail = _depotEggsByGrade[g] ?? 0;
        final cartonsAvail = _availableCartons(eggsAvail);
        if (soldCartonsByGrade[g]! > cartonsAvail) {
          throw Exception("Stock insuffisant pour ${_gradeFr(g)} (dispo: $cartonsAvail cartons).");
        }
      }

      await _db.runTransaction((tx) async {
        final depotSnap = await tx.get(depotStockRef);
        final depotData = depotSnap.data() ?? <String, dynamic>{};
        final depotGoodEggs = _readGoodByGrade(depotData);

        // re-check
        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
          final cartonsAvail = _availableCartons(depotGoodEggs[g] ?? 0);
          if (soldCartonsByGrade[g]! > cartonsAvail) {
            throw Exception("Stock insuffisant (rafraîchir).");
          }
        }

        // Update stock (soustraction en œufs)
        final newDepotGood = <String, int>{
          'SMALL': (depotGoodEggs['SMALL'] ?? 0) - soldEggsByGrade['SMALL']!,
          'MEDIUM': (depotGoodEggs['MEDIUM'] ?? 0) - soldEggsByGrade['MEDIUM']!,
          'LARGE': (depotGoodEggs['LARGE'] ?? 0) - soldEggsByGrade['LARGE']!,
          'XL': (depotGoodEggs['XL'] ?? 0) - soldEggsByGrade['XL']!,
        };

        final nowTs = FieldValue.serverTimestamp();

        tx.set(saleRef, {
          'date': dateIso,
          'type': 'SALE',
          'from': {'kind': 'DEPOT', 'id': widget.depotId, 'name': widget.depotName},
          'customer': customer['name'] == null ? null : customer,

          'soldCartonsByGrade': soldCartonsByGrade,
          'unitPriceByGrade': unitPriceByGrade,
          'lineTotalByGrade': lineTotalByGrade,
          'soldEggsByGrade': soldEggsByGrade,
          'eggsPerCarton': eggsPerCarton,

          'totalAmount': totalAmount,
          'currency': 'XAF',

          // ✅ Paiements / recouvrements
          'amountPaid': amountPaid,
          'amountDue': amountDue,
          'paymentStatus': status, // UNPAID | PARTIAL | PAID
          'paid': paidBool, // compat
          'lastPaymentAt': amountPaid > 0 ? nowTs : null,
          'paidAt': paidBool ? nowTs : null,
          'payments': amountPaid > 0
              ? [
            {
              'amount': amountPaid,
              'at': nowTs,
              'method': 'INITIAL',
              'note': 'Paiement à la vente',
            }
          ]
              : [],

          'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          'createdAt': nowTs,
          'updatedAt': nowTs,
          'source': 'mobile_app',
        });

        tx.set(depotStockRef, {
          'kind': 'DEPOT',
          'locationType': 'DEPOT',
          'locationId': widget.depotId,
          'refId': widget.depotId,
          'goodByGrade': newDepotGood,
          'eggsByGrade': newDepotGood,
          'goodTotalEggs': newDepotGood.values.fold<int>(0, (a, b) => a + b),
          'updatedAt': nowTs,
        }, SetOptions(merge: true));
      });

      setState(() => _message = "Vente enregistrée ✅");

      // reset
      for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
        _cartonsCtrls[g]!.text = "0";
        _unitPriceCtrls[g]!.text = "0";
      }
      _noteCtrl.clear();
      _takePaymentNow = false;
      _paidNowCtrl.text = "0";
    } catch (e) {
      setState(() => _message = "Erreur : ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _inputRow({
    required String grade,
    required int eggsAvail,
  }) {
    final cartonsAvail = _availableCartons(eggsAvail);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_gradeFr(grade), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_remainderInfo(eggsAvail), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cartonsCtrls[grade],
                    enabled: !_loading,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Cartons à vendre (max $cartonsAvail)",
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unitPriceCtrls[grade],
                    enabled: !_loading,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Prix unitaire / carton (XAF)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Total ligne: ${_lineTotal(grade)} XAF",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final farmRef = _db.collection('farms').doc(widget.farmId);
    final depotStockRef = farmRef.collection('stocks_eggs').doc("DEPOT_${widget.depotId}");
    final customersQuery = farmRef.collection('customers').where('active', isEqualTo: true).orderBy('name');

    final total = _grandTotal();
    final paidNow = _takePaymentNow ? _parse(_paidNowCtrl) : 0;
    final paidNowClamped = paidNow > total ? total : paidNow;
    final dueNow = total - paidNowClamped;

    return Scaffold(
      appBar: AppBar(
        title: Text("Vente — ${widget.depotName}"),
        actions: [
          IconButton(
            tooltip: "Clients",
            icon: const Icon(Icons.people),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ClientsScreen(farmId: widget.farmId)));
            },
          ),
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
            // Client dropdown
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: customersQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text("Erreur clients: ${snap.error}", style: const TextStyle(color: Colors.red));
                }
                final docs = snap.data?.docs ?? [];

                return DropdownButtonFormField<String>(
                  value: _selectedCustomerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Client (optionnel)",
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text("— Client comptant / non renseigné —"),
                    ),
                    ...docs.map((d) {
                      final name = (d.data()['name'] ?? d.id).toString();
                      return DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(name),
                      );
                    }),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) {
                    if (v == null) {
                      setState(() {
                        _selectedCustomerId = null;
                        _selectedCustomerName = null;
                      });
                      return;
                    }
                    final doc = docs.firstWhere((x) => x.id == v);
                    setState(() {
                      _selectedCustomerId = v;
                      _selectedCustomerName = (doc.data()['name'] ?? doc.id).toString();
                    });
                  },
                );
              },
            ),

            const SizedBox(height: 12),

            // Stock dépôt + inputs
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: depotStockRef.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text("Erreur stock: ${snap.error}", style: const TextStyle(color: Colors.red));
                }
                if (!snap.hasData) return const LinearProgressIndicator();

                final data = snap.data!.data() ?? <String, dynamic>{};
                final eggsByGrade = _readGoodByGrade(data);

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (eggsByGrade.toString() != _depotEggsByGrade.toString()) {
                    setState(() => _depotEggsByGrade = eggsByGrade);
                  }
                });

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text("Stock disponible (cartons entiers)"),
                        subtitle: Text(
                          "Petit: ${_availableCartons(eggsByGrade['SMALL'] ?? 0)} • "
                              "Moyen: ${_availableCartons(eggsByGrade['MEDIUM'] ?? 0)} • "
                              "Gros: ${_availableCartons(eggsByGrade['LARGE'] ?? 0)} • "
                              "Très gros: ${_availableCartons(eggsByGrade['XL'] ?? 0)}",
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _inputRow(grade: 'SMALL', eggsAvail: eggsByGrade['SMALL'] ?? 0),
                    _inputRow(grade: 'MEDIUM', eggsAvail: eggsByGrade['MEDIUM'] ?? 0),
                    _inputRow(grade: 'LARGE', eggsAvail: eggsByGrade['LARGE'] ?? 0),
                    _inputRow(grade: 'XL', eggsAvail: eggsByGrade['XL'] ?? 0),
                  ],
                );
              },
            ),

            const Divider(height: 28),

            // Paiement
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Encaisser maintenant ?"),
                      subtitle: const Text("Cocher pour enregistrer un paiement initial (partiel ou total)."),
                      value: _takePaymentNow,
                      onChanged: _loading
                          ? null
                          : (v) {
                        setState(() {
                          _takePaymentNow = v;
                          if (v) {
                            // suggestion: préremplir avec total si c'était 0
                            if (_parse(_paidNowCtrl) <= 0 && _grandTotal() > 0) {
                              _paidNowCtrl.text = _grandTotal().toString();
                            }
                          } else {
                            _paidNowCtrl.text = "0";
                          }
                        });
                      },
                    ),
                    if (_takePaymentNow) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _paidNowCtrl,
                        enabled: !_loading,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Montant encaissé (XAF)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Reste à payer: $dueNow XAF",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _noteCtrl,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: "Note (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calculate),
                title: const Text("Montant total"),
                trailing: Text(
                  "$total XAF",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _saveSale,
              icon: const Icon(Icons.save),
              label: Text(_loading ? "Enregistrement..." : "Enregistrer la vente"),
            ),

            const SizedBox(height: 12),
            if (_message != null)
              Text(
                _message!,
                style: TextStyle(color: _message!.startsWith("Erreur") ? Colors.red : Colors.green),
              ),
          ],
        ),
      ),
    );
  }
}
