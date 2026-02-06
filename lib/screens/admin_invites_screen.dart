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

  // collection choisie (farm ou root legacy)
  CollectionReference<Map<String, dynamic>>? _invitesRef;
  bool _checkingInvitesPath = true;
  String? _invitesPathMsg;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _checkingInvitesPath = false;
        _invitesRef = null;
        _invitesPathMsg = "Non connecté.";
      });
      return;
    }

    // 1) vérifier rôle ADMIN/active via farms/farm_nkoteng/users/{uid}
    try {
      final profileSnap =
      await _db.collection('farms').doc(farmId).collection('users').doc(uid).get();
      final p = profileSnap.data() ?? <String, dynamic>{};
      final role = _asStr(p['role']).toUpperCase();
      final active = _asBool(p['active']);

      if (!active || role != 'ADMIN') {
        setState(() {
          _checkingInvitesPath = false;
          _invitesRef = null;
          _invitesPathMsg = "Accès refusé (ADMIN uniquement).";
        });
        return;
      }
    } catch (e) {
      setState(() {
        _checkingInvitesPath = false;
        _invitesRef = null;
        _invitesPathMsg = "Erreur profil: $e";
      });
      return;
    }

    // 2) essayer farms/farm_nkoteng/invites, sinon fallback root /invites (legacy)
    final farmInvites = _db.collection('farms').doc(farmId).collection('invites');
    try {
      // test lecture (server) – si rules bloquent, on fallback.
      await farmInvites.limit(1).get(const GetOptions(source: Source.server));
      setState(() {
        _invitesRef = farmInvites;
        _checkingInvitesPath = false;
        _invitesPathMsg = "Chemin: farms/$farmId/invites";
      });
      return;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // fallback root
      } else {
        // autre erreur => on tente quand même fallback root pour éviter écran vide.
      }
    } catch (_) {}

    setState(() {
      _invitesRef = _db.collection('invites');
      _checkingInvitesPath = false;
      _invitesPathMsg = "Chemin: /invites (legacy)";
    });
  }

  Future<void> _openCreate() async {
    final ref = _invitesRef;
    if (ref == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _InviteForm(invitesRef: ref)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingInvitesPath) {
      return Scaffold(
        appBar: AppBar(title: const Text("Invitations")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final ref = _invitesRef;
    if (ref == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Invitations")),
        body: Center(
          child: Text(_invitesPathMsg ?? "Accès indisponible."),
        ),
      );
    }

    final q = ref.orderBy('createdAt', descending: true);

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

          final docs = snap.data!.docs;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (_invitesPathMsg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _invitesPathMsg!,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              if (docs.isEmpty)
                const Center(child: Text("Aucune invitation.")),
              for (final d in docs) _InviteTile(data: d.data(), id: d.id),
            ],
          );
        },
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String id;

  const _InviteTile({required this.data, required this.id});

  String _asStr(dynamic v) => (v ?? '').toString();
  bool _asBool(dynamic v) => v == true;

  @override
  Widget build(BuildContext context) {
    final email = _asStr(data['email']);
    final role = _asStr(data['role']);
    final active = _asBool(data['active']);
    final used = _asBool(data['used']);
    final displayName = _asStr(data['displayName']);

    return Card(
      child: ListTile(
        title: Text(displayName.isEmpty ? email : "$displayName — $email"),
        subtitle: Text("Rôle: $role • Actif: ${active ? "Oui" : "Non"} • Utilisée: ${used ? "Oui" : "Non"}"),
        trailing: Text(id.substring(0, id.length > 6 ? 6 : id.length)),
      ),
    );
  }
}

class _InviteForm extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> invitesRef;

  const _InviteForm({required this.invitesRef});

  @override
  State<_InviteForm> createState() => _InviteFormState();
}

class _InviteFormState extends State<_InviteForm> {
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
      final existing = await widget.invitesRef
          .where('emailLower', isEqualTo: emailLower)
          .where('used', isEqualTo: false)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        throw Exception("Une invitation non utilisée existe déjà pour cet email.");
      }

      await widget.invitesRef.add({
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
