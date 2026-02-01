import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';

import 'admin_invites_screen.dart';
import 'admin_users_screen.dart';
import 'buildings_screen.dart';
import 'clients_screen.dart';
import 'depots_screen.dart';
import 'egg_transfer_farm_to_depot_screen.dart';
import 'egg_transfers_history_screen.dart';
import 'farm_stock_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _go(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final profile = UserProfileScope.of(context);

    final items = <_MenuItem>[
      // ======== FERME (FERMIER/VET/ADMIN) ========
      if (profile.isFarmer || profile.isVet || profile.isAdmin)
        _MenuItem(
          title: 'Bâtiments & Rapports',
          subtitle: 'Bâtiments, saisie journalière, historique',
          icon: Icons.home_work,
          onTap: () => _go(context, const BuildingsScreen()),
        ),

      if (profile.isFarmer || profile.isVet || profile.isAdmin)
        _MenuItem(
          title: 'Stock ferme (œufs)',
          subtitle: 'Stock global ferme (FARM_GLOBAL)',
          icon: Icons.egg_alt,
          onTap: () => _go(context, FarmStockScreen(farmId: profile.farmId)),
        ),

      if (profile.isFarmer || profile.isVet || profile.isAdmin)
        _MenuItem(
          title: 'Transfert ferme → dépôt',
          subtitle: 'Transfert par carton (stock en œufs)',
          icon: Icons.swap_horiz,
          onTap: () => _go(context, EggTransferFarmToDepotScreen(farmId: profile.farmId)),
        ),

      if (profile.isFarmer || profile.isVet || profile.isAdmin)
        _MenuItem(
          title: 'Historique transferts œufs',
          subtitle: 'Transferts ferme → dépôt',
          icon: Icons.list_alt,
          onTap: () => _go(context, EggTransfersHistoryScreen(farmId: profile.farmId)),
        ),

      // ======== DEPOT (DEPOT/ADMIN) ========
      if (profile.isDepot || profile.isAdmin)
        _MenuItem(
          title: 'Dépôts',
          subtitle: 'Réception, ventes, recouvrements',
          icon: Icons.store,
          onTap: () => _go(context, DepotsScreen(farmId: profile.farmId)),
        ),

      if (profile.isDepot || profile.isAdmin)
        _MenuItem(
          title: 'Clients',
          subtitle: 'Gestion des clients',
          icon: Icons.people,
          onTap: () => _go(context, ClientsScreen(farmId: profile.farmId)),
        ),

      // ======== ADMIN ========
      if (profile.isAdmin)
        _MenuItem(
          title: 'Admin - Utilisateurs',
          subtitle: 'Gestion des profils (roles/active)',
          icon: Icons.admin_panel_settings,
          onTap: () => _go(context, const AdminUsersScreen()),
        ),
      if (profile.isAdmin)
        _MenuItem(
          title: 'Admin - Invitations',
          subtitle: 'Invitations / provisioning',
          icon: Icons.mark_email_read,
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
          _ProfileHeader(profile: profile),
          const SizedBox(height: 12),
          ...items.map((e) => _MenuTile(item: e)),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  const _ProfileHeader({required this.profile});

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
    final color = _roleColor(profile.role);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.12),
              child: Icon(Icons.person, color: color),
            ),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: -6,
                    children: [
                      Chip(
                        label: Text(profile.role),
                        backgroundColor: color.withOpacity(0.12),
                        side: BorderSide(color: color.withOpacity(0.5)),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        label: Text(profile.active ? 'Actif' : 'Inactif'),
                        backgroundColor:
                        (profile.active ? Colors.green : Colors.grey).withOpacity(0.12),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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

class _MenuTile extends StatelessWidget {
  final _MenuItem item;
  const _MenuTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(item.icon),
        title: Text(item.title),
        subtitle: Text(item.subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: item.onTap,
      ),
    );
  }
}
