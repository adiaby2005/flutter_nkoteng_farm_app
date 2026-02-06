import 'package:cloud_firestore/cloud_firestore.dart';

class MortalityService {
  static const String farmId = 'farm_nkoteng';
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _farmRef() =>
      _db.collection('farms').doc(farmId);

  static DocumentReference<Map<String, dynamic>> _stockRef(String buildingId) =>
      _farmRef().collection('stocks_subjects').doc('BUILDING_$buildingId');

  static DocumentReference<Map<String, dynamic>> _lotRef(String lotId) =>
      _farmRef().collection('subjects_lots').doc(lotId);

  /// ✅ Ecrit un enregistrement dans daily_mortality + décrémente le lot actif et le stock sujets.
  static Future<void> addDailyMortality({
    required String buildingId,
    required String dateIso,
    required int qty,
    required String? cause,
    required String? note,
    required String lotId, // ✅ obligatoire ici
    String source = 'mobile_app',
  }) async {
    if (qty <= 0) throw Exception("Mortalité: quantité invalide.");

    final farmRef = _farmRef();
    final idempotencyKey = [
      'MORTALITY',
      farmId,
      dateIso,
      buildingId,
      lotId,
      qty.toString(),
    ].join('|');

    final lockRef = farmRef.collection('idempotency').doc(idempotencyKey);
    final mortalityRef = farmRef.collection('daily_mortality').doc();
    final lotRef = _lotRef(lotId);
    final stockRef = _stockRef(buildingId);

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) return;

      final lotSnap = await tx.get(lotRef);
      if (!lotSnap.exists) throw Exception('Lot introuvable (subjects_lots).');

      final lot = lotSnap.data() ?? {};
      final currentQty = (lot['currentQty'] is num) ? (lot['currentQty'] as num).toInt() : 0;
      final mortalityTotal = (lot['mortalityTotal'] is num) ? (lot['mortalityTotal'] as num).toInt() : 0;

      if (qty > currentQty) {
        throw Exception('Mortalité > effectif du lot (stock insuffisant).');
      }

      final stockSnap = await tx.get(stockRef);
      final stockData = stockSnap.data() ?? {};
      final stockOnHand = (stockData['totalOnHand'] is num) ? (stockData['totalOnHand'] as num).toInt() : 0;
      if (qty > stockOnHand) {
        throw Exception('Mortalité > stock sujets du bâtiment ($stockOnHand).');
      }

      final now = FieldValue.serverTimestamp();

      tx.set(mortalityRef, {
        'date': dateIso,
        'buildingId': buildingId,
        'lotId': lotId,
        'qty': qty,
        'cause': cause,
        'note': note,
        'mode': 'AUTO_LOT',
        'uniqueKey': idempotencyKey,
        'createdAt': now,
        'source': source,
      }, SetOptions(merge: true));

      tx.set(lotRef, {
        'currentQty': currentQty - qty,
        'mortalityTotal': mortalityTotal + qty,
        'updatedAt': now,
      }, SetOptions(merge: true));

      tx.set(stockRef, {
        'totalOnHand': FieldValue.increment(-qty),
        'updatedAt': now,
      }, SetOptions(merge: true));

      tx.set(lockRef, {
        'kind': 'DAILY_MORTALITY',
        'createdAt': now,
        'uniqueKey': idempotencyKey,
      }, SetOptions(merge: true));
    });
  }
}
