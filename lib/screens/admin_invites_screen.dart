import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AdminInvitesScreen extends StatefulWidget {
  const AdminInvitesScreen({super.key});

  @override
  State<AdminInvitesScreen> createState() => _AdminInvitesScreenState();
}

class _AdminInvitesScreenState extends State<AdminInvitesScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const String farmId = 'farm_nkoteng';

  String _asStr(dynamic v) => (v ?? '').toString();
  bool _asBool(dynamic v) => v == true;

  Future<void> _openCreate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _InviteForm()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _db.collection('invites').orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Invitations"),
        actions: [
          IconButton(
            tooltip: "Créer une invitation",
            icon: const Icon(Icons.add),
            onPressed: _openCreate,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text("Erreur: ${snap.error}"));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("Aucune invitation. Clique sur + pour en créer."));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();

              final email = _asStr(data['email']);
              final role = _asStr(data['role']);
              final active = _asBool(data['active']);
              final used = _asBool(data['used']);
              final usedByUid = _asStr(data['usedByUid']);
              final f = _asStr(data['farmId']);

              final statusText = used ? "Utilisée" : "En attente";
              final statusColor = used ? Colors.grey : Colors.green;

              return Card(
                child: ListTile(
                  leading: Icon(used ? Icons.mark_email_read : Icons.mark_email_unread, color: statusColor),
                  title: Text(email, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    "Rôle: $role • Farm: $f\n"
                        "Actif: ${active ? "Oui" : "Non"} • Statut: $statusText"
                        "${used && usedByUid.isNotEmpty ? "\nUtilisée par: $usedByUid" : ""}",
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text("Supprimer"),
                            content: Text("Supprimer l’invitation de $email ?"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Supprimer")),
                            ],
                          ),
                        );
                        if (ok == true) await d.reference.delete();
                      } else if (v == 'toggle') {
                        await d.reference.set({'active': !active, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'toggle', child: Text(active ? "Désactiver" : "Activer")),
                      const PopupMenuItem(value: 'delete', child: Text("Supprimer")),
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

class _InviteForm extends StatefulWidget {
  const _InviteForm();

  @override
  State<_InviteForm> createState() => _InviteFormState();
}

class _InviteFormState extends State<_InviteForm> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const String farmId = 'farm_nkoteng';

  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  String _role = 'DEPOT';
  bool _active = true;

  bool _saving = false;
  String? _msg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool _roleAllowed(String r) => ['ADMIN', 'FERMIER', 'VETERINAIRE', 'DEPOT'].contains(r);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      final email = _emailCtrl.text.trim();
      final displayName = _nameCtrl.text.trim();

      if (email.isEmpty || !email.contains('@')) throw Exception("Email invalide.");
      if (!_roleAllowed(_role)) throw Exception("Rôle invalide.");

      final emailLower = email.toLowerCase();

      // Empêcher doublon invite active non utilisée pour le même email
      final existing = await _db
          .collection('invites')
          .where('emailLower', isEqualTo: emailLower)
          .where('used', isEqualTo: false)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        throw Exception("Une invitation non utilisée existe déjà pour cet email.");
      }

      await _db.collection('invites').add({
        'email': email,
        'emailLower': emailLower,
        'displayName': displayName.isEmpty ? null : displayName,
        'role': _role,
        'active': _active,
        'farmId': farmId,
        'used': false,
        'usedAt': null,
        'usedByUid': null,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': _auth.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => _msg = "Erreur: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nouvelle invitation")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _emailCtrl,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "Email (obligatoire)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: "Nom affiché (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(
                labelText: "Rôle",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'ADMIN', child: Text("ADMIN")),
                DropdownMenuItem(value: 'FERMIER', child: Text("FERMIER")),
                DropdownMenuItem(value: 'VETERINAIRE', child: Text("VETERINAIRE")),
                DropdownMenuItem(value: 'DEPOT', child: Text("DEPOT")),
              ],
              onChanged: _saving ? null : (v) => setState(() => _role = v ?? 'DEPOT'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _active,
              onChanged: _saving ? null : (v) => setState(() => _active = v),
              title: const Text("Actif"),
              subtitle: const Text("Si inactif, l’invitation ne donnera pas accès."),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? "Enregistrement..." : "Créer l’invitation"),
            ),
            const SizedBox(height: 12),
            if (_msg != null) Text(_msg!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
