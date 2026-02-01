import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EggTransferDetailScreen extends StatelessWidget {
  final String farmId;
  final String movementId;

  const EggTransferDetailScreen({
    super.key,
    required this.farmId,
    required this.movementId,
  });

  String _gradeFr(String g) {
    switch (g) {
      case 'SMALL':
        return 'Petit';
      case 'MEDIUM':
        return 'Moyen';
      case 'LARGE':
        return 'Gros';
      case 'XL':
        return 'Très gros';
      default:
        return g;
    }
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

  String _dateTimeText(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      String two(int n) => n.toString().padLeft(2, '0');
      return "${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}";
    }
    return "-";
  }

  String _label(Map<String, dynamic> m, String fallback) {
    final name = (m['name'] ?? m['id'] ?? '').toString().trim();
    final kind = (m['kind'] ?? '').toString().trim();
    if (name.isEmpty) return fallback;
    if (kind.isEmpty) return name;
    return "$kind : $name";
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('farms')
        .doc(farmId)
        .collection('egg_movements')
        .doc(movementId);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Détail transfert"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text("Erreur : ${snap.error}", style: const TextStyle(color: Colors.red)),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.data!.exists) {
              return const Center(child: Text("Transfert introuvable"));
            }

            final d = snap.data!.data() ?? <String, dynamic>{};

            final date = (d['date'] ?? '').toString();
            final createdAt = _dateTimeText(d['createdAt']);

            final from = _asMap(d['from']);
            final to = _asMap(d['to']);

            final goodByGrade = _asMap(d['goodOutByGrade']);
            final goodTotal = _asInt(d['goodOutTotal']);

            final broken = _asMap(d['brokenOut']);
            final brokenTotal = _asInt(broken['totalBrokenEggs']);
            final brokenAlv = _asInt(broken['brokenAlveoles']);
            final brokenIso = _asInt(broken['brokenIsolated']);

            final note = (d['note'] ?? '').toString().trim();

            return ListView(
              children: [
                Text("Date : $date", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 6),
                Text("Enregistré : $createdAt", style: const TextStyle(color: Colors.grey)),

                const SizedBox(height: 12),

                Row(
                  children: [
                    _pill("Bons: $goodTotal"),
                    const SizedBox(width: 8),
                    _pill("Casses: $brokenTotal"),
                  ],
                ),

                const Divider(height: 28),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload),
                  title: const Text("Origine"),
                  subtitle: Text(_label(from, "Origine")),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download),
                  title: const Text("Destination"),
                  subtitle: Text(_label(to, "Destination")),
                ),

                const Divider(height: 28),

                Text("Bons œufs (détail)", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),

                for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL'])
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.egg_alt_outlined),
                      title: Text(_gradeFr(g)),
                      trailing: Text("${_asInt(goodByGrade[g])}"),
                    ),
                  ),

                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.egg_alt_outlined),
                    title: const Text("Total bons œufs"),
                    trailing: Text("$goodTotal", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),

                const Divider(height: 28),

                Text("Casses", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.broken_image_outlined),
                    title: const Text("Total casses"),
                    trailing: Text(
                      "$brokenTotal",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.broken_image_outlined),
                    title: const Text("Détail casses"),
                    subtitle: Text("Alvéoles: $brokenAlv • Isolés: $brokenIso"),
                  ),
                ),

                if (note.isNotEmpty) ...[
                  const Divider(height: 28),
                  Text("Note", style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(note),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
