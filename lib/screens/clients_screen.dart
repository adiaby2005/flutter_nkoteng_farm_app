import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ClientsScreen extends StatelessWidget {
  final String farmId;
  const ClientsScreen({super.key, required this.farmId});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final q = db.collection('farms').doc(farmId).collection('customers').orderBy('name');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Clients"),
        actions: [
          IconButton(
            tooltip: "Ajouter",
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ClientFormScreen(farmId: farmId),
                ),
              );
            },
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text("Erreur: ${snap.error}"));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("Aucun client. Ajoute-en un avec +"));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              final name = (data['name'] ?? d.id).toString();
              final phone = (data['phone'] ?? '').toString();

              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(name),
                subtitle: phone.isEmpty ? null : Text(phone),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _ClientFormScreen(
                        farmId: farmId,
                        customerId: d.id,
                        initialName: name,
                        initialPhone: phone,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ClientFormScreen extends StatefulWidget {
  final String farmId;
  final String? customerId;
  final String? initialName;
  final String? initialPhone;

  const _ClientFormScreen({
    required this.farmId,
    this.customerId,
    this.initialName,
    this.initialPhone,
  });

  @override
  State<_ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<_ClientFormScreen> {
  final _db = FirebaseFirestore.instance;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;

  bool _saving = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? "");
    _phoneCtrl = TextEditingController(text: widget.initialPhone ?? "");
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();

      if (name.isEmpty) throw Exception("Nom obligatoire.");

      final col = _db.collection('farms').doc(widget.farmId).collection('customers');

      if (widget.customerId == null) {
        await col.add({
          'name': name,
          'phone': phone.isEmpty ? null : phone,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await col.doc(widget.customerId).set({
          'name': name,
          'phone': phone.isEmpty ? null : phone,
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => _msg = "Erreur: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customerId != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? "Modifier client" : "Nouveau client")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _nameCtrl,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: "Nom du client",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Téléphone (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? "Enregistrement..." : "Enregistrer"),
            ),
            const SizedBox(height: 12),
            if (_msg != null) Text(_msg!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
