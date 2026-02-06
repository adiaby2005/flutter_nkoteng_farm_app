import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/subject_lot_service.dart';

class SubjectTransferStrictScreen extends StatefulWidget {
  final String fromBuildingId;
  final String fromBuildingName;

  const SubjectTransferStrictScreen({
    super.key,
    required this.fromBuildingId,
    required this.fromBuildingName,
  });

  @override
  State<SubjectTransferStrictScreen> createState() => _SubjectTransferStrictScreenState();
}

class _SubjectTransferStrictScreenState extends State<SubjectTransferStrictScreen> {
  final _qtyCtrl = TextEditingController(text: '0');
  String? _toBuildingId;
  String? _toBuildingName;

  bool _saving = false;

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green : Colors.red),
    );
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final toId = _toBuildingId;
    if (toId == null || toId.isEmpty) {
      _snack("Choisir le bâtiment destination", false);
      return;
    }

    setState(() => _saving = true);
    try {
      await SubjectLotService.transferStrict(
        fromBuildingId: widget.fromBuildingId,
        toBuildingId: toId,
        qty: _i(_qtyCtrl),
      );
      _snack("✅ Transfert STRICT effectué", true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString(), false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmRef = FirebaseFirestore.instance.collection('farms').doc(SubjectLotService.farmId);

    return Scaffold(
      appBar: AppBar(
        title: Text("Transfert STRICT - ${widget.fromBuildingName}"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Quantité à transférer",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: farmRef.collection('buildings').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();

              final buildings = snap.data!.docs
                  .where((b) => b.id != widget.fromBuildingId)
                  .toList();

              return DropdownButtonFormField<String>(
                value: _toBuildingId,
                decoration: const InputDecoration(
                  labelText: "Bâtiment destination",
                  border: OutlineInputBorder(),
                ),
                items: buildings.map((b) {
                  final name = (b.data()['name'] ?? '').toString().trim();
                  return DropdownMenuItem(
                    value: b.id,
                    child: Text(name.isEmpty ? b.id : name),
                  );
                }).toList(),
                onChanged: _saving
                    ? null
                    : (v) {
                  setState(() {
                    _toBuildingId = v;
                    final b = buildings.where((e) => e.id == v).toList();
                    _toBuildingName = b.isEmpty ? null : (b.first.data()['name'] ?? '').toString();
                  });
                },
              );
            },
          ),

          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.swap_horiz),
            label: Text(_saving ? "Transfert..." : "Transférer (STRICT)"),
          ),
          const SizedBox(height: 8),
          const Text(
            "Règle STRICT: la destination doit être vide (aucun lot actif).",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
