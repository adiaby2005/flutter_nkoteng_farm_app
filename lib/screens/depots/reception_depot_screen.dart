import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/depot_service.dart';
import '../../utils/units.dart';

class ReceptionDepotScreen extends StatefulWidget {
  const ReceptionDepotScreen({super.key, required this.farmId});
  final String farmId;

  @override
  State<ReceptionDepotScreen> createState() => _ReceptionDepotScreenState();
}

class _ReceptionDepotScreenState extends State<ReceptionDepotScreen> {
  late final DepotService service;

  bool _loading = true;
  String? _error;

  QueryDocumentSnapshot<Map<String, dynamic>>? _transferDoc;

  // champs éditables
  String _depotId = 'depot_1'; // adapte si tu as une liste de dépôts
  final _noteCtrl = TextEditingController();

  // On gère en alvéoles, mais on affiche/édite en cartons + reste
  // calibres usuels (adapte à ton app)
  final List<String> _calibers = const ['S', 'M', 'L', 'XL'];

  // saisie : cartons + alvéoles restantes par calibre
  final Map<String, TextEditingController> _cartonsCtrls = {};
  final Map<String, TextEditingController> _alveolesRemaCtrls = {};

  @override
  void initState() {
    super.initState();
    service = DepotService(FirebaseFirestore.instance);
    for (final c in _calibers) {
      _cartonsCtrls[c] = TextEditingController(text: '0');
      _alveolesRemaCtrls[c] = TextEditingController(text: '0');
    }
    _loadPrefill();
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

  Future<void> _loadPrefill() async {
    setState(() {
      _loading = true;
      _error = null;
      _transferDoc = null;
    });

    try {
      final doc = await service.getLatestPendingTransfer(widget.farmId);
      if (doc == null) {
        setState(() {
          _loading = false;
          _transferDoc = null;
        });
        return;
      }

      final data = doc.data();
      _transferDoc = doc;

      // Prefill depotId si présent sur transfert
      final depotId = (data['depotId'] as String?) ?? _depotId;
      _depotId = depotId;

      // Prefill quantités si présent
      final raw = (data['alveolesByCaliber'] as Map?)?.cast<String, dynamic>() ?? {};
      for (final c in _calibers) {
        final alveoles = (raw[c] is num) ? (raw[c] as num).toInt() : 0;
        final cartons = Units.alveolesToFullCartons(alveoles);
        final rem = Units.alveolesRemainder(alveoles);
        _cartonsCtrls[c]!.text = cartons.toString();
        _alveolesRemaCtrls[c]!.text = rem.toString();
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Map<String, int> _buildAlveolesByCaliber() {
    final out = <String, int>{};
    for (final c in _calibers) {
      final cartons = _toInt(_cartonsCtrls[c]!.text);
      final rem = _toInt(_alveolesRemaCtrls[c]!.text);
      final alveoles = (cartons * Units.alveolesPerCarton) + rem;
      out[c] = alveoles < 0 ? 0 : alveoles;
    }
    return out;
  }

  int _totalAlveoles(Map<String, int> m) => m.values.fold<int>(0, (a, b) => a + b);

  Future<void> _validateReception() async {
    final transfer = _transferDoc;
    if (transfer == null) return;

    final alveolesByCaliber = _buildAlveolesByCaliber();
    final total = _totalAlveoles(alveolesByCaliber);
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantité invalide : total = 0.')),
      );
      return;
    }

    try {
      await service.receiveTransfer(
        farmId: widget.farmId,
        transferDocId: transfer.id,
        depotId: _depotId,
        alveolesByCaliber: alveolesByCaliber,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Réception dépôt validée ✅')),
      );

      // recharge pour prendre le prochain transfert en attente
      await _loadPrefill();
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
                      hintText: 'ex: 3',
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
                      hintText: '0..11',
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
    final transfer = _transferDoc;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réception dépôt'),
        actions: [
          IconButton(
            tooltip: 'Recharger',
            onPressed: _loadPrefill,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
          ? Center(child: Text('Erreur: $_error'))
          : (transfer == null)
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox, size: 48),
              const SizedBox(height: 10),
              const Text(
                'Aucun transfert dépôt en attente de réception.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadPrefill,
                icon: const Icon(Icons.refresh),
                label: const Text('Rafraîchir'),
              ),
            ],
          ),
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              title: const Text('Transfert source'),
              subtitle: Text('ID: ${transfer.id}'),
              trailing: const Icon(Icons.receipt_long),
            ),
          ),
          const SizedBox(height: 10),

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
            onPressed: _validateReception,
            icon: const Icon(Icons.check_circle),
            label: const Text('Valider la réception'),
          ),
        ],
      ),
    );
  }
}
