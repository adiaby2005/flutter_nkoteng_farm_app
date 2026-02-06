import 'package:flutter/material.dart';
import '../services/subject_lot_service.dart';

class SubjectOutStrictScreen extends StatefulWidget {
  final String buildingId;
  final String buildingName;

  const SubjectOutStrictScreen({
    super.key,
    required this.buildingId,
    required this.buildingName,
  });

  @override
  State<SubjectOutStrictScreen> createState() => _SubjectOutStrictScreenState();
}

class _SubjectOutStrictScreenState extends State<SubjectOutStrictScreen> {
  final _qtyCtrl = TextEditingController(text: '0');

  String _kind = 'SALE'; // SALE | REFORM

  // sale info
  final _buyerCtrl = TextEditingController();
  final _unitPriceCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();

  bool _saving = false;

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green : Colors.red),
    );
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _buyerCtrl.dispose();
    _unitPriceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final qty = _i(_qtyCtrl);
    if (qty <= 0) {
      _snack("Quantité invalide", false);
      return;
    }

    setState(() => _saving = true);
    try {
      Map<String, dynamic>? saleInfo;
      if (_kind == 'SALE') {
        final unitPrice = _i(_unitPriceCtrl);
        saleInfo = {
          'buyerName': _buyerCtrl.text.trim().isEmpty ? null : _buyerCtrl.text.trim(),
          'unitPrice': unitPrice,
          'totalAmount': unitPrice * qty,
          'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        };
      }

      await SubjectLotService.outStrict(
        buildingId: widget.buildingId,
        qty: qty,
        outKind: _kind,
        saleInfo: saleInfo,
      );

      _snack("✅ Sortie STRICT ($_kind) effectuée", true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e.toString(), false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSale = _kind == 'SALE';

    return Scaffold(
      appBar: AppBar(
        title: Text("Réforme / Vente - ${widget.buildingName}"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: const InputDecoration(
              labelText: "Type de sortie",
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'SALE', child: Text("Vente")),
              DropdownMenuItem(value: 'REFORM', child: Text("Réforme")),
            ],
            onChanged: _saving ? null : (v) => setState(() => _kind = v ?? 'SALE'),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Quantité à sortir",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 12),

          if (isSale) ...[
            TextField(
              controller: _buyerCtrl,
              decoration: const InputDecoration(
                labelText: "Acheteur (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitPriceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Prix unitaire (FCFA)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: "Note (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),
          ],

          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.exit_to_app),
            label: Text(_saving ? "Enregistrement..." : "Enregistrer (STRICT)"),
          ),
        ],
      ),
    );
  }
}
