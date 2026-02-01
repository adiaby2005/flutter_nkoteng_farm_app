import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../utils/units.dart';

class DepotAdjustmentScreen extends StatefulWidget {
  const DepotAdjustmentScreen({super.key, required this.farmId});
  final String farmId;

  @override
  State<DepotAdjustmentScreen> createState() => _DepotAdjustmentScreenState();
}

class _DepotAdjustmentScreenState extends State<DepotAdjustmentScreen> {
  final List<String> _calibers = const ['S', 'M', 'L', 'XL'];

  String _depotId = 'depot_1';
  String _reason = 'CASSE'; // ou RECALIBRAGE
  final _noteCtrl = TextEditingController();

  final Map<String, TextEditingController> _cartonsCtrls = {};
  final Map<String, TextEditingController> _alveolesRemaCtrls = {};

  @override
  void initState() {
    super.initState();
    for (final c in _calibers) {
      _cartonsCtrls[c] = TextEditingController(text: '0');
      _alveolesRemaCtrls[c] = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    for (final c in _calibers) {
      _cartonsCtrls[c]?.dispose();
      _alveolesRemaCtrls[c]?.dispose();
    }
    super.dispose();
  }

  int _toInt(String v) => int.tryParse(v.trim()) ?? 0;

  Map<String, int> _buildAlveolesByCaliber() {
    final out = <String, int>{};
    for (final c in _calibers) {
      final cartons = _toInt(_cartonsCtrls[c]!.text);
      final rem = _toInt(_alveolesRemaCtrls[c]!.text);
      final alveoles = cartons * Units.alveolesPerCarton + rem;
      out[c] = alveoles < 0 ? 0 : alveoles;
    }
    return out;
  }

  int _totalAlveoles(Map<String, int> m) => m.values.fold<int>(0, (a, b) => a + b);

  Future<void> _saveAdjustment() async {
    final alveolesByCaliber = _buildAlveolesByCaliber();
    final total = _totalAlveoles(alveolesByCaliber);
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantité invalide : total = 0.')),
      );
      return;
    }

    try {
      final ref = FirebaseFirestore.instance
          .collection('farms')
          .doc(widget.farmId)
          .collection('daily_entry_adjustments')
          .doc();

      await ref.set({
        'depotId': _depotId,
        'reason': _reason, // CASSE / RECALIBRAGE / AUTRE
        'alveolesByCaliber': alveolesByCaliber,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajustement dépôt enregistré ✅')),
      );

      // reset
      for (final c in _calibers) {
        _cartonsCtrls[c]!.text = '0';
        _alveolesRemaCtrls[c]!.text = '0';
      }
      _noteCtrl.clear();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Widget _qtyRow(String caliber) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Calibre $caliber', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cartonsCtrls[caliber],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cartons',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _alveolesRemaCtrls[caliber],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Alvéoles (reste)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Builder(
              builder: (_) {
                final cartons = _toInt(_cartonsCtrls[caliber]!.text);
                final rem = _toInt(_alveolesRemaCtrls[caliber]!.text);
                final alveoles = cartons * Units.alveolesPerCarton + rem;
                return Text(
                  'Total: ${Units.formatCartonsAlveoles(alveoles)} (${alveoles} alvéoles)',
                  style: TextStyle(color: Colors.grey.shade700),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustement dépôt')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Depot ID',
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: _depotId),
                    onChanged: (v) => _depotId = v.trim().isEmpty ? _depotId : v.trim(),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _reason,
                    decoration: const InputDecoration(
                      labelText: 'Motif',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CASSE', child: Text('Casse')),
                      DropdownMenuItem(value: 'RECALIBRAGE', child: Text('Recalibrage')),
                      DropdownMenuItem(value: 'AUTRE', child: Text('Autre')),
                    ],
                    onChanged: (v) => setState(() => _reason = v ?? 'CASSE'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note (optionnel)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          ..._calibers.map(_qtyRow),

          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _saveAdjustment,
            icon: const Icon(Icons.save),
            label: const Text('Enregistrer ajustement'),
          ),
          const SizedBox(height: 8),
          Text(
            'Rappel: 1 carton = ${Units.alveolesPerCarton} alvéoles.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
