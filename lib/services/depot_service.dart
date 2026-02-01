import 'package:cloud_firestore/cloud_firestore.dart';

class DepotService {
  DepotService(this.db);

  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> _eggMovementsCol(String farmId) =>
      db.collection('farms').doc(farmId).collection('egg_movements');

  /// Dernier transfert vers dépôt NON réceptionné
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> getLatestPendingTransfer(String farmId) async {
    final q = await _eggMovementsCol(farmId)
        .where('type', isEqualTo: 'TRANSFER_TO_DEPOT')
        .where('received', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;
    return q.docs.first;
  }

  /// Valider la réception :
  /// - crée un mouvement DEPOT_RECEPTION
  /// - marque le transfert reçu (received=true)
  Future<void> receiveTransfer({
    required String farmId,
    required String transferDocId,
    required String depotId,
    required Map<String, int> alveolesByCaliber, // ex: {"S": 10, "M": 15}
    required String? note,
  }) async {
    final transferRef = _eggMovementsCol(farmId).doc(transferDocId);
    final receptionRef = _eggMovementsCol(farmId).doc();

    await db.runTransaction((tx) async {
      final transferSnap = await tx.get(transferRef);
      if (!transferSnap.exists) {
        throw StateError('Transfert introuvable.');
      }

      final data = transferSnap.data() as Map<String, dynamic>;
      final alreadyReceived = (data['received'] == true);
      if (alreadyReceived) {
        throw StateError('Ce transfert a déjà été réceptionné.');
      }

      tx.set(receptionRef, {
        'type': 'DEPOT_RECEPTION',
        'depotId': depotId,
        'sourceTransferId': transferDocId,
        'alveolesByCaliber': alveolesByCaliber,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.update(transferRef, {
        'received': true,
        'receivedAt': FieldValue.serverTimestamp(),
        'receivedByReceptionId': receptionRef.id,
        'receivedAlveolesByCaliber': alveolesByCaliber,
        'receivedNote': note,
      });

      // Optionnel : ici tu peux aussi mettre à jour stocks dépôt (stocks_eggs / depots)
      // si tu as déjà un schéma (ex: farms/{farmId}/depots/{depotId}/stocks/{caliber})
    });
  }
}
