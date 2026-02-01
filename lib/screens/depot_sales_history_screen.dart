import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DepotSalesHistoryScreen extends StatefulWidget {
  final String farmId;
  final String depotId;
  final String depotName;

  const DepotSalesHistoryScreen({
    super.key,
    required this.farmId,
    required this.depotId,
    required this.depotName,
  });

  @override
  State<DepotSalesHistoryScreen> createState() => _DepotSalesHistoryScreenState();
}

class _DepotSalesHistoryScreenState extends State<DepotSalesHistoryScreen> {
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
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

  Widget _badge(String status) {
    Color border;
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'PAID':
        border = Colors.green;
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = "Payé";
        break;
      case 'PARTIAL':
        border = Colors.blue;
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        label = "Partiel";
        break;
      default:
        border = Colors.orange;
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        label = "Non payé";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _dateHeader(String dateIso) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, size: 18),
          const SizedBox(width: 8),
          Text(dateIso, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _range!;
    final startIso = _iso(range.start);
    final endIso = _iso(range.end);

    final farmRef = FirebaseFirestore.instance.collection('farms').doc(widget.farmId);

    final q = farmRef
        .collection('egg_movements')
        .where('type', isEqualTo: 'SALE')
        .where('from.id', isEqualTo: widget.depotId)
        .where('date', isGreaterThanOrEqualTo: startIso)
        .where('date', isLessThanOrEqualTo: endIso)
        .orderBy('date', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text("Ventes — ${widget.depotName}"),
        actions: [
          TextButton.icon(
            onPressed: _pickRange,
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

          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("Aucune vente sur la période."));

          String? lastDate;

          int totalPeriod = 0;
          int paidPeriod = 0;
          int unpaidPeriod = 0;
          int partialPeriod = 0;

          for (final d in docs) {
            final data = d.data();
            final total = _asInt(data['totalAmount']);
            final paid = _asInt(data['amountPaid']);
            final status = (data['paymentStatus'] ?? _statusFrom(total, paid)).toString();

            totalPeriod += total;
            if (status == 'PAID') paidPeriod += total;
            if (status == 'UNPAID') unpaidPeriod += total;
            if (status == 'PARTIAL') partialPeriod += total;
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.summarize),
                          title: const Text("Total période"),
                          subtitle: Text(_fmtRange(range)),
                          trailing: Text("$totalPeriod XAF", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const Divider(height: 0),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _badge('PAID'),
                              Text("$paidPeriod XAF", style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              _badge('PARTIAL'),
                              Text("$partialPeriod XAF", style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              _badge('UNPAID'),
                              Text("$unpaidPeriod XAF", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final d = docs[i - 1];
              final data = d.data();

              final date = (data['date'] ?? '').toString();
              final total = _asInt(data['totalAmount']);
              final paid = _asInt(data['amountPaid']);
              final due = _asInt(data['amountDue']);
              final status = (data['paymentStatus'] ?? _statusFrom(total, paid)).toString();

              final customer = _asMap(data['customer']);
              final customerName = (customer['name'] ?? '').toString().trim();

              final soldCartonsByGrade = _asMap(data['soldCartonsByGrade']);
              int gi(String k) => _asInt(soldCartonsByGrade[k]);

              final headerNeeded = (lastDate != date);
              lastDate = date;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (headerNeeded) ...[
                    const SizedBox(height: 10),
                    _dateHeader(date),
                    const SizedBox(height: 8),
                  ],
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.point_of_sale),
                      title: Text("$total XAF"),
                      subtitle: Text(
                        [
                          if (customerName.isNotEmpty) "Client: $customerName",
                          "Cartons — P:${gi('SMALL')} • M:${gi('MEDIUM')} • G:${gi('LARGE')} • TG:${gi('XL')}",
                          "Payé: $paid • Reste: $due",
                        ].join("\n"),
                      ),
                      trailing: _badge(status),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
