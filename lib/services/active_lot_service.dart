import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveLotService {
  static const String farmId = 'farm_nkoteng';
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _farmRef() =>
      _db.collection('farms').doc(farmId);

  static DocumentReference<Map<String, dynamic>> _activeRef(String buildingId) =>
      _farmRef().collection('building_active_lots').doc(buildingId);

  /// ✅ Retourne le lotId du lot actif du bâtiment, ou null.
  /// Supporte aussi l'ancien champ activeLotId (legacy).
  static Future<String?> getActiveLotIdForBuilding(String buildingId) async {
    final snap = await _activeRef(buildingId)
        .get(const GetOptions(source: Source.server));

    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;

    final active = data['active'] == true;
    if (!active) return null;

    final lotId = (data['lotId'] ?? '').toString().trim();
    if (lotId.isNotEmpty) return lotId;

    // legacy fallback
    final legacy = (data['activeLotId'] ?? '').toString().trim();
    return legacy.isNotEmpty ? legacy : null;
  }
}
