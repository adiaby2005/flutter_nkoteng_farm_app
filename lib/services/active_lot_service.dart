import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveLotService {
  static final _db = FirebaseFirestore.instance;

  static Future<String?> getActiveLotIdForBuilding(String buildingId) async {
    final doc = await _db
        .collection('farms')
        .doc('farm_nkoteng')
        .collection('building_active_lots')
        .doc(buildingId)
        .get();

    if (!doc.exists) return null;
    final data = doc.data();
    return data?['activeLotId'] as String?;
  }
}
