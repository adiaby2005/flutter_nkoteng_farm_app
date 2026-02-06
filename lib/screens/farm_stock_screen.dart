// farm_stock_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// ✅ Stock ferme (source de vérité) : farms/{farmId}/stocks_eggs/FARM_GLOBAL
///
/// Logique finale (alignée migration "casses sans calibre") :
/// - eggsByGrade.{SMALL,MEDIUM,LARGE,XL} = œufs bons par calibre
/// - goodTotalEggs = (optionnel) total stocké (on vérifie vs recalcul)
/// - brokenTotalEggs = casses TOTAL (sans calibre)  ✅ source unique pour les casses
/// - brokenByGrade = doit être 0 partout (on ignore pour éviter incohérences)
///
/// Affichage:
/// - Par calibre: dispo en Cartons / Alvéoles / Isolés (CTI) + total œufs
/// - Casses: CTI global + total casses
/// - Détection incohérence: compare totaux stockés vs totaux recalculés
class FarmStockScreen extends StatefulWidget {
  final String farmId;
  const FarmStockScreen({super.key, required this.farmId});

  @override
  State<FarmStockScreen> createState() => _FarmStockScreenState();
}

class _FarmStockScreenState extends State<FarmStockScreen> {
  final _db = FirebaseFirestore.instance;

  Future<DocumentSnapshot<Map<String, dynamic>>>? _future;

  static const _grades = <String>['SMALL', 'MEDIUM', 'LARGE', 'XL'];

  // Carton = 12 alvéoles ; Alvéole = 30 œufs
  static const int _eggsPerTray = 30;
  static const int _traysPerCarton = 12;

  @override
  void initState() {
    super.initState();
    _future = _fetchGlobalStock(server: false);
  }

  DocumentReference<Map<String, dynamic>> get _globalRef => _db
      .collection('farms')
      .doc(widget.farmId)
      .collection('stocks_eggs')
      .doc('FARM_GLOBAL');

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchGlobalStock({required bool server}) async {
    if (server) {
      return _globalRef.get(const GetOptions(source: Source.server));
    }
    return _globalRef.get(const GetOptions(source: Source.serverAndCache));
  }

  void _refreshServer() {
    setState(() {
      _future = _fetchGlobalStock(server: true);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stock ferme actualisé (serveur) ✅')),
    );
  }

  // -------------------------
  // Helpers
  // -------------------------
  int _asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;

  Map<String, dynamic> _asMap(dynamic v) =>
      (v is Map<String, dynamic>) ? v : <String, dynamic>{};

  Map<String, int> _normalizeGrades(dynamic v) {
    final m = _asMap(v);
    return {
      for (final g in _grades) g: _asInt(m[g]),
    };
  }

  int _sumGrades(Map<String, int> m) {
    int s = 0;
    for (final g in _grades) {
      s += _asInt(m[g]);
    }
    return s;
  }

  Map<String, int> _ctiFromEggs(int eggs) {
    if (eggs < 0) eggs = 0;
    final perCarton = _traysPerCarton * _eggsPerTray; // 360
    final cartons = eggs ~/ perCarton;
    final rem1 = eggs % perCarton;
    final trays = rem1 ~/ _eggsPerTray;
    final isolated = rem1 % _eggsPerTray;
    return {'cartons': cartons, 'trays': trays, 'isolated': isolated};
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k : ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v),
      ],
    );
  }

  Widget _gradeCard({required String grade, required int eggs}) {
    final good = _ctiFromEggs(eggs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(grade, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _kv('Dispo', '${good['cartons']} c / ${good['trays']} a / ${good['isolated']} i'),
                _kv('Total', '$eggs œufs'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _incoherenceCard({
    required int storedGoodTotal,
    required int storedBrokenTotal,
    required int calcGoodTotal,
    required int calcBrokenTotal,
  }) {
    final ok = storedGoodTotal == calcGoodTotal && storedBrokenTotal == calcBrokenTotal;

    if (ok) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.verified, color: Colors.green),
          title: const Text("Cohérence OK"),
          subtitle: Text("Totaux: œufs=$calcGoodTotal, casses=$calcBrokenTotal"),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  "Incohérence détectée",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text("Totaux stockés: œufs=$storedGoodTotal, casses=$storedBrokenTotal"),
            Text("Totaux recalculés: œufs=$calcGoodTotal, casses=$calcBrokenTotal"),
            const SizedBox(height: 8),
            const Text(
              "Affichage basé sur les totaux recalculés (plus fiables).",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock ferme'),
        actions: [
          IconButton(
            tooltip: 'Actualiser stock (serveur)',
            onPressed: _refreshServer,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Erreur: ${snap.error}'),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final data = snap.data!.data() ?? <String, dynamic>{};

          // ✅ Bons oeufs: uniquement eggsByGrade
          final eggsByGrade = _normalizeGrades(data['eggsByGrade']);

          // ✅ Casses: uniquement brokenTotalEggs (sans calibre)
          final brokenTotalStored = _asInt(data['brokenTotalEggs']);

          // Totaux stockés (peuvent être absents / faux)
          final goodTotalStored = _asInt(data['goodTotalEggs']);

          // Totaux recalculés (source fiable)
          final goodTotalCalc = _sumGrades(eggsByGrade);
          final brokenTotalCalc = brokenTotalStored; // logique finale: brokenTotalEggs = vérité

          // CTI global (bons + casses)
          final goodCti = _ctiFromEggs(goodTotalCalc);
          final brokenCti = _ctiFromEggs(brokenTotalCalc);

          return RefreshIndicator(
            onRefresh: () async {
              _refreshServer();
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _incoherenceCard(
                  storedGoodTotal: goodTotalStored,
                  storedBrokenTotal: brokenTotalStored,
                  calcGoodTotal: goodTotalCalc,
                  calcBrokenTotal: brokenTotalCalc,
                ),
                const SizedBox(height: 10),

                // -------------------------
                // Résumé
                // -------------------------
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Résumé', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _kv('Total œufs', '$goodTotalCalc'),
                            _kv('CTI œufs', '${goodCti['cartons']} c / ${goodCti['trays']} a / ${goodCti['isolated']} i'),
                          ],
                        ),
                        const Divider(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _kv('Total casses', '$brokenTotalCalc'),
                            _kv('CTI casses', '${brokenCti['cartons']} c / ${brokenCti['trays']} a / ${brokenCti['isolated']} i'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // -------------------------
                // Détail par calibre (bons oeufs)
                // -------------------------
                for (final g in _grades)
                  _gradeCard(
                    grade: g,
                    eggs: _asInt(eggsByGrade[g]),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}
