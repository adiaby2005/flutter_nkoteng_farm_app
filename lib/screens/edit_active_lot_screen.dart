import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/subject_lot_service.dart';

class EditActiveLotScreen extends StatefulWidget {
  final String buildingId;
  final String buildingName;

  const EditActiveLotScreen({
    super.key,
    required this.buildingId,
    required this.buildingName,
  });

  @override
  State<EditActiveLotScreen> createState() => _EditActiveLotScreenState();
}

class _EditActiveLotScreenState extends State<EditActiveLotScreen> {
  static const String _farmId = SubjectLotService.farmId;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final _strainCtrl = TextEditingController();
  final _ageWeeksCtrl = TextEditingController(text: '0');
  final _ageDaysCtrl = TextEditingController(text: '0');

  DateTime? _startedAt; // modifiable via date picker
  bool _saving = false;

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  String _s(TextEditingController c) => c.text.trim();

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _strainCtrl.dispose();
    _ageWeeksCtrl.dispose();
    _ageDaysCtrl.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> _farmRef() =>
      _db.collection('farms').doc(_farmId);

  DocumentReference<Map<String, dynamic>> _activeRef() =>
      _farmRef().collection('building_active_lots').doc(widget.buildingId);

  DocumentReference<Map<String, dynamic>> _stockRef() =>
      _farmRef().collection('stocks_subjects').doc('BUILDING_${widget.buildingId}');

  CollectionReference<Map<String, dynamic>> _lotsCol() =>
      _farmRef().collection('lots');

  CollectionReference<Map<String, dynamic>> _movementsCol() =>
      _farmRef().collection('subjects_movements');

  String _asStr(dynamic v) => (v ?? '').toString();
  int _asInt(dynamic v) => (v is num) ? v.toInt() : 0;

  void _prefillFromActive(Map<String, dynamic> active) {
    final strain = _asStr(active['strain']);
    final w = _asInt(active['startAgeWeeks']);
    final d = _asInt(active['startAgeDays']);

    DateTime? started;
    final ts = active['startedAt'];
    if (ts is Timestamp) started = ts.toDate();

    // On ne ré-écrase pas si l'utilisateur a déjà commencé à modifier
    if (_strainCtrl.text.isEmpty) _strainCtrl.text = strain;
    if (_ageWeeksCtrl.text.trim() == '0' && w != 0) _ageWeeksCtrl.text = '$w';
    if (_ageDaysCtrl.text.trim() == '0' && d != 0) _ageDaysCtrl.text = '$d';
    _startedAt ??= started;
  }

