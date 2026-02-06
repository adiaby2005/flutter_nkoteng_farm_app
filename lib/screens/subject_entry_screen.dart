import 'package:flutter/material.dart';
import '../services/subject_lot_service.dart';

class SubjectEntryScreen extends StatefulWidget {
  final String buildingId;
  final String buildingName;

  const SubjectEntryScreen({
    super.key,
    required this.buildingId,
    required this.buildingName,
  });

  @override
  State<SubjectEntryScreen> createState() => _SubjectEntryScreenState();
}

class _SubjectEntryScreenState extends State<SubjectEntryScreen> {
  final _strainCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '0');
  final _ageWeeksCtrl = TextEditingController(text: '0');
  final _ageDaysCtrl = TextEditingController(text: '0');

  bool _saving = false;

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

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
    _qtyCtrl.dispose();
    _ageWeeksCtrl.dispose();
    _ageDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final lotId = await SubjectLotService.enterLotStrict(
        buildingId: widget.buildingId,
        strain: _strainCtrl.text.trim(),
        qtyIn: _i(_qtyCtrl),
        startAgeWeeks: _i(_ageWeeksCtrl),
        startAgeDays: _i(_ageDaysCtrl),
      );

      _snack("✅ Lot créé: $lotId", true);
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
      appBar: AppBar(
        title: Text("Entrée lot - ${widget.buildingName}"),
      ),
      body: ListView(
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
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Nombre de sujets à entrer",
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
