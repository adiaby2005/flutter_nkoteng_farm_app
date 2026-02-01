import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DepotRecoveriesScreen extends StatefulWidget {
  final String farmId;
  final String depotId;
  final String depotName;

  const DepotRecoveriesScreen({
    super.key,
    required this.farmId,
    required this.depotId,
    required this.depotName,
  });

  @override
  State<DepotRecoveriesScreen> createState() => _DepotRecoveriesScreenState();
}

class _DepotRecoveriesScreenState extends State<DepotRecoveriesScreen> {
  DateTimeRange? _range;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  String _iso(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  String _fmtRange(DateTimeRange r) => "${_iso(r.start)} → ${_iso(r.end)}";

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
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

  String _statusFrom(int total, int paid) {
    if (total <= 0) return 'UNPAID';
    if (paid <= 0) return 'UNPAID';
    if (paid >= total) return 'PAID';
    return 'PARTIAL';
  }

  (String label, Color bg, Color fg, Color border) _badgeStyle(String status) {
    switch (status) {
      case 'PAID':
        return ("Payé", Colors.green.shade100, Colors.green.shade800, Colors.green);
      case 'PARTIAL':
        return ("Partiel", Colors.blue.shade100, Colors.blue.shade800, Colors.blue);
      default:
        return ("Non payé", Colors.orange.shade100, Colors.orange.shade800, Colors.orange);
    }
  }

  Widget _badge(String status) {
    final s = _badgeStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: s.$2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.$4),
      ),
      child: Text(s.$1, style: TextStyle(fontWeight: FontWeight.bold, color: s.$3)),
    );
  }

  String _prettyErr(Object e) {
    if (e is FirebaseException) {
      final code = e.code;
      final msg = e.message ?? "";
      return "Firestore: $code ${msg.isEmpty ? '' : '— $msg'}";
    }
    return e.toString();
  }

  Future<void> _collectPayment({
    required DocumentReference<Map<String, dynamic>> ref,
    required int totalAmount,
    required int currentPaid,
  }) async {
    final remaining = totalAmount - currentPaid;
    if (remaining <= 0) return;

    final amountCtrl = TextEditingController(text: remaining.toString());
    final methodCtrl = TextEditingController(text: "CASH");
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Encaisser un paiement"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Reste à payer: $remaining XAF"),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Montant encaissé (XAF)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: methodCtrl,
                decoration: const InputDecoration(
                  labelText: "Méthode (ex: CASH, MOMO, OM)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: "Note (optionnel)",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Encaisser")),
          ],
        );
      },
    );

    if (ok != true) return;

    int amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) return;
    if (amount > remaining) amount = remaining;

    final method = methodCtrl.text.trim().isEmpty ? 'CASH' : methodCtrl.text.trim();
    final note = noteCtrl.text.trim();

    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};

        final total = _asInt(data['totalAmount']);
        final paid = _asInt(data['amountPaid']);
        final due = total - paid;

        if (total <= 0) throw Exception("Vente invalide: totalAmount manquant.");
        if (due <= 0) return;

        int toPay = amount;
        if (toPay > due) toPay = due;

        final newPaid = paid + toPay;
        final newDue = total - newPaid;
        final finalStatus = _statusFrom(total, newPaid);

        final nowServer = FieldValue.serverTimestamp();
        final nowClient = Timestamp.now(); // ✅ safe dans arrayUnion

        final paymentEntry = <String, dynamic>{
          'amount': toPay,
          'at': nowClient,
          'method': method,
        };
        if (note.isNotEmpty) paymentEntry['note'] = note;

        tx.set(ref, {
          'amountPaid': newPaid,
          'amountDue': newDue,
          'paymentStatus': finalStatus,
          'paid': (finalStatus == 'PAID'),
          'lastPaymentAt': nowServer,
          'paidAt': (finalStatus == 'PAID') ? nowServer : FieldValue.delete(),
          'updatedAt': nowServer,
          'payments': FieldValue.arrayUnion([paymentEntry]),
        }, SetOptions(merge: true));
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Paiement encaissé: $amount XAF ✅")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur: ${_prettyErr(e)}")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _range!;
    final startIso = _iso(range.start);
    final endIso = _iso(range.end);

    final farmRef = FirebaseFirestore.instance.collection('farms').doc(widget.farmId);

    // Récupérer les ventes du dépôt (période). Filtrage impayés/partiels côté UI.
    final q = farmRef
        .collection('egg_movements')
        .where('type', isEqualTo: 'SALE')
        .where('from.id', isEqualTo: widget.depotId)
        .where('date', isGreaterThanOrEqualTo: startIso)
        .where('date', isLessThanOrEqualTo: endIso)
        .orderBy('date', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text("Recouvrements — ${widget.depotName}"),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _pickRange,
            icon: const Icon(Icons.filter_alt),
            label: Text(_fmtRange(range)),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "Erreur: ${snap.error}\n\n"
                    "Si le message parle d’index, clique le lien fourni par Firebase Console et crée l’index.",
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final allDocs = snap.data!.docs;

          final docs = allDocs.where((d) {
            final data = d.data();
            final total = _asInt(data['totalAmount']);
            final paid = _asInt(data['amountPaid']);
            return paid < total;
          }).toList();

          if (docs.isEmpty) return const Center(child: Text("Aucun impayé/partiel sur la période."));

          int totalDue = 0;
          for (final d in docs) {
            final data = d.data();
            final total = _asInt(data['totalAmount']);
            final paid = _asInt(data['amountPaid']);
            totalDue += (total - paid);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: const Text("Reste à recouvrer (période)"),
                    subtitle: Text(_fmtRange(range)),
                    trailing: Text(
                      "$totalDue XAF",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
                );
              }

              final doc = docs[i - 1];
              final data = doc.data();

              final date = (data['date'] ?? '').toString();
              final total = _asInt(data['totalAmount']);
              final paid = _asInt(data['amountPaid']);
              final due = total - paid;
              final status = (data['paymentStatus'] ?? _statusFrom(total, paid)).toString();

              final customer = _asMap(data['customer']);
              final customerName = (customer['name'] ?? '').toString().trim();

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Reste: $due XAF",
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          _badge(status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text("Date: $date"),
                      if (customerName.isNotEmpty) Text("Client: $customerName"),
                      const SizedBox(height: 6),
                      Text("Total: $total • Payé: $paid"),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _collectPayment(
                            ref: doc.reference,
                            totalAmount: total,
                            currentPaid: paid,
                          ),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text("Encaisser (paiement partiel)"),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
