import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/subject_lot_service.dart';

class ActiveLotEditScreen extends StatefulWidget {
  final String buildingId;
  final String buildingName;

  const ActiveLotEditScreen({
    super.key,
    required this.buildingId,
    required this.buildingName,
  });

  @override
  State<ActiveLotEditScreen> createState() => _ActiveLotEditScreenState();
}

class _ActiveLotEditScreenState extends State<ActiveLotEditScreen> {
  final _strainCtrl = TextEditingController();
  final _ageWeeksCtrl = TextEditingController(text: '0');
  final _ageDaysCtrl = TextEditingController(text: '0');

  DateTime? _startedAtOverride; // optionnel

  bool _loading = true;
  bool _saving = false;

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green : Colors.red),
    );
  }

  DocumentReference<Map<String, dynamic>> get _activeRef =>
      FirebaseFirestore.instance
          .collection('farms')
          .doc(SubjectLotService.farmId)
          .collection('building_active_lots')
          .doc(widget.buildingId);

  String _asStr(dynamic v) => (v ?? '').toString();
  int _asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;

  @override
  void initState() {
    super.initState();
    _loadActiveLot();
  }

  Future<void> _loadActiveLot() async {
    setState(() => _loading = true);
    try {
      final snap = await _activeRef.get(const GetOptions(source: Source.serverAndCache));
      final data = snap.data();
      if (data == null || data['active'] != true) {
        _snack("Aucun lot actif dans ce bâtiment.", false);
        if (mounted) Navigator.pop(context);
        return;
      }

      _strainCtrl.text = _asStr(data['strain']);
      _ageWeeksCtrl.text = _asInt(data['startAgeWeeks']).toString();
      _ageDaysCtrl.text = _asInt(data['startAgeDays']).toString();
    } catch (e) {
      _snack("Erreur chargement: $e", false);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();

    final d = await showDatePicker(
      context: context,
      initialDate: _startedAtOverride ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (d == null) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAtOverride ?? now),
    );
    if (t == null) return;

    setState(() {
      _startedAtOverride = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _save() async {
    if (_saving) return;

    final strain = _strainCtrl.text.trim();
    final w = _i(_ageWeeksCtrl);
    final d = _i(_ageDaysCtrl);

    if (strain.isEmpty) {
      _snack("Souche obligatoire.", false);
      return;
    }
    if (w < 0 || d < 0 || d > 6) {
      _snack("Âge invalide (jours 0..6).", false);
      return;
    }

    setState(() => _saving = true);
    try {
      await SubjectLotService.updateActiveLotStrict(
        buildingId: widget.buildingId,
        strain: strain,
        startAgeWeeks: w,
        startAgeDays: d,
        startedAtOverride: _startedAtOverride,
      );

      _snack("✅ Lot actif modifié", true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString(), false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _strainCtrl.dispose();
    _ageWeeksCtrl.dispose();
    _ageDaysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Modifier lot - ${widget.buildingName}"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _strainCtrl,
            decoration: const InputDecoration(
              labelText: "Souche (ex: ISA Brown)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ageWeeksCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Âge (semaines)",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ageDaysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Âge (jours 0..6)",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Optionnel : date de démarrage",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _startedAtOverride == null
                        ? "Aucun changement (conserve startedAt actuel)"
                        : "Nouveau startedAt : $_startedAtOverride",
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _pickDateTime,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text("Choisir date/heure"),
                  ),
                  if (_startedAtOverride != null)
                    TextButton(
                      onPressed: () => setState(() => _startedAtOverride = null),
                      child: const Text("Annuler le changement"),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_saving ? "Enregistrement..." : "Enregistrer"),
          ),
        ],
      ),
    );
  }
}
