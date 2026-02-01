import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/building.dart';
import '../services/active_lot_service.dart';

class DailyEntryScreen extends StatefulWidget {
  final Building building;

  const DailyEntryScreen({super.key, required this.building});

  @override
  State<DailyEntryScreen> createState() => _DailyEntryScreenState();
}

class _DailyEntryScreenState extends State<DailyEntryScreen> {
  // =========================
  // PONTE par calibre
  // =========================
  final Map<String, TextEditingController> _alveolesCtrls = {
    'SMALL': TextEditingController(),
    'MEDIUM': TextEditingController(),
    'LARGE': TextEditingController(),
    'XL': TextEditingController(),
  };

  final Map<String, TextEditingController> _isolatedCtrls = {
    'SMALL': TextEditingController(),
    'MEDIUM': TextEditingController(),
    'LARGE': TextEditingController(),
    'XL': TextEditingController(),
  };

  // =========================
  // CASSES (collecte bâtiment)
  // =========================
  final TextEditingController _brokenAlveolesCtrl = TextEditingController();
  final TextEditingController _brokenIsolatedCtrl = TextEditingController();
  final TextEditingController _brokenNoteCtrl = TextEditingController();

  // =========================
  // ALIMENTS (sacs 50 kg)
  // =========================
  final TextEditingController _feedBagsCtrl = TextEditingController(text: "0");
  String? _selectedFeedItemId;
  Map<String, dynamic>? _buildingFreshData;

  // =========================
  // EAU (litres)
  // =========================
  String _waterMode = 'MANUAL'; // MANUAL | ESTIMATE
  final TextEditingController _waterLitersCtrl = TextEditingController(text: "0");
  final TextEditingController _waterNoteCtrl = TextEditingController();
  int _waterEstimatedLiters = 0;

  // =========================
  // MORTALITÉ
  // =========================
  final TextEditingController _mortalityQtyCtrl = TextEditingController(text: "0");
  final TextEditingController _mortalityCauseCtrl = TextEditingController();
  final TextEditingController _mortalityNoteCtrl = TextEditingController();

  // =========================
  // VÉTÉRINAIRE (utilisation)
  // =========================
  bool _noVetTreatment = false;
  String? _selectedVetItemId;
  final TextEditingController _vetQtyCtrl = TextEditingController(text: "0");
  final TextEditingController _vetNoteCtrl = TextEditingController();

  int? _vetStockOnHand;
  String _vetUnitLabel = "unité";

  // =========================
  // State
  // =========================
  bool _loading = false;
  String? _message;
  DateTime _selectedDate = DateTime.now();

  final _db = FirebaseFirestore.instance;

  static const String _farmId = 'farm_nkoteng';

  // -------------------------
  // Formatters (contrôle saisie)
  // -------------------------
  final List<TextInputFormatter> _digitsOnly = [
    FilteringTextInputFormatter.digitsOnly,
  ];

