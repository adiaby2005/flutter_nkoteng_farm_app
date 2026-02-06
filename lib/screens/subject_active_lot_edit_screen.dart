import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/subject_lot_service.dart';

class SubjectActiveLotEditScreen extends StatefulWidget {
  final String buildingId;
  final String buildingName;

  const SubjectActiveLotEditScreen({
    super.key,
    required this.buildingId,
    required this.buildingName,
  });

  @override
  State<SubjectActiveLotEditScreen> createState() => _SubjectActiveLotEditScreenState();
}

class _SubjectActiveLotEditScreenState extends State<SubjectActiveLotEditScreen> {
  final _strainCtrl = TextEditingController();
  final _weeksCtrl = TextEditingController(text: '0');
  final _daysCtrl = TextEditingController(text: '0');

  bool _loading = true;
  bool _saving = false;
  String? _err;

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green : Colors.red),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _strainCtrl.dispose();
    _weeksCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final farmRef = FirebaseFirestore.instance
          .collection('farms')
          .doc(SubjectLotService.farmId);

      final snap = await farmRef
          .collection('building_active_lots')
          .doc(widget.buildingId)
          .get(const GetOptions(source: Source.server));

      if (!snap.exists || snap.data()?['active'] != true) {
        throw Exception("Aucun lot actif sur ce bâtiment.");
      }

      final data = snap.data() ?? {};
      _strainCtrl.text = (data['strain'] ?? '').toString();
      _weeksCtrl.text = ((data['startAgeWeeks'] is num) ? (data['startAgeWeeks'] as num).toInt() : 0).toString();
      _daysCtrl.text = ((data['startAgeDays'] is num) ? (data['startAgeDays'] as num).toInt() : 0).toString();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await SubjectLotService.updateActiveLotMeta(
        buildingId: widget.buildingId,
        strain: _strainCtrl.text.trim(),
        startAgeWeeks: _i(_weeksCtrl),
        startAgeDays: _i(_daysCtrl),
      );

      _snack("✅ Lot actif mis à jour", true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString(), false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Modifier lot actif - ${widget.buildingName}")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(child: Text(_err!, style: const TextStyle(color: Colors.red)))
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  controller: _weeksCtrl,
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
                  controller: _daysCtrl,
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
