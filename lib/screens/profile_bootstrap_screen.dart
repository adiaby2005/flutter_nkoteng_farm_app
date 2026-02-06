import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import 'home_screen.dart';

const String kFarmId = 'farm_nkoteng';

class ProfileBootstrapScreen extends StatelessWidget {
  const ProfileBootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Session absente. Veuillez vous reconnecter.')),
      );
    }

    final docRef = FirebaseFirestore.instance
        .collection('farms')
        .doc(kFarmId)
        .collection('users')
        .doc(user.uid);

    debugPrint('AUTH uid=${user.uid} email=${user.email}');
    debugPrint('PROFILE DOC PATH = ${docRef.path}'); // farms/farm_nkoteng/users/{uid}

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snap.hasError) {
          return _ErrorScreen(
            title: 'Erreur profil Firestore',
            message: snap.error.toString(),
            path: docRef.path,
          );
        }

        final data = snap.data?.data();
        if (data == null) {
          return ContactAdminScreen(
            email: user.email ?? '',
            reason: "Votre compte est authentifié mais aucun profil n'est défini.\n\n"
                "L'admin doit créer:\n"
                "farms/$kFarmId/users/${user.uid}\n"
                "avec role + active=true.",
          );
        }

        final profile = UserProfile.fromMap(uid: user.uid, farmId: kFarmId, map: data);

        if (!profile.active) {
          return ContactAdminScreen(
            email: profile.email.isEmpty ? (user.email ?? '') : profile.email,
            reason: "Votre compte est désactivé (active=false). Contactez l'administrateur.",
          );
        }

        return HomeScreen(profile: profile);
      },
    );
  }
}

class ContactAdminScreen extends StatelessWidget {
  final String email;
  final String reason;

  const ContactAdminScreen({super.key, required this.email, required this.reason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accès non autorisé')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.lock, size: 64),
            const SizedBox(height: 12),
            Text(reason, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.email),
                title: const Text('Compte'),
                subtitle: Text(email.isEmpty ? '(email inconnu)' : email),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () async => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String title;
  final String message;
  final String path;

  const _ErrorScreen({required this.title, required this.message, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('Path: $path'),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    );
  }
}
