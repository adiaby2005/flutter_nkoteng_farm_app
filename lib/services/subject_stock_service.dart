import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectStockService {
  static const String farmId = 'farm_nkoteng';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _dateIso(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static DocumentReference<Map<String, dynamic>> _farmRef() =>
      _db.collection('farms').doc(farmId);

  static DocumentReference<Map<String, dynamic>> _activeLotRef(String buildingId) =>
      _farmRef().collection('building_active_lots').doc(buildingId);

  static DocumentReference<Map<String, dynamic>> _lotRef(String lotId) =>
      _farmRef().collection('lots').doc(lotId);

  static DocumentReference<Map<String, dynamic>> _lotLocationRef(String lotId, String buildingId) =>
      _farmRef().collection('lot_locations').doc('${lotId}_$buildingId');

  static DocumentReference<Map<String, dynamic>> _stocksBuildingRef(String buildingId) =>
      _farmRef().collection('stocks_subjects').doc('BUILDING_$buildingId');

  static DocumentReference<Map<String, dynamic>> _stocksFarmRef() =>
      _farmRef().collection('stocks_subjects').doc('FARM_GLOBAL');

  static DocumentReference<Map<String, dynamic>> _idempotencyRef(String key) =>
      _farmRef().collection('idempotency').doc(key);

  static DocumentReference<Map<String, dynamic>> _movementRef() =>
      _farmRef().collection('subjects_movements').doc();

  /// Lit le lot actif d’un bâtiment (null si aucun).
  static Future<String?> getActiveLotIdForBuilding(String buildingId) async {
    final snap = await _activeLotRef(buildingId).get(const GetOptions(source: Source.serverAndCache));
    final data = snap.data();
    final lotId = (data?['lotId'] ?? '').toString().trim();
    if (lotId.isEmpty) return null;
    final active = data?['active'] == true;
    return active ? lotId : null;
  }

  /// ENTREES SUJETS :
  /// - si aucun lot actif dans le bâtiment => crée un nouveau lot + l’active
  /// - sinon => ajoute des sujets au lot actif existant
  ///
  /// Retour:
  /// {
  ///   lotId: "...",
  ///   createdNewLot: true/false
  /// }
  static Future<Map<String, dynamic>> addSubjectsToBuilding({
    required String buildingId,
    required int qty,
    required DateTime date,
    // requis seulement si création nouveau lot :
    String? souche,
    int? startAgeWeeks,
    int? startAgeDays,
    String? origin,
    String? notes,
  }) async {
    if (qty <= 0) {
      throw Exception("Quantité invalide (doit être > 0).");
    }

    final dateIso = _dateIso(date);
    final farmRef = _farmRef();

    // 1) lire lot actif (hors transaction ok, mais on revalide dans la transaction)
    final activeSnap = await _activeLotRef(buildingId).get(const GetOptions(source: Source.serverAndCache));
    final activeData = activeSnap.data();
    final currentLotId = (activeData?['lotId'] ?? '').toString().trim();
    final hasActive = (activeData?['active'] == true) && currentLotId.isNotEmpty;

    // 2) si pas de lot actif, on va créer un lot
    final bool willCreateNewLot = !hasActive;

    final String lotId = willCreateNewLot ? farmRef.collection('lots').doc().id : currentLotId;

    if (willCreateNewLot) {
      final s = (souche ?? '').trim();
      if (s.isEmpty) throw Exception("Souche requise pour créer un nouveau lot.");
      final w = startAgeWeeks ?? 0;
      final d = startAgeDays ?? 0;
      if (w < 0 || d < 0 || d > 6) {
        throw Exception("Âge invalide (semaines >=0, jours 0..6).");
      }
    }

    // Idempotency : un key stable
    final uniqueKey = [
      'SUBJECTS_IN',
      farmId,
      buildingId,
      dateIso,
      lotId,
      qty.toString(),
      willCreateNewLot ? 'NEWLOT' : 'EXISTINGLOT',
    ].join('|');

    final lockRef = _idempotencyRef(uniqueKey);
    final movementRef = _movementRef();
    final activeRef = _activeLotRef(buildingId);
    final lotRef = _lotRef(lotId);
    final locRef = _lotLocationRef(lotId, buildingId);
    final bStockRef = _stocksBuildingRef(buildingId);
    final fStockRef = _stocksFarmRef();

    bool didWrite = false;

    await _db.runTransaction((tx) async {
      // A) idempotency read
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        didWrite = false;
        return;
      }

      // B) re-check active lot inside tx
      final activeNowSnap = await tx.get(activeRef);
      final activeNowData = activeNowSnap.data() as Map<String, dynamic>?;
      final activeNowLotId = (activeNowData?['lotId'] ?? '').toString().trim();
      final activeNow = activeNowData?['active'] == true;

      if (!willCreateNewLot) {
        // on ajoute sur lot actif existant => il doit exister et matcher
        if (!(activeNow && activeNowLotId == lotId)) {
          throw Exception("Lot actif du bâtiment changé. Réessaie.");
        }
      } else {
        // on veut créer un lot => il ne doit pas y avoir de lot actif
        if (activeNow && activeNowLotId.isNotEmpty) {
          throw Exception("Ce bâtiment a déjà un lot actif. Ajoute plutôt sur le lot actif.");
        }
      }

      // C) create lot if needed
      if (willCreateNewLot) {
        tx.set(lotRef, {
          'farmId': farmId,
          'status': 'ACTIVE',
          'souche': (souche ?? '').trim(),
          'arrivalDate': dateIso,
          'startAgeWeeks': (startAgeWeeks ?? 0),
          'startAgeDays': (startAgeDays ?? 0),
          'initialQty': qty,
          'origin': (origin ?? '').trim().isEmpty ? null : (origin ?? '').trim(),
          'notes': (notes ?? '').trim().isEmpty ? null : (notes ?? '').trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // active lot mapping (1 lot actif par bâtiment)
        tx.set(activeRef, {
          'buildingId': buildingId,
          'lotId': lotId,
          'active': true,
          'activatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // update lot updatedAt (optionnel)
        tx.set(lotRef, {'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }

      // D) update lot_locations qtyOnHand
      final locSnap = await tx.get(locRef);
      final locData = locSnap.data() as Map<String, dynamic>?;
      final currentOnHand = (locData?['qtyOnHand'] is num) ? (locData!['qtyOnHand'] as num).toInt() : 0;

      tx.set(locRef, {
        'lotId': lotId,
        'buildingId': buildingId,
        'qtyOnHand': currentOnHand + qty,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // E) movements
      tx.set(movementRef, {
        'type': 'IN',
        'date': dateIso,
        'lotId': lotId,
        'buildingId': buildingId,
        'qty': qty,
        'from': {'kind': 'FARM'},
        'to': {'kind': 'BUILDING', 'id': buildingId},
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      });

      // F) aggregate stocks
      tx.set(bStockRef, {
        'updatedAt': FieldValue.serverTimestamp(),
        'totalOnHand': FieldValue.increment(qty),
      }, SetOptions(merge: true));

      tx.set(fStockRef, {
        'updatedAt': FieldValue.serverTimestamp(),
        'totalOnHand': FieldValue.increment(qty),
      }, SetOptions(merge: true));

      // G) write lock
      tx.set(lockRef, {
        'kind': 'SUBJECTS_IN',
        'createdAt': FieldValue.serverTimestamp(),
      });

      didWrite = true;
    });

    if (!didWrite) {
      return {'lotId': lotId, 'createdNewLot': willCreateNewLot, 'skipped': true};
    }

    return {'lotId': lotId, 'createdNewLot': willCreateNewLot, 'skipped': false};
  }

  /// Transfert bâtiment -> bâtiment (1 lot actif par bâtiment, donc on transfère le lot actif du FROM)
  static Future<void> transferSubjects({
    required String fromBuildingId,
    required String toBuildingId,
    required int qty,
    required DateTime date,
    String? note,
  }) async {
    if (fromBuildingId == toBuildingId) throw Exception("Bâtiments identiques.");
    if (qty <= 0) throw Exception("Quantité invalide.");

    final dateIso = _dateIso(date);
    final farmRef = _farmRef();

    // lire lot actif from (server)
    final fromActive = await _activeLotRef(fromBuildingId).get(const GetOptions(source: Source.server));
    final fromLotId = (fromActive.data()?['lotId'] ?? '').toString().trim();
    final fromIsActive = fromActive.data()?['active'] == true;
    if (!fromIsActive || fromLotId.isEmpty) throw Exception("Aucun lot actif dans le bâtiment source.");

    final uniqueKey = ['SUBJECTS_TRANSFER', farmId, dateIso, fromBuildingId, toBuildingId, fromLotId, qty.toString()].join('|');
    final lockRef = _idempotencyRef(uniqueKey);

    final moveRef = _movementRef();
    final fromLocRef = _lotLocationRef(fromLotId, fromBuildingId);

    // Le toBuilding doit être vide (pas de lot actif) OU tu autorises fusion ? (ici on interdit)
    final toActiveRef = _activeLotRef(toBuildingId);
    final toLocRef = _lotLocationRef(fromLotId, toBuildingId);

    final fromBStockRef = _stocksBuildingRef(fromBuildingId);
    final toBStockRef = _stocksBuildingRef(toBuildingId);

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) return;

      final toActiveSnap = await tx.get(toActiveRef);
      final toActiveData = toActiveSnap.data() as Map<String, dynamic>?;
      final toHasActive = (toActiveData?['active'] == true) && ((toActiveData?['lotId'] ?? '').toString().trim().isNotEmpty);
      if (toHasActive) {
        throw Exception("Le bâtiment destination a déjà un lot actif. Transfert refusé (1 lot actif par bâtiment).");
      }

      // from stock
      final fromLocSnap = await tx.get(fromLocRef);
      final fromLocData = fromLocSnap.data() as Map<String, dynamic>?;
      final fromOnHand = (fromLocData?['qtyOnHand'] is num) ? (fromLocData!['qtyOnHand'] as num).toInt() : 0;
      if (fromOnHand < qty) throw Exception("Stock sujets insuffisant: $fromOnHand dispo.");

      // decrement from
      tx.set(fromLocRef, {
        'qtyOnHand': fromOnHand - qty,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // increment to
      final toLocSnap = await tx.get(toLocRef);
      final toLocData = toLocSnap.data() as Map<String, dynamic>?;
      final toOnHand = (toLocData?['qtyOnHand'] is num) ? (toLocData!['qtyOnHand'] as num).toInt() : 0;

      tx.set(toLocRef, {
        'lotId': fromLotId,
        'buildingId': toBuildingId,
        'qtyOnHand': toOnHand + qty,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // active lot mapping for destination (becomes active)
      tx.set(toActiveRef, {
        'buildingId': toBuildingId,
        'lotId': fromLotId,
        'active': true,
        'activatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // if source becomes 0 => deactivate
      if (fromOnHand - qty <= 0) {
        tx.set(_activeLotRef(fromBuildingId), {
          'active': false,
          'deactivatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // movement
      tx.set(moveRef, {
        'type': 'TRANSFER',
        'date': dateIso,
        'lotId': fromLotId,
        'qty': qty,
        'from': {'kind': 'BUILDING', 'id': fromBuildingId},
        'to': {'kind': 'BUILDING', 'id': toBuildingId},
        'note': (note ?? '').trim().isEmpty ? null : (note ?? '').trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      });

      // aggregates (farm unchanged)
      tx.set(fromBStockRef, {'updatedAt': FieldValue.serverTimestamp(), 'totalOnHand': FieldValue.increment(-qty)}, SetOptions(merge: true));
      tx.set(toBStockRef, {'updatedAt': FieldValue.serverTimestamp(), 'totalOnHand': FieldValue.increment(qty)}, SetOptions(merge: true));

      tx.set(lockRef, {'kind': 'SUBJECTS_TRANSFER', 'createdAt': FieldValue.serverTimestamp()});
    });
  }
}