  // ✅ Isolés: 0..29 (si tu veux 1..29, remplace min=0 par min=1 dans _MinMaxIntFormatter)
  final List<TextInputFormatter> _isolatedFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    const _MinMaxIntFormatter(min: 0, max: 29),
  ];

  @override
  void initState() {
    super.initState();
    _loadBuildingFresh();
  }

  Future<void> _loadBuildingFresh() async {
    try {
      final doc = await _db
          .collection('farms')
          .doc(_farmId)
          .collection('buildings')
          .doc(widget.building.id)
          .get();

      if (doc.exists) {
        setState(() {
          _buildingFreshData = doc.data();

          final def = _defaultFeedItemIdFromBuilding();
          if (_selectedFeedItemId == null && def != null) {
            _selectedFeedItemId = def;
          }
        });
      }
    } catch (_) {
      // offline / permissions : ignore
    }
  }

  @override
  void dispose() {
    for (final c in _alveolesCtrls.values) {
      c.dispose();
    }
    for (final c in _isolatedCtrls.values) {
      c.dispose();
    }

    _brokenAlveolesCtrl.dispose();
    _brokenIsolatedCtrl.dispose();
    _brokenNoteCtrl.dispose();

    _feedBagsCtrl.dispose();

    _waterLitersCtrl.dispose();
    _waterNoteCtrl.dispose();

    _mortalityQtyCtrl.dispose();
    _mortalityCauseCtrl.dispose();
    _mortalityNoteCtrl.dispose();

    _vetQtyCtrl.dispose();
    _vetNoteCtrl.dispose();

    super.dispose();
  }

  // =========================
  // Utils
  // =========================
  String _dateIso(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  String _dailyEntryDocId(String dateIso) => "${widget.building.id}_$dateIso";

  DocumentReference<Map<String, dynamic>> _dailyEntryRef(String dateIso) {
    return _db.collection('farms').doc(_farmId).collection('daily_entries').doc(_dailyEntryDocId(dateIso));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  int _parseInt(TextEditingController c) {
    return int.tryParse(c.text.trim()) ?? 0;
  }

  int _getInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  bool _validateIsolated0to29(int v) => v >= 0 && v <= 29;

  int _totalEggsForGrade(String grade) {
    final alveoles = _parseInt(_alveolesCtrls[grade]!);
    final isolated = _parseInt(_isolatedCtrls[grade]!);
    return alveoles * 30 + isolated;
  }

  int _totalEggsAllGrades() {
    int total = 0;
    for (final g in _alveolesCtrls.keys) {
      total += _totalEggsForGrade(g);
    }
    return total;
  }

  String? _defaultFeedItemIdFromBuilding() {
    final data = _buildingFreshData;
    final v = data == null ? null : data['defaultFeedItemId'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  // =========================
  // ESTIMATION EAU ✅ FIX cast int/num/String
  // =========================
  Future<int> _computeEstimatedWaterLiters() async {
    final farmRef = _db.collection('farms').doc(_farmId);
    final doc = await farmRef.collection('building_active_lots').doc(widget.building.id).get();

    final qtyRaw = doc.data()?['qty'];
    final qty = _getInt(qtyRaw);

    // 0.25 L / sujet / jour
    return (qty * 0.25).round();
  }

  // =========================
  // Validations
  // =========================
  void _validateVetBeforeSave() {
    if (_noVetTreatment) return;

    final itemId = _selectedVetItemId;
    final qty = _parseInt(_vetQtyCtrl);

    if ((itemId == null || itemId.isEmpty) && qty > 0) {
      throw Exception("Vétérinaire : sélectionnez un produit.");
    }
    if (itemId != null && itemId.isNotEmpty && qty <= 0) {
      throw Exception("Vétérinaire : quantité > 0 requise.");
    }

    if (_vetStockOnHand != null && qty > _vetStockOnHand!) {
      throw Exception("Vétérinaire : quantité ($qty) > stock (${_vetStockOnHand!}).");
    }
  }

  // =========================
  // Enregistrement "tout en un"
  // =========================
  Future<void> _saveAll() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    final List<String> ok = [];
    try {
      _validateVetBeforeSave();

      final dateIso = _dateIso(_selectedDate);

      await _dailyEntryRef(dateIso).set({
        'date': dateIso,
        'buildingId': widget.building.id,
        'buildingName': widget.building.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      }, SetOptions(merge: true));

      final prodRes = await _saveProductionIfAny(dateIso);
      if (prodRes != null) ok.add(prodRes);

      final brokenRes = await _saveBrokenIfAny(dateIso);
      if (brokenRes != null) ok.add(brokenRes);

      final feedRes = await _saveFeedIfAny(dateIso);
      if (feedRes != null) ok.add(feedRes);

      final waterRes = await _saveWaterIfAny(dateIso);
      if (waterRes != null) ok.add(waterRes);

      final vetRes = await _saveVetUseIfAny(dateIso);
      if (vetRes != null) ok.add(vetRes);

      final mortRes = await _saveMortalityIfAny(dateIso);
      if (mortRes != null) ok.add(mortRes);

      if (ok.isEmpty) {
        setState(() => _message = "Rien à enregistrer (tous les champs sont vides).");
        return;
      }

      await _dailyEntryRef(dateIso).set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() => _message = "Enregistré : ${ok.join(' • ')}");
    } catch (e) {
      setState(() => _message = "Erreur : ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =========================
  // PONTE ✅ + maj BUILDING_* ET FARM_GLOBAL
  // =========================
  Future<String?> _saveProductionIfAny(String dateIso) async {
    for (final g in _isolatedCtrls.keys) {
      final iso = _parseInt(_isolatedCtrls[g]!);
      if (!_validateIsolated0to29(iso)) {
        throw Exception("Œufs isolés ($g) doit être entre 0 et 29.");
      }
    }

    final totalEggs = _totalEggsAllGrades();
    if (totalEggs <= 0) return null;

    final lotId = await ActiveLotService.getActiveLotIdForBuilding(widget.building.id);

    final uniqueKey = [
      'PRODUCTION',
      _farmId,
      dateIso,
      widget.building.id,
    ].join('|');

    final farmRef = _db.collection('farms').doc(_farmId);
    final lockRef = farmRef.collection('idempotency').doc(uniqueKey);

    final prodRef = farmRef.collection('daily_production').doc();
    final stockBuildingRef = farmRef.collection('stocks_eggs').doc("BUILDING_${widget.building.id}");
    final stockFarmRef = farmRef.collection('stocks_eggs').doc("FARM_GLOBAL");
    final entryRef = _dailyEntryRef(dateIso);

    final Map<String, int> eggsByGrade = {
      'SMALL': _totalEggsForGrade('SMALL'),
      'MEDIUM': _totalEggsForGrade('MEDIUM'),
      'LARGE': _totalEggsForGrade('LARGE'),
      'XL': _totalEggsForGrade('XL'),
    };

    bool didWrite = false;

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        didWrite = false;
        return;
      }

      final buildingSnap = await tx.get(stockBuildingRef);
      final farmSnap = await tx.get(stockFarmRef);

      didWrite = true;

      tx.set(prodRef, {
        'date': dateIso,
        'buildingId': widget.building.id,
        'lotId': lotId,
        'eggsByGrade': eggsByGrade,
        'totalEggs': totalEggs,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      });

      // BUILDING STOCK
      final Map<String, dynamic> bData = buildingSnap.exists ? (buildingSnap.data() ?? {}) : <String, dynamic>{};
      final Map<String, dynamic> bByGradeDyn = (bData['eggsByGrade'] is Map)
          ? Map<String, dynamic>.from(bData['eggsByGrade'])
          : <String, dynamic>{};

      final int bSmall = _getInt(bByGradeDyn['SMALL']);
      final int bMed = _getInt(bByGradeDyn['MEDIUM']);
      final int bLarge = _getInt(bByGradeDyn['LARGE']);
      final int bXl = _getInt(bByGradeDyn['XL']);

      final Map<String, int> bNewByGrade = {
        'SMALL': bSmall + (eggsByGrade['SMALL'] ?? 0),
        'MEDIUM': bMed + (eggsByGrade['MEDIUM'] ?? 0),
        'LARGE': bLarge + (eggsByGrade['LARGE'] ?? 0),
        'XL': bXl + (eggsByGrade['XL'] ?? 0),
      };

      final int bGoodTotal = _getInt(bData['goodTotalEggs'] ?? bData['totalGoodEggs']);

      tx.set(
        stockBuildingRef,
        {
          'kind': 'BUILDING',
          'refId': widget.building.id,
          'eggsByGrade': bNewByGrade,
          'goodByGrade': bNewByGrade,
          'goodTotalEggs': bGoodTotal + totalEggs,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // FARM_GLOBAL STOCK
      final Map<String, dynamic> fData = farmSnap.exists ? (farmSnap.data() ?? {}) : <String, dynamic>{};
      final Map<String, dynamic> fByGradeDyn = (fData['eggsByGrade'] is Map)
          ? Map<String, dynamic>.from(fData['eggsByGrade'])
          : (fData['goodByGrade'] is Map)
          ? Map<String, dynamic>.from(fData['goodByGrade'])
          : <String, dynamic>{};

      final int fSmall = _getInt(fByGradeDyn['SMALL']);
      final int fMed = _getInt(fByGradeDyn['MEDIUM']);
      final int fLarge = _getInt(fByGradeDyn['LARGE']);
      final int fXl = _getInt(fByGradeDyn['XL']);

      final Map<String, int> fNewByGrade = {
        'SMALL': fSmall + (eggsByGrade['SMALL'] ?? 0),
        'MEDIUM': fMed + (eggsByGrade['MEDIUM'] ?? 0),
        'LARGE': fLarge + (eggsByGrade['LARGE'] ?? 0),
        'XL': fXl + (eggsByGrade['XL'] ?? 0),
      };

      final int fGoodTotal = _getInt(fData['goodTotalEggs'] ?? fData['totalGoodEggs']);

      tx.set(
        stockFarmRef,
        {
          'kind': 'FARM',
          'refId': 'FARM_GLOBAL',
          'eggsByGrade': fNewByGrade,
          'goodByGrade': fNewByGrade,
          'goodTotalEggs': fGoodTotal + totalEggs,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        entryRef,
        {
          'production': {
            'lotId': lotId,
            'eggsByGrade': eggsByGrade,
            'totalEggs': totalEggs,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      tx.set(lockRef, {
        'kind': 'DAILY_PRODUCTION',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    if (!didWrite) return "Ponte déjà enregistrée";

    for (final c in _alveolesCtrls.values) c.clear();
    for (final c in _isolatedCtrls.values) c.clear();

    return "Ponte OK (+$totalEggs)";
  }

  // =========================
  // CASSES ✅ + maj BUILDING_* ET FARM_GLOBAL
  // =========================
  Future<String?> _saveBrokenIfAny(String dateIso) async {
    final brokenAlv = _parseInt(_brokenAlveolesCtrl);
    final brokenIso = _parseInt(_brokenIsolatedCtrl);

    if (brokenAlv < 0 || brokenIso < 0) {
      throw Exception("Casses : valeurs négatives interdites.");
    }
    if (brokenAlv == 0 && brokenIso == 0) return null;

    if (!_validateIsolated0to29(brokenIso)) {
      throw Exception("Casses : œufs isolés doit être entre 0 et 29.");
    }

    final totalBroken = brokenAlv * 30 + brokenIso;
    if (totalBroken <= 0) return null;

    final farmRef = _db.collection('farms').doc(_farmId);

    final uniqueKey = [
      'BROKEN_IN',
      _farmId,
      dateIso,
      widget.building.id,
      brokenAlv.toString(),
      brokenIso.toString(),
    ].join('|');

    final lockRef = farmRef.collection('idempotency').doc(uniqueKey);
    final inflowRef = farmRef.collection('broken_egg_inflows').doc();
    final stockBuildingRef = farmRef.collection('stocks_eggs').doc("BUILDING_${widget.building.id}");
    final stockFarmRef = farmRef.collection('stocks_eggs').doc("FARM_GLOBAL");
    final entryRef = _dailyEntryRef(dateIso);

    final note = _brokenNoteCtrl.text.trim().isEmpty ? null : _brokenNoteCtrl.text.trim();

    bool didWrite = false;

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        didWrite = false;
        return;
      }

      final bSnap = await tx.get(stockBuildingRef);
      final fSnap = await tx.get(stockFarmRef);

      didWrite = true;

      final int bCurrentBroken = bSnap.exists ? _getInt(bSnap.data()?['brokenTotalEggs']) : 0;
      final int fCurrentBroken = fSnap.exists ? _getInt(fSnap.data()?['brokenTotalEggs']) : 0;

      tx.set(inflowRef, {
        'date': dateIso,
        'buildingId': widget.building.id,
        'type': 'DAILY_COLLECTION',
        'brokenAlveoles': brokenAlv,
        'brokenIsolated': brokenIso,
        'totalBrokenEggs': totalBroken,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      });

      tx.set(
        stockBuildingRef,
        {
          'kind': 'BUILDING',
          'refId': widget.building.id,
          'brokenTotalEggs': bCurrentBroken + totalBroken,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        stockFarmRef,
        {
          'kind': 'FARM',
          'refId': 'FARM_GLOBAL',
          'brokenTotalEggs': fCurrentBroken + totalBroken,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        entryRef,
        {
          'broken': {
            'brokenAlveoles': brokenAlv,
            'brokenIsolated': brokenIso,
            'totalBrokenEggs': totalBroken,
            'note': note,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      tx.set(lockRef, {
        'kind': 'BROKEN_EGG_INFLOW',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    if (!didWrite) return "Casses déjà enregistrées";

    _brokenAlveolesCtrl.clear();
    _brokenIsolatedCtrl.clear();
    _brokenNoteCtrl.clear();

    return "Casses OK (+$totalBroken)";
  }

  // =========================
  // ALIMENTS
  // =========================
  Future<String?> _saveFeedIfAny(String dateIso) async {
    final bags = _parseInt(_feedBagsCtrl);
    if (bags < 0) throw Exception("Aliments : sacs négatifs interdits.");
    if (bags == 0) return null;

    final feedItemId = _selectedFeedItemId;
    if (feedItemId == null || feedItemId.isEmpty) {
      throw Exception("Aliments : veuillez sélectionner un aliment.");
    }

    final farmRef = _db.collection('farms').doc(_farmId);

    final uniqueKey = [
      'FEED_CONS',
      _farmId,
      dateIso,
      widget.building.id,
      feedItemId,
      bags.toString(),
    ].join('|');

    final lockRef = farmRef.collection('idempotency').doc(uniqueKey);
    final consRef = farmRef.collection('feed_consumptions').doc();
    final entryRef = _dailyEntryRef(dateIso);

    bool didWrite = false;

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        didWrite = false;
        return;
      }
      didWrite = true;

      tx.set(consRef, {
        'date': dateIso,
        'buildingId': widget.building.id,
        'itemId': feedItemId,
        'bags50kg': bags,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      });

      tx.set(
        entryRef,
        {
          'feed': {
            'itemId': feedItemId,
            'bags50kg': bags,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      tx.set(lockRef, {
        'kind': 'FEED_CONSUMPTION',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    if (!didWrite) return "Aliments déjà enregistrés";

    _feedBagsCtrl.text = "0";
    return "Aliments OK (-$bags sacs)";
  }

  // =========================
  // EAU
  // =========================
  Future<String?> _saveWaterIfAny(String dateIso) async {
    final liters = int.tryParse(_waterLitersCtrl.text.trim()) ?? 0;
    if (liters < 0) throw Exception("Eau : litres négatifs interdits.");
    if (liters == 0) return null;

    final farmRef = _db.collection('farms').doc(_farmId);

    final uniqueKey = [
      'WATER',
      _farmId,
      dateIso,
      widget.building.id,
      _waterMode,
      liters.toString(),
    ].join('|');

    final lockRef = farmRef.collection('idempotency').doc(uniqueKey);
    final waterRef = farmRef.collection('daily_water_consumption').doc();
    final entryRef = _dailyEntryRef(dateIso);

    final note = _waterNoteCtrl.text.trim().isEmpty ? null : _waterNoteCtrl.text.trim();

    bool didWrite = false;

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        didWrite = false;
        return;
      }
      didWrite = true;

      tx.set(waterRef, {
        'date': dateIso,
        'buildingId': widget.building.id,
        'mode': _waterMode,
        'liters': liters,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      });

      tx.set(
        entryRef,
        {
          'water': {
            'mode': _waterMode,
            'liters': liters,
            'note': note,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      tx.set(lockRef, {
        'kind': 'WATER_CONSUMPTION',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    if (!didWrite) return "Eau déjà enregistrée";

    _waterLitersCtrl.text = "0";
    _waterNoteCtrl.clear();

    return "Eau OK (-$liters L)";
  }

  // =========================
  // VÉTÉRINAIRE
  // =========================
  Future<String?> _saveVetUseIfAny(String dateIso) async {
    if (_noVetTreatment) return null;

    final itemId = _selectedVetItemId;
    final qty = _parseInt(_vetQtyCtrl);
    if (itemId == null || itemId.isEmpty || qty <= 0) return null;

    final farmRef = _db.collection('farms').doc(_farmId);

    final uniqueKey = [
      'VET_USE',
      _farmId,
      dateIso,
      widget.building.id,
      itemId,
      qty.toString(),
    ].join('|');

    final lockRef = farmRef.collection('idempotency').doc(uniqueKey);
    final useRef = farmRef.collection('vet_usages').doc();
    final entryRef = _dailyEntryRef(dateIso);

    final note = _vetNoteCtrl.text.trim().isEmpty ? null : _vetNoteCtrl.text.trim();

    bool didWrite = false;

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        didWrite = false;
        return;
      }

      didWrite = true;

      tx.set(useRef, {
        'date': dateIso,
        'buildingId': widget.building.id,
        'itemId': itemId,
        'qty': qty,
        'unit': _vetUnitLabel,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      });

      tx.set(
        entryRef,
        {
          'vet': {
            'itemId': itemId,
            'qty': qty,
            'unit': _vetUnitLabel,
            'note': note,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      tx.set(lockRef, {
        'kind': 'VET_USAGE',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    if (!didWrite) return "Vétérinaire déjà enregistré";

    _selectedVetItemId = null;
    _vetQtyCtrl.text = "0";
    _vetNoteCtrl.clear();
    _vetStockOnHand = null;
    _vetUnitLabel = "unité";

    return "Vétérinaire OK (-$qty $_vetUnitLabel)";
  }

  // =========================
  // MORTALITÉ ✅ SANS MortalityService (direct Firestore)
  // =========================
  Future<String?> _saveMortalityIfAny(String dateIso) async {
    final qty = _parseInt(_mortalityQtyCtrl);
    if (qty < 0) throw Exception("Mortalité : quantité négative interdite.");
    if (qty == 0) return null;

    final lotId = await ActiveLotService.getActiveLotIdForBuilding(widget.building.id);
    final farmRef = _db.collection('farms').doc(_farmId);

    final cause = _mortalityCauseCtrl.text.trim().isEmpty ? null : _mortalityCauseCtrl.text.trim();
    final note = _mortalityNoteCtrl.text.trim().isEmpty ? null : _mortalityNoteCtrl.text.trim();

    final uniqueKey = [
      'MORTALITY',
      _farmId,
      dateIso,
      widget.building.id,
      qty.toString(),
      (cause ?? ''),
      (note ?? ''),
    ].join('|');

    final lockRef = farmRef.collection('idempotency').doc(uniqueKey);
    final mortRef = farmRef.collection('mortalities').doc(); // ✅ collection simple
    final entryRef = _dailyEntryRef(dateIso);

    bool didWrite = false;

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        didWrite = false;
        return;
      }

      didWrite = true;

      tx.set(mortRef, {
        'date': dateIso,
        'buildingId': widget.building.id,
        'lotId': lotId,
        'qty': qty,
        'cause': cause,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'mobile_app',
      });

      tx.set(
        entryRef,
        {
          'mortality': {
            'qty': qty,
            'cause': cause,
            'note': note,
            'lotId': lotId,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      tx.set(lockRef, {
        'kind': 'MORTALITY',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    if (!didWrite) return "Mortalité déjà enregistrée";

    _mortalityQtyCtrl.text = "0";
    _mortalityCauseCtrl.clear();
    _mortalityNoteCtrl.clear();

    return "Mortalité OK (-$qty)";
  }

  // =========================
  // UI Helpers
  // =========================
  Widget _gradeRow(String label, String grade) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _alveolesCtrls[grade],
                keyboardType: TextInputType.number,
                inputFormatters: _digitsOnly,
                decoration: const InputDecoration(
                  labelText: 'Alvéoles',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _isolatedCtrls[grade],
                keyboardType: TextInputType.number,
                inputFormatters: _isolatedFormatters,
                decoration: const InputDecoration(
                  labelText: 'Œufs isolés (0..29)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final msg = _message;
    final defaultFeedId = _defaultFeedItemIdFromBuilding();

    final feedQuery = _db
        .collection('farms')
        .doc(_farmId)
        .collection('items')
        .where('type', isEqualTo: 'FEED')
        .where('active', isEqualTo: true);

    final vetQuery = _db
        .collection('farms')
        .doc(_farmId)
        .collection('items')
        .where('type', isEqualTo: 'VET')
        .where('active', isEqualTo: true);

    return Scaffold(
      appBar: AppBar(title: Text("Saisie – ${widget.building.name}")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Date : ${_dateIso(_selectedDate)}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loading ? null : _pickDate,
                  icon: const Icon(Icons.date_range),
                  label: const Text("Choisir"),
                ),
              ],
            ),

            const Divider(height: 32),

            Text("Ponte journalière", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _gradeRow("Petit calibre", 'SMALL'),
            _gradeRow("Moyen calibre", 'MEDIUM'),
            _gradeRow("Gros calibre", 'LARGE'),
            _gradeRow("Très gros calibre", 'XL'),

            const Divider(height: 32),

            Text("Casses (constatées à la collecte)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _brokenAlveolesCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: _digitsOnly,
                    decoration: const InputDecoration(
                      labelText: 'Alvéoles cassées',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _brokenIsolatedCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: _isolatedFormatters,
                    decoration: const InputDecoration(
                      labelText: 'Œufs isolés (0..29)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _brokenNoteCtrl,
              decoration: const InputDecoration(
                labelText: "Note casses (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),

            const Divider(height: 32),

            Text("Aliments", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: feedQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text("Erreur aliments: ${snap.error}", style: const TextStyle(color: Colors.red));
                }
                if (!snap.hasData) return const LinearProgressIndicator();
                final docs = snap.data!.docs;

                if (_selectedFeedItemId == null && defaultFeedId != null) {
                  final exists = docs.any((d) => d.id == defaultFeedId);
                  if (exists) _selectedFeedItemId = defaultFeedId;
                }

                return DropdownButtonFormField<String>(
                  value: _selectedFeedItemId,
                  decoration: const InputDecoration(
                    labelText: "Aliment",
                    border: OutlineInputBorder(),
                  ),
                  items: docs.map((d) {
                    final data = d.data();
                    final label = (data['name'] ?? d.id).toString();
                    return DropdownMenuItem<String>(value: d.id, child: Text(label));
                  }).toList(),
                  onChanged: _loading ? null : (v) => setState(() => _selectedFeedItemId = v),
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _feedBagsCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: _digitsOnly,
              decoration: const InputDecoration(
                labelText: 'Sacs consommés (50 kg)',
                border: OutlineInputBorder(),
              ),
            ),

            const Divider(height: 32),

            Text("Eau (litres)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    value: 'MANUAL',
                    groupValue: _waterMode,
                    title: const Text("Saisie manuelle"),
                    onChanged: _loading ? null : (v) => setState(() => _waterMode = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    value: 'ESTIMATE',
                    groupValue: _waterMode,
                    title: const Text("Estimation"),
                    onChanged: _loading
                        ? null
                        : (v) async {
                      setState(() => _waterMode = v!);
                      try {
                        final est = await _computeEstimatedWaterLiters();
                        if (mounted) {
                          setState(() {
                            _waterEstimatedLiters = est;
                            _waterLitersCtrl.text = est.toString();
                          });
                        }
                      } catch (_) {
                        if (mounted) {
                          setState(() {
                            _waterEstimatedLiters = 0;
                            _waterLitersCtrl.text = "0";
                          });
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _waterLitersCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: _digitsOnly,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: _waterMode == 'MANUAL'
                    ? "Litres consommés"
                    : "Litres estimés (modifiable si besoin)",
                border: const OutlineInputBorder(),
                helperText: _waterMode == 'ESTIMATE'
                    ? "Estimé = $_waterEstimatedLiters L (basé sur lot actif)"
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _waterNoteCtrl,
              decoration: const InputDecoration(
                labelText: "Note eau (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),

            const Divider(height: 32),

            Text("Produits vétérinaires (utilisation)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _noVetTreatment,
              onChanged: _loading
                  ? null
                  : (v) {
                setState(() {
                  _noVetTreatment = v ?? false;
                  if (_noVetTreatment) {
                    _selectedVetItemId = null;
                    _vetQtyCtrl.text = "0";
                    _vetNoteCtrl.clear();
                    _vetStockOnHand = null;
                    _vetUnitLabel = "unité";
                  }
                });
              },
              title: const Text("Aucun traitement / produit utilisé aujourd'hui"),
            ),

            if (!_noVetTreatment) ...[
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: vetQuery.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text("Erreur véto: ${snap.error}", style: const TextStyle(color: Colors.red));
                  }
                  if (!snap.hasData) return const LinearProgressIndicator();

                  final docs = snap.data!.docs;

                  return DropdownButtonFormField<String>(
                    value: _selectedVetItemId,
                    decoration: const InputDecoration(
                      labelText: "Produit vétérinaire",
                      border: OutlineInputBorder(),
                    ),
                    items: docs.map((d) {
                      final data = d.data();
                      final label = (data['name'] ?? d.id).toString();
                      return DropdownMenuItem<String>(value: d.id, child: Text(label));
                    }).toList(),
                    onChanged: _loading
                        ? null
                        : (v) async {
                      setState(() {
                        _selectedVetItemId = v;
                        _vetStockOnHand = null;
                        _vetUnitLabel = "unité";
                      });

                      if (v == null) return;
                      try {
                        final doc = await _db
                            .collection('farms')
                            .doc(_farmId)
                            .collection('items')
                            .doc(v)
                            .get();

                        final data = doc.data() ?? {};
                        setState(() {
                          _vetStockOnHand = _getInt(data['stockOnHand']);
                          final u = (data['unit'] ?? data['unitLabel'] ?? '').toString().trim();
                          if (u.isNotEmpty) _vetUnitLabel = u;
                        });
                      } catch (_) {}
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _vetQtyCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: _digitsOnly,
                decoration: InputDecoration(
                  labelText: "Quantité ($_vetUnitLabel)",
                  border: const OutlineInputBorder(),
                  helperText: _vetStockOnHand == null ? null : "Stock dispo: $_vetStockOnHand $_vetUnitLabel",
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _vetNoteCtrl,
                decoration: const InputDecoration(
                  labelText: "Note véto (optionnel)",
                  border: OutlineInputBorder(),
                ),
              ),
            ],

            const Divider(height: 32),

            Text("Mortalité", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _mortalityQtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: _digitsOnly,
              decoration: const InputDecoration(
                labelText: "Nombre de morts",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mortalityCauseCtrl,
              decoration: const InputDecoration(
                labelText: "Cause (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mortalityNoteCtrl,
              decoration: const InputDecoration(
                labelText: "Note mortalité (optionnel)",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),

            if (msg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  msg,
                  style: TextStyle(
                    color: msg.startsWith("Erreur") ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _saveAll,
                icon: _loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_loading ? "Enregistrement..." : "Enregistrer"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ Bloque la valeur dans une plage (ex: 0..29)
class _MinMaxIntFormatter extends TextInputFormatter {
  final int min;
  final int max;

  const _MinMaxIntFormatter({required this.min, required this.max});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final v = int.tryParse(text);
    if (v == null) return oldValue;

    int clamped = v;
    if (v < min) clamped = min;
    if (v > max) clamped = max;

    final s = clamped.toString();
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}
