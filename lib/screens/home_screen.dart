import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import 'admin_users_screen.dart';
import 'admin_invites_screen.dart';
import 'buildings_screen.dart';
import 'clients_screen.dart';
import 'depots_screen.dart';
import 'farm_stock_screen.dart';
import 'egg_transfer_farm_to_depot_screen.dart';

class HomeScreen extends StatelessWidget {
  final UserProfile profile;
  const HomeScreen({super.key, required this.profile});

  void _go(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

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

  @override
  Widget build(BuildContext context) {
    final farmId = profile.farmId; // farm_nkoteng

    final items = <_MenuItem>[
      // ✅ Bâtiments (FERMIER/VETO/ADMIN)
      if (profile.isAdmin || profile.isFarmer || profile.isVet)
        _MenuItem(
          title: 'Bâtiments',
          subtitle: 'Lots actifs, rapports journaliers, transferts',
          icon: Icons.home_work,
          onTap: () => _go(context, const BuildingsScreen()),
        ),

      // ✅ Dépôts (DEPOT/ADMIN)
      if (profile.isAdmin || profile.isDepot)
        _MenuItem(
          title: 'Dépôts',
          subtitle: 'Réception, ventes, historique, recouvrements',
          icon: Icons.store,
          onTap: () => _go(context, DepotsScreen(farmId: farmId)),
        ),

      // ✅ Clients (DEPOT/ADMIN)
      if (profile.isAdmin || profile.isDepot)
        _MenuItem(
          title: 'Clients',
          subtitle: 'Créer / modifier / supprimer',
          icon: Icons.people,
          onTap: () => _go(context, ClientsScreen(farmId: farmId)),
        ),

      // ✅ Stock ferme (FERMIER/VETO/ADMIN)
      if (profile.isAdmin || profile.isFarmer || profile.isVet)
        _MenuItem(
          title: 'Stock ferme (oeufs)',
          subtitle: 'FARM_GLOBAL + calcul bâtiments',
          icon: Icons.egg_alt,
          onTap: () => _go(context, FarmStockScreen(farmId: farmId)),
        ),

      // ✅ Transfert ferme → dépôt (FERMIER/VETO/ADMIN)
      if (profile.isAdmin || profile.isFarmer || profile.isVet)
        _MenuItem(
          title: 'Transfert ferme → dépôt',
          subtitle: 'Par carton (stock conservé en oeufs)',
          icon: Icons.swap_horiz,
          onTap: () => _go(context, EggTransferFarmToDepotScreen(farmId: farmId)),
        ),

      // ✅ Admin
      if (profile.isAdmin)
        _MenuItem(
          title: 'Admin - Utilisateurs',
          subtitle: 'Profils farms/farm_nkoteng/users',
          icon: Icons.admin_panel_settings,
          onTap: () => _go(context, const AdminUsersScreen()),
        ),

      if (profile.isAdmin)
        _MenuItem(
          title: 'Admin - Invitations',
          subtitle: 'Création / suivi des invitations',
          icon: Icons.mark_email_unread,
          onTap: () => _go(context, const AdminInvitesScreen()),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nkoteng Farm App'),
        actions: [
          IconButton(
            tooltip: 'Déconnexion',
            onPressed: () async => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.person)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName.isNotEmpty ? profile.displayName : 'Utilisateur',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(profile.email),
                        const SizedBox(height: 8),
                        Chip(
                          label: Text(profile.role),
                          backgroundColor: _roleColor(profile.role).withOpacity(0.12),
                          side: BorderSide(color: _roleColor(profile.role).withOpacity(0.5)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...items.map((e) => Card(
            child: ListTile(
              leading: Icon(e.icon),
              title: Text(e.title),
              subtitle: Text(e.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: e.onTap,
            ),
          )),
        ],
      ),
    );
  }
}

class _MenuItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  _MenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}
