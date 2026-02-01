import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FarmStockScreen extends StatelessWidget {
  final String farmId;

  const FarmStockScreen({
    super.key,
    required this.farmId,
  });

  int _getInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  Map<String, int> _emptyGrades() => {
    'SMALL': 0,
    'MEDIUM': 0,
    'LARGE': 0,
    'XL': 0,
  };

  String _gradeFr(String g) {
    switch (g) {
      case 'SMALL':
        return 'Petit';
      case 'MEDIUM':
        return 'Moyen';
      case 'LARGE':
        return 'Gros';
      case 'XL':
        return 'Super gros';
      default:
        return g;
    }
  }

  Map<String, int> _readGrades(Map<String, dynamic> data, String key) {
    final raw = data[key];
    final m = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return {
      'SMALL': _getInt(m['SMALL']),
      'MEDIUM': _getInt(m['MEDIUM']),
      'LARGE': _getInt(m['LARGE']),
      'XL': _getInt(m['XL']),
    };
  }

  Map<String, int> _pickGoodByGrade(Map<String, dynamic> data) {
    // compat: certains docs utilisent goodByGrade, d'autres eggsByGrade
    final good = _readGrades(data, 'goodByGrade');
    final eggs = _readGrades(data, 'eggsByGrade');

    int pick(String g) {
      final v = good[g] ?? 0;
      if (v != 0) return v;
      return eggs[g] ?? 0;
    }

    return {
      'SMALL': pick('SMALL'),
      'MEDIUM': pick('MEDIUM'),
      'LARGE': pick('LARGE'),
      'XL': pick('XL'),
    };
  }

  int _sumGrades(Map<String, int> m) => m.values.fold<int>(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final farmRef = FirebaseFirestore.instance.collection('farms').doc(farmId);

    // ✅ Toujours calculer à partir des BUILDING_* (source de vérité dynamique)
    final allStocksStream = farmRef.collection('stocks_eggs').snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Stock global (Ferme)')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: allStocksStream,
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

            final good = _emptyGrades();
            int brokenTotal = 0;

            for (final d in snap.data!.docs) {
              // ✅ seulement les stocks bâtiment = stock ferme
              if (!d.id.startsWith('BUILDING_')) continue;

              final data = d.data();
              final picked = _pickGoodByGrade(data);

              for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL']) {
                good[g] = (good[g] ?? 0) + (picked[g] ?? 0);
              }

              brokenTotal += _getInt(data['brokenTotalEggs']);
            }

            final goodTotal = _sumGrades(good);

            return _StockView(
              title: "Stock ferme (calculé automatiquement depuis bâtiments)",
              good: good,
              goodTotal: goodTotal,
              brokenTotal: brokenTotal,
              gradeFr: _gradeFr,
            );
          },
        ),
      ),
    );
  }
}

class _StockView extends StatelessWidget {
  final String title;
  final Map<String, int> good;
  final int goodTotal;
  final int brokenTotal;
  final String Function(String) gradeFr;

  const _StockView({
    required this.title,
    required this.good,
    required this.goodTotal,
    required this.brokenTotal,
    required this.gradeFr,
  });

  // 1 alvéole = 30 oeufs
  // 1 carton = 12 alvéoles
  int _totalTrays(int eggs) => eggs ~/ 30;
  int _cartons(int eggs) => _totalTrays(eggs) ~/ 12;
  int _traysRemainder(int eggs) => _totalTrays(eggs) % 12;
  int _isolated(int eggs) => eggs % 30;

  Widget _chip(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _gradeCard(BuildContext context, String grade, int eggs) {
    final cartons = _cartons(eggs);
    final trays = _traysRemainder(eggs);
    final iso = _isolated(eggs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gradeFr(grade),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip("$cartons carton(s)", icon: Icons.inventory_2),
                _chip("$trays alvéole(s)", icon: Icons.apps),
                _chip("$iso isolé(s)", icon: Icons.egg_alt),
                _chip("$eggs œuf(s)", icon: Icons.numbers),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _chip("Bons: $goodTotal", icon: Icons.egg),
                    _chip("Cassés: $brokenTotal", icon: Icons.warning_amber),
                    _chip("Total: ${goodTotal + brokenTotal}", icon: Icons.calculate),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final g in ['SMALL', 'MEDIUM', 'LARGE', 'XL'])
          _gradeCard(context, g, good[g] ?? 0),
      ],
    );
  }
}