  Future<void> _pickStartedAt() async {
    final now = DateTime.now();
    final initial = _startedAt ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: now.add(const Duration(days: 1)),
    );

    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      // conserve l'heure actuelle pour éviter un timestamp à minuit si tu veux
      _startedAt = DateTime(picked.year, picked.month, picked.day, initial.hour, initial.minute);
    });
  }

  void _validate() {
    final strain = _s(_strainCtrl);
    final w = _i(_ageWeeksCtrl);
    final d = _i(_ageDaysCtrl);

    if (strain.isEmpty) throw Exception("Souche obligatoire.");
    if (w < 0) throw Exception("Âge semaines invalide.");
    if (d < 0 || d > 6) throw Exception("Âge jours invalide (0..6).");
    if (_startedAt == null) throw Exception("Date de démarrage (startedAt) obligatoire.");
  }

  Future<void> _saveEdits({
    required String lotId,
    required Map<String, dynamic> activeBefore,
  }) async {
    _validate();

    final newStrain = _s(_strainCtrl);
    final newWeeks = _i(_ageWeeksCtrl);
    final newDays = _i(_ageDaysCtrl);
    final newStartedAt = _startedAt!;

    setState(() => _saving = true);

    try {
      final activeRef = _activeRef();
      final lotRef = _lotsCol().doc(lotId);
      final stockRef = _stockRef();
      final movementRef = _movementsCol().doc();

      await _db.runTransaction((tx) async {
        final activeSnap = await tx.get(activeRef);
        if (!activeSnap.exists || activeSnap.data()?['active'] != true) {
          throw Exception("Aucun lot actif à modifier.");
        }

        final currentLotId = _asStr(activeSnap.data()?['lotId']);
        if (currentLotId.isEmpty) throw Exception("lotId manquant dans building_active_lots.");
        if (currentLotId != lotId) {
          // protection: le lot a changé entre temps
          throw Exception("Le lot actif a changé, recharge l'écran.");
        }

        final lotSnap = await tx.get(lotRef);
        if (!lotSnap.exists) {
          throw Exception("Lot introuvable dans farms/$_farmId/lots/$lotId");
        }

        // (Optionnel) lecture stock pour mettre dans audit
        final stockSnap = await tx.get(stockRef);
        final stockQty = _asInt(stockSnap.data()?['totalOnHand']);

        final now = FieldValue.serverTimestamp();
        final startedTs = Timestamp.fromDate(newStartedAt);

        // 1) Update lot doc
        tx.set(
          lotRef,
          {
            'strain': newStrain,
            'startAgeWeeks': newWeeks,
            'startAgeDays': newDays,
            'startedAt': startedTs,
            'updatedAt': now,
            'source': 'mobile_app',
          },
          SetOptions(merge: true),
        );

        // 2) Update active pointer doc
        tx.set(
          activeRef,
          {
            'strain': newStrain,
            'startAgeWeeks': newWeeks,
            'startAgeDays': newDays,
            'startedAt': startedTs,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );

        // 3) Audit movement
        tx.set(movementRef, {
          'type': 'EDIT_ACTIVE_LOT',
          'lotId': lotId,
          'buildingId': widget.buildingId,
          'before': {
            'strain': _asStr(activeBefore['strain']),
            'startAgeWeeks': _asInt(activeBefore['startAgeWeeks']),
            'startAgeDays': _asInt(activeBefore['startAgeDays']),
            'startedAt': activeBefore['startedAt'],
          },
          'after': {
            'strain': newStrain,
            'startAgeWeeks': newWeeks,
            'startAgeDays': newDays,
            'startedAt': startedTs,
          },
          'stockOnHandAtEdit': stockQty,
          'createdAt': now,
          'source': 'mobile_app',
        });
      });

      _snack("✅ Lot actif modifié", true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack("❌ $e", false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeDocStream = _activeRef().snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text("Modifier lot actif - ${widget.buildingName}"),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: activeDocStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                "Erreur: ${snap.error}",
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data();
          final isActive = (data?['active'] == true);

          if (!isActive || data == null) {
            return const Center(
              child: Text(
                "Aucun lot actif sur ce bâtiment.",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final lotId = _asStr(data['lotId']);
          if (lotId.isEmpty) {
            return const Center(
              child: Text(
                "LotId manquant dans building_active_lots.",
                style: TextStyle(color: Colors.red),
              ),
            );
          }

          // Prefill une seule fois
          _prefillFromActive(data);

          final startedLabel = (_startedAt == null)
              ? "Non défini"
              : "${_startedAt!.year.toString().padLeft(4, '0')}-"
              "${_startedAt!.month.toString().padLeft(2, '0')}-"
              "${_startedAt!.day.toString().padLeft(2, '0')}";

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text("Lot actif: $lotId"),
                  subtitle: Text("Bâtiment: ${widget.buildingName}"),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _strainCtrl,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: "Souche",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ageWeeksCtrl,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Âge départ (semaines)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _ageDaysCtrl,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Âge départ (jours 0..6)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: const Text("Date de démarrage (startedAt)"),
                  subtitle: Text(startedLabel),
                  trailing: const Icon(Icons.edit),
                  onTap: _saving ? null : _pickStartedAt,
                ),
              ),

              const SizedBox(height: 16),

              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () => _saveEdits(
                  lotId: lotId,
                  activeBefore: Map<String, dynamic>.from(data),
                ),
                icon: _saving
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.save),
                label: Text(_saving ? "Enregistrement..." : "Enregistrer modifications"),
              ),
              const SizedBox(height: 8),

              OutlinedButton.icon(
                onPressed: _saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text("Annuler"),
              ),

              const SizedBox(height: 18),
              const Text(
                "Note: cet écran modifie le lot actif et le document lot correspondant. "
                    "Un mouvement d'audit (EDIT_ACTIVE_LOT) est aussi créé.",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}
