import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/building.dart';

class BuildingService {
  static final _db = FirebaseFirestore.instance;

  static Stream<List<Building>> streamBuildings() {
    return _db
        .collection('farms')
        .doc('farm_nkoteng')
        .collection('buildings')
        .orderBy('name')
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => Building.fromFirestore(d.id, d.data()))
          .toList();
    });
  }
}
