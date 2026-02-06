import 'package:cloud_firestore/cloud_firestore.dart';

class EggTransferService {
  static const int eggsPerTray = 30;
  static const int traysPerCarton = 12;

  final FirebaseFirestore _db;
  EggTransferService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _farmRef(String farmId) =>
      _db.collection('farms').doc(farmId);

  DocumentReference<Map<String, dynamic>> _stockEggRef(String farmId, String docId) =>
      _farmRef(farmId).collection('stocks_eggs').doc(docId);

  DocumentReference<Map<String, dynamic>> _idempotencyRef(String farmId, String key) =>
      _farmRef(farmId).collection('idempotency').doc(key);

  CollectionReference<Map<String, dynamic>> _eggMovementsCol(String farmId) =>
      _farmRef(farmId).collection('egg_movements');

  int _asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;

  Map<String, int> _asIntMap(dynamic v) {
    if (v is Map) {
      final out = <String, int>{};
      for (final e in v.entries) {
        out['${e.key}'] = _asInt(e.value);
      }
      return out;
    }
    return <String, int>{};
  }

  /// Source de vérité = eggsByGrade.
  /// Fallback: goodByGrade si eggsByGrade vide (pour compat legacy).
  Map<String, int> _pickGoodByGrade(Map<String, dynamic>? stockData) {
    final eggs = _asIntMap(stockData?['eggsByGrade']);
    final good = _asIntMap(stockData?['goodByGrade']);

    int pick(String g) {
      final ve = eggs[g] ?? 0;
      if (ve != 0) return ve;
      return good[g] ?? 0;
    }

    return <String, int>{
      'SMALL': pick('SMALL'),
      'MEDIUM': pick('MEDIUM'),
      'LARGE': pick('LARGE'),
      'XL': pick('XL'),
    };
  }

  int _sum(Map<String, int> m) => m.values.fold<int>(0, (a, b) => a + b);

  /// Transfert Ferme -> Dépôt (anti-incohérence)
  ///
  /// - fromStockId: docId stock source (ex: 'FARM_GLOBAL' ou 'BUILDING_xxx')
  /// - depotId: identifiant dépôt
  /// - depotName: nom dépôt (optionnel, pour trace)
  /// - qtyByGrade: quantités à transférer (œufs) par calibre
  /// - brokenQty: nombre d'œufs cassés transférés (sans calibre)
  ///
  /// Ecrit:
  /// - egg_movements/{autoId}
  /// - stocks_eggs/{fromStockId} (maps + goodTotalEggs recalculé)
  /// - stocks_eggs/DEPOT_{depotId} (maps + goodTotalEggs recalculé)
  /// - idempotency/{key} pour éviter double transfert
  Future<void> transferFarmToDepot({
    required String farmId,
    required String fromStockId,
    required String depotId,
    String? depotName,
    required Map<String, int> qtyByGrade,
    int brokenQty = 0,
    required String dateIso, // 'YYYY-MM-DD'
    String source = 'mobile_app',
  }) async {
    // Normalize grades
    final grades = <String>['SMALL', 'MEDIUM', 'LARGE', 'XL'];
    final q = <String, int>{
      for (final g in grades) g: (qtyByGrade[g] ?? 0),
    };

    final totalGoodOut = _sum(q);
    if (totalGoodOut <= 0 && brokenQty <= 0) {
      throw Exception("Transfert: rien à transférer.");
    }
    if (brokenQty < 0) throw Exception("Transfert: casses négatives interdites.");
    for (final g in grades) {
      if (q[g]! < 0) throw Exception("Transfert: quantité négative interdite ($g).");
    }

    final fromRef = _stockEggRef(farmId, fromStockId);
    final toRef = _stockEggRef(farmId, 'DEPOT_$depotId');
    final movementRef = _eggMovementsCol(farmId).doc();

    // Idempotency key: stable
    final key = [
      'EGG_TRANSFER_FARM_DEPOT',
      farmId,
      dateIso,
      fromStockId,
      depotId,
      '${q['SMALL']}|${q['MEDIUM']}|${q['LARGE']}|${q['XL']}|$brokenQty',
    ].join('|');
    final lockRef = _idempotencyRef(farmId, key);

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        throw Exception("Transfert déjà appliqué (idempotency).");
      }

      final fromSnap = await tx.get(fromRef);
      final toSnap = await tx.get(toRef);

      final fromData = fromSnap.data();
      final toData = toSnap.data();

      final fromGood = _pickGoodByGrade(fromData);
      final toGood = _pickGoodByGrade(toData);

      final fromBroken = _asInt(fromData?['brokenTotalEggs']);
      final toBroken = _asInt(toData?['brokenTotalEggs']);

      // Check availability
      for (final g in grades) {
        final available = fromGood[g] ?? 0;
        final need = q[g] ?? 0;
        if (available < need) {
          throw Exception("Stock insuffisant ($g): dispo=$available, demandé=$need");
        }
      }
      if (fromBroken < brokenQty) {
        throw Exception("Stock casses insuffisant: dispo=$fromBroken, demandé=$brokenQty");
      }

      final newFromGood = <String, int>{
        for (final g in grades) g: (fromGood[g] ?? 0) - (q[g] ?? 0),
      };
      final newToGood = <String, int>{
        for (final g in grades) g: (toGood[g] ?? 0) + (q[g] ?? 0),
      };

      final newFromBroken = fromBroken - brokenQty;
      final newToBroken = toBroken + brokenQty;

      final now = FieldValue.serverTimestamp();

      // ✅ IMPORTANT: on écrit la MAP COMPLETE + total recalculé
      tx.set(fromRef, {
        'eggsByGrade': newFromGood,
        'goodByGrade': newFromGood, // compat legacy
        'goodTotalEggs': _sum(newFromGood),
        'brokenTotalEggs': newFromBroken,
        'updatedAt': now,
        'source': source,
      }, SetOptions(merge: true));

      tx.set(toRef, {
        'kind': 'DEPOT',
        'locationType': 'DEPOT',
        'locationId': depotId,
        'refId': depotId,
        'name': depotName,
        'eggsByGrade': newToGood,
        'goodByGrade': newToGood, // compat legacy
        'goodTotalEggs': _sum(newToGood),
        'brokenTotalEggs': newToBroken,
        'updatedAt': now,
        'source': source,
      }, SetOptions(merge: true));

      // Movement (audit)
      tx.set(movementRef, {
        'date': dateIso,
        'type': 'FARM_TO_DEPOT',
        'from': {'stockId': fromStockId},
        'to': {'depotId': depotId, 'depotName': depotName},
        'goodByGrade': q,
        'goodTotalEggs': totalGoodOut,
        'brokenTotalEggs': brokenQty,
        'createdAt': now,
        'source': source,
      });

      tx.set(lockRef, {
        'kind': 'EGG_TRANSFER_FARM_DEPOT',
        'createdAt': now,
        'movementId': movementRef.id,
      });
    });
  }
}
