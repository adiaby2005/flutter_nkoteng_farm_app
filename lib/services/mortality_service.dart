import 'package:cloud_firestore/cloud_firestore.dart';

class MortalityService {
  static final _db = FirebaseFirestore.instance;

  /// Ecrit un enregistrement dans daily_mortality.
  /// Si lotId est non-null, on met aussi à jour le lot (mortalityTotal, currentQty).
  static Future<void> addDailyMortality({
    required String buildingId,
    required String dateIso, // ex "2026-03-16"
    required int qty,
    required String? cause,
    required String? note,
    required String? lotId,
  }) async {
    final farmRef = _db.collection('farms').doc('farm_nkoteng');
    final idempotencyKey = [
      'MORTALITY_AUTOLOT',
      'farm_nkoteng',
      dateIso,
      buildingId,
      lotId ?? 'NOLOT',
      qty.toString(),
    ].join('|');

    final lockRef = farmRef.collection('idempotency').doc(idempotencyKey);
    final mortalityRef = farmRef.collection('daily_mortality').doc();
    final lotRef = lotId == null ? null : farmRef.collection('lots').doc(lotId);

    await _db.runTransaction((tx) async {
      // READS first
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        // anti double clic
        return;
      }

      DocumentSnapshot<Map<String, dynamic>>? lotSnap;
      Map<String, dynamic>? lotData;
      if (lotRef != null) {
        lotSnap = await tx.get(lotRef);
        if (!lotSnap.exists) {
          throw Exception('Lot introuvable.');
        }
        lotData = lotSnap.data();
        final currentQty = (lotData?['currentQty'] ?? 0) as int;
        if (qty > currentQty) {
          throw Exception('Mortalité > effectif du lot (stock insuffisant).');
        }
      }

      // WRITES
      tx.set(mortalityRef, {
        'date': dateIso,
        'buildingId': buildingId,
        'lotId': lotId,
        'qty': qty,
        'cause': cause,
        'note': note,
        'mode': lotId != null ? 'AUTO_LOT' : 'NO_LOT',
        'uniqueKey': idempotencyKey,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'mobile_app',
      }, SetOptions(merge: true));

      if (lotRef != null && lotData != null) {
        final currentQty = (lotData['currentQty'] ?? 0) as int;
        final mortalityTotal = (lotData['mortalityTotal'] ?? 0) as int;

        tx.set(lotRef, {
          'currentQty': currentQty - qty,
          'mortalityTotal': mortalityTotal + qty,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      tx.set(lockRef, {
        'kind': 'DAILY_MORTALITY_AUTO_LOT',
        'createdAt': FieldValue.serverTimestamp(),
        'uniqueKey': idempotencyKey,
      }, SetOptions(merge: true));
    });
  }
}
