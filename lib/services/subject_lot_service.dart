import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectLotService {
  static const String farmId = 'farm_nkoteng';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _farmRef() =>
      _db.collection('farms').doc(farmId);

  static DocumentReference<Map<String, dynamic>> _activeRef(String buildingId) =>
      _farmRef().collection('building_active_lots').doc(buildingId);

  static DocumentReference<Map<String, dynamic>> _stockRef(String buildingId) =>
      _farmRef().collection('stocks_subjects').doc('BUILDING_$buildingId');

  // ✅ IMPORTANT: conforme à tes rules
  static CollectionReference<Map<String, dynamic>> _lotsCol() =>
      _farmRef().collection('subjects_lots');

  static CollectionReference<Map<String, dynamic>> _movementsCol() =>
      _farmRef().collection('subjects_movements');

  /// Calcule l'âge actuel (semaines + jours) à partir de startedAt + startAgeWeeks/days
  static Map<String, int> computeAge({
    required DateTime startedAt,
    required int startAgeWeeks,
    required int startAgeDays,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final diffDays = n.difference(startedAt).inDays;
    final baseDays = (startAgeWeeks * 7) + startAgeDays;
    final totalDays = baseDays + (diffDays < 0 ? 0 : diffDays);
    final weeks = totalDays ~/ 7;
    final days = totalDays % 7;
    return {'weeks': weeks, 'days': days};
  }

  /// Entrée lot (STRICT: un seul lot actif / bâtiment)
  static Future<String> enterLotStrict({
    required String buildingId,
    required String strain,
    required int qtyIn,
    required int startAgeWeeks,
    required int startAgeDays,
    String source = 'mobile_app',
  }) async {
    if (qtyIn <= 0) throw Exception("Quantité invalide (doit être > 0)");
    if (strain.trim().isEmpty) throw Exception("Souche obligatoire");
    if (startAgeWeeks < 0 || startAgeDays < 0 || startAgeDays > 6) {
      throw Exception("Âge invalide");
    }

    final activeRef = _activeRef(buildingId);
    final stockRef = _stockRef(buildingId);
    final lotDoc = _lotsCol().doc(); // autoId
    final movementRef = _movementsCol().doc();

    await _db.runTransaction((tx) async {
      final activeSnap = await tx.get(activeRef);
      if (activeSnap.exists && (activeSnap.data()?['active'] == true)) {
        throw Exception("❌ Un lot actif existe déjà pour ce bâtiment");
      }

      final now = FieldValue.serverTimestamp();

      // create lot
      tx.set(lotDoc, {
        'buildingId': buildingId,
        'strain': strain.trim(),
        'startedAt': now,
        'startAgeWeeks': startAgeWeeks,
        'startAgeDays': startAgeDays,
        'active': true,
        'createdAt': now,
        'updatedAt': now,
        'source': source,
      });

      // set active pointer
      tx.set(
        activeRef,
        {
          'active': true,
          'lotId': lotDoc.id,
          'strain': strain.trim(),
          'startedAt': now,
          'startAgeWeeks': startAgeWeeks,
          'startAgeDays': startAgeDays,
          'createdAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      // stock add
      tx.set(
        stockRef,
        {
          'totalOnHand': FieldValue.increment(qtyIn),
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      // movement IN
      tx.set(movementRef, {
        'type': 'IN',
        'lotId': lotDoc.id,
        'buildingId': buildingId,
        'qty': qtyIn,
        'strain': strain.trim(),
        'startAgeWeeks': startAgeWeeks,
        'startAgeDays': startAgeDays,
        'createdAt': now,
        'source': source,
      });
    });

    return lotDoc.id;
  }

  /// ✅ Modifier le lot actif (strain/age/startedAt) + refléter dans subjects_lots
  static Future<void> updateActiveLotStrict({
    required String buildingId,
    required String strain,
    required int startAgeWeeks,
    required int startAgeDays,
    DateTime? startedAtOverride, // si null => ne change pas startedAt
    String source = 'mobile_app',
  }) async {
    if (strain.trim().isEmpty) throw Exception("Souche obligatoire");
    if (startAgeWeeks < 0 || startAgeDays < 0 || startAgeDays > 6) {
      throw Exception("Âge invalide");
    }

    final activeRef = _activeRef(buildingId);

    await _db.runTransaction((tx) async {
      final activeSnap = await tx.get(activeRef);
      if (!activeSnap.exists || activeSnap.data()?['active'] != true) {
        throw Exception("❌ Aucun lot actif dans ce bâtiment");
      }

      final data = activeSnap.data()!;
      final lotId = (data['lotId'] ?? '').toString();
      if (lotId.isEmpty) throw Exception("LotId manquant dans building_active_lots");

      final lotRef = _lotsCol().doc(lotId);
      final lotSnap = await tx.get(lotRef);
      if (!lotSnap.exists) {
        throw Exception("❌ Lot introuvable (subjects_lots/$lotId)");
      }

      final now = FieldValue.serverTimestamp();

      // startedAt
      final startedAtField = (startedAtOverride != null)
          ? Timestamp.fromDate(startedAtOverride)
          : null;

      // Update active pointer
      final activePatch = <String, dynamic>{
        'strain': strain.trim(),
        'startAgeWeeks': startAgeWeeks,
        'startAgeDays': startAgeDays,
        'updatedAt': now,
        'source': source,
      };
      if (startedAtField != null) {
        activePatch['startedAt'] = startedAtField;
      }

      tx.set(activeRef, activePatch, SetOptions(merge: true));

      // Update lot doc
      final lotPatch = <String, dynamic>{
        'strain': strain.trim(),
        'startAgeWeeks': startAgeWeeks,
        'startAgeDays': startAgeDays,
        'updatedAt': now,
        'source': source,
      };
      if (startedAtField != null) {
        lotPatch['startedAt'] = startedAtField;
      }

      tx.set(lotRef, lotPatch, SetOptions(merge: true));

      // Audit movement
      final movementRef = _movementsCol().doc();
      tx.set(movementRef, {
        'type': 'EDIT_ACTIVE_LOT',
        'lotId': lotId,
        'buildingId': buildingId,
        'strain': strain.trim(),
        'startAgeWeeks': startAgeWeeks,
        'startAgeDays': startAgeDays,
        'startedAtOverride': startedAtOverride != null ? startedAtField : null,
        'createdAt': now,
        'source': source,
      });
    });
  }

  /// Transfert STRICT: destination doit être vide (pas de lot actif)
  static Future<void> transferStrict({
    required String fromBuildingId,
    required String toBuildingId,
    required int qty,
    String source = 'mobile_app',
  }) async {
    if (fromBuildingId == toBuildingId) throw Exception("Bâtiments identiques");
    if (qty <= 0) throw Exception("Quantité invalide (doit être > 0)");

    final fromActiveRef = _activeRef(fromBuildingId);
    final toActiveRef = _activeRef(toBuildingId);
    final fromStockRef = _stockRef(fromBuildingId);
    final toStockRef = _stockRef(toBuildingId);
    final movementRef = _movementsCol().doc();

    await _db.runTransaction((tx) async {
      final fromActiveSnap = await tx.get(fromActiveRef);
      final toActiveSnap = await tx.get(toActiveRef);
      final fromStockSnap = await tx.get(fromStockRef);

      if (!fromActiveSnap.exists || fromActiveSnap.data()?['active'] != true) {
        throw Exception("❌ Aucun lot actif dans le bâtiment source");
      }
      if (toActiveSnap.exists && toActiveSnap.data()?['active'] == true) {
        throw Exception("❌ Le bâtiment destination a déjà un lot actif");
      }

      final lotId = (fromActiveSnap.data()!['lotId'] ?? '').toString();
      if (lotId.isEmpty) throw Exception("LotId manquant dans building_active_lots");

      final fromQty = (fromStockSnap.data()?['totalOnHand'] is num)
          ? (fromStockSnap.data()!['totalOnHand'] as num).toInt()
          : 0;

      if (fromQty < qty) throw Exception("❌ Stock insuffisant ($fromQty dispo)");

      final now = FieldValue.serverTimestamp();

      // destination prend le même lotId (déplacement du lot)
      tx.set(toActiveRef, {...fromActiveSnap.data()!, 'updatedAt': now}, SetOptions(merge: true));

      // source devient inactif
      tx.set(
        fromActiveRef,
        {
          'active': false,
          'deactivatedAt': now,
          'deactivatedReason': 'TRANSFER',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      // stocks
      tx.set(fromStockRef, {'totalOnHand': FieldValue.increment(-qty), 'updatedAt': now},
          SetOptions(merge: true));
      tx.set(toStockRef, {'totalOnHand': FieldValue.increment(qty), 'updatedAt': now},
          SetOptions(merge: true));

      // movement
      tx.set(movementRef, {
        'type': 'TRANSFER',
        'lotId': lotId,
        'fromBuildingId': fromBuildingId,
        'toBuildingId': toBuildingId,
        'qty': qty,
        'createdAt': now,
        'source': source,
      });
    });
  }

  /// Sortie STRICT (SALE/REFORM)
  static Future<void> outStrict({
    required String buildingId,
    required int qty,
    required String outKind, // SALE | REFORM
    Map<String, dynamic>? saleInfo,
    String source = 'mobile_app',
  }) async {
    if (qty <= 0) throw Exception("Quantité invalide (doit être > 0)");
    final kind = outKind.toUpperCase().trim();
    if (kind != 'SALE' && kind != 'REFORM') {
      throw Exception("outKind invalide (SALE|REFORM)");
    }

    final activeRef = _activeRef(buildingId);
    final stockRef = _stockRef(buildingId);
    final movementRef = _movementsCol().doc();

    await _db.runTransaction((tx) async {
      final activeSnap = await tx.get(activeRef);
      final stockSnap = await tx.get(stockRef);

      if (!activeSnap.exists || activeSnap.data()?['active'] != true) {
        throw Exception("❌ Aucun lot actif dans ce bâtiment");
      }

      final lotId = (activeSnap.data()!['lotId'] ?? '').toString();
      if (lotId.isEmpty) throw Exception("LotId manquant dans building_active_lots");

      final currentQty = (stockSnap.data()?['totalOnHand'] is num)
          ? (stockSnap.data()!['totalOnHand'] as num).toInt()
          : 0;

      if (currentQty < qty) throw Exception("❌ Stock insuffisant ($currentQty dispo)");

      final now = FieldValue.serverTimestamp();

      // movement OUT
      tx.set(movementRef, {
        'type': 'OUT',
        'outKind': kind,
        'lotId': lotId,
        'buildingId': buildingId,
        'qty': qty,
        'saleInfo': kind == 'SALE' ? saleInfo : null,
        'createdAt': now,
        'source': source,
      });

      // stock decrement
      tx.set(stockRef, {'totalOnHand': FieldValue.increment(-qty), 'updatedAt': now},
          SetOptions(merge: true));

      // if empty -> deactivate lot
      if (currentQty == qty) {
        tx.set(
          activeRef,
          {
            'active': false,
            'deactivatedAt': now,
            'deactivatedReason': kind,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      }
    });
  }
}
