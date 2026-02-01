import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DepotFormScreen extends StatefulWidget {
  final String? depotId; // null => create
  const DepotFormScreen({super.key, this.depotId});

  @override
  State<DepotFormScreen> createState() => _DepotFormScreenState();
}

class _DepotFormScreenState extends State<DepotFormScreen> {
  static const String farmId = 'farm_nkoteng';
  final db = FirebaseFirestore.instance;

  bool _loading = false;
  String? _message;

  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  bool _active = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIfEdit() async {
    if (widget.depotId == null) return;

    final ref = db.collection('farms').doc(farmId).collection('depots').doc(widget.depotId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data() ?? {};
    _nameCtrl.text = (data['name'] ?? '').toString();
    _locationCtrl.text = (data['location'] ?? '').toString();
    _active = (data['active'] ?? true) == true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _loadIfEdit();
        if (mounted) setState(() {});
      } catch (_) {}
    });
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final name = _nameCtrl.text.trim();
      if (name.isEmpty) throw Exception("Nom du dépôt obligatoire.");

      final ref = (widget.depotId == null)
          ? db.collection('farms').doc(farmId).collection('depots').doc()
          : db.collection('farms').doc(farmId).collection('depots').doc(widget.depotId);

      final now = FieldValue.serverTimestamp();

      await ref.set({
        'name': name,
        'location': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'active': _active,
        'updatedAt': now,
        if (widget.depotId == null) 'createdAt': now,
      }, SetOptions(merge: true));

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _message = "Erreur : ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.depotId != null;
    final msg = _message;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Modifier dépôt' : 'Nouveau dépôt')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _nameCtrl,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: "Nom du dépôt",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: "Localisation (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _active,
              onChanged: _loading ? null : (v) => setState(() => _active = v),
              title: const Text("Actif"),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_loading ? "Enregistrement..." : "Enregistrer"),
            ),
            const SizedBox(height: 12),
            if (msg != null)
              Text(
                msg,
                style: TextStyle(color: msg.startsWith('Erreur') ? Colors.red : Colors.green),
              ),
          ],
        ),
      ),
    );
  }
}
