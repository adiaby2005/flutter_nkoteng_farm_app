import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const String kFarmId = 'farm_nkoteng';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _searchCtrl = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _db.collection('farms').doc(kFarmId).collection('users').doc(uid);
  }

  CollectionReference<Map<String, dynamic>> get _usersCol {
    return _db.collection('farms').doc(kFarmId).collection('users');
  }

  String _asStr(dynamic v) => (v ?? '').toString().trim();
  bool _asBool(dynamic v) => v == true;

  bool _isMe(String uid) => _auth.currentUser?.uid == uid;

  Color _roleColor(String role) {
    switch (role) {
      case 'ADMIN':
        return Colors.red;
      case 'VETERINAIRE':
        return Colors.teal;
      case 'DEPOT':
        return Colors.indigo;
      case 'FERMIER':
      default:
        return Colors.green;
    }
  }

  Future<void> _editUser(BuildContext context, String uid,
      Map<String, dynamic> currentData) async {
    final displayNameCtrl =
    TextEditingController(text: _asStr(currentData['displayName']));
    final email = _asStr(currentData['email']);
    String role = _asStr(currentData['role']).isEmpty ? 'FERMIER' : _asStr(currentData['role']);
    bool active = _asBool(currentData['active']);

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Modifier profil'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (email.isNotEmpty)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.email),
                    title: const Text('Email'),
                    subtitle: Text(email),
                  ),
                TextField(
                  controller: displayNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom affiché (displayName)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  items: const [
                    DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
                    DropdownMenuItem(value: 'FERMIER', child: Text('FERMIER')),
                    DropdownMenuItem(
                        value: 'VETERINAIRE', child: Text('VETERINAIRE')),
                    DropdownMenuItem(value: 'DEPOT', child: Text('DEPOT')),
                  ],
                  onChanged: (v) => role = v ?? role,
                  decoration: const InputDecoration(labelText: 'Rôle'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Compte actif'),
                  value: active,
                  onChanged: (v) => active = v,
                ),
                if (_isMe(uid))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      "Note: tu modifies ton propre compte.",
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );

    if (res != true) return;

    await _userDoc(uid).update({
      'displayName': displayNameCtrl.text.trim(),
      'role': role,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil mis à jour')),
    );
  }

  Future<void> _resetPassword(BuildContext context, String email) async {
    if (email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email manquant dans le profil.")),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réinitialiser le mot de passe'),
        content: Text(
          "Envoyer un email de réinitialisation à :\n\n$email\n\n"
              "Le mot de passe ne sera pas changé automatiquement : l'utilisateur doit suivre le lien reçu.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email de reset envoyé')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec envoi reset: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Utilisateurs'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Rechercher (email, nom, rôle, uid)...',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = "");
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _usersCol.orderBy('role').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Erreur: ${snap.error}'),
                  );
                }

                final docs = snap.data?.docs ?? [];
                final filtered = docs.where((d) {
                  if (_query.isEmpty) return true;
                  final m = d.data();
                  final hay = [
                    d.id,
                    _asStr(m['email']),
                    _asStr(m['displayName']),
                    _asStr(m['role']),
                    _asBool(m['active']) ? 'active' : 'inactive',
                  ].join(' ').toLowerCase();
                  return hay.contains(_query);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('Aucun utilisateur'));
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final doc = filtered[i];
                    final data = doc.data();
                    final uid = doc.id;

                    final email = _asStr(data['email']);
                    final displayName = _asStr(data['displayName']);
                    final role = _asStr(data['role']).isEmpty ? 'FERMIER' : _asStr(data['role']);
                    final active = _asBool(data['active']);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _roleColor(role).withOpacity(0.15),
                        child: Icon(
                          Icons.person,
                          color: _roleColor(role),
                        ),
                      ),
                      title: Text(
                        displayName.isNotEmpty ? displayName : '(Sans nom)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (email.isNotEmpty)
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: -6,
                            children: [
                              Chip(
                                label: Text(role),
                                backgroundColor:
                                _roleColor(role).withOpacity(0.12),
                                side: BorderSide(
                                    color: _roleColor(role).withOpacity(0.5)),
                                visualDensity: VisualDensity.compact,
                              ),
                              Chip(
                                label: Text(active ? 'Actif' : 'Inactif'),
                                backgroundColor: (active
                                    ? Colors.green
                                    : Colors.grey)
                                    .withOpacity(0.12),
                                visualDensity: VisualDensity.compact,
                              ),
                              if (_isMe(uid))
                                Chip(
                                  label: const Text('Moi'),
                                  backgroundColor:
                                  Colors.orange.withOpacity(0.12),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await _editUser(context, uid, data);
                          } else if (value == 'reset') {
                            await _resetPassword(context, email);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Éditer'),
                          ),
                          const PopupMenuItem(
                            value: 'reset',
                            child: Text('Reset password'),
                          ),
                        ],
                      ),
                      onTap: () => _editUser(context, uid, data),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
