import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/building.dart';
import '../services/active_lot_service.dart';

class DailyEntryScreen extends StatefulWidget {
  final Building building;

  const DailyEntryScreen({super.key, required this.building});

  @override
  State<DailyEntryScreen> createState() => _DailyEntryScreenState();
}

class _DailyEntryScreenState extends State<DailyEntryScreen> {
  static const String _farmId = 'farm_nkoteng';

  final FirebaseFirestore _db = FirebaseFirestore.instance;


  /// Récupère le lot actif du bâtiment (compat: lit `lotId` ou `activeLotId`)
  Future<String?> _getActiveLotIdCompat() async {
    final doc = await _db
        .collection('farms')
        .doc(_farmId)
        .collection('building_active_lots')
        .doc(widget.building.id)
        .get(const GetOptions(source: Source.serverAndCache));

    final data = doc.data();
    if (data == null) return null;
    if (data['active'] != true) return null;

    final lotId = (data['lotId'] ?? data['activeLotId'] ?? '').toString();
    return lotId.isEmpty ? null : lotId;
  }

  DateTime _date = DateTime.now();

  // Eggs by grade: SMALL/MEDIUM/LARGE/XL
  final _smallTraysCtrl = TextEditingController(text: '0');
  final _smallIsolatedCtrl = TextEditingController(text: '');
  final _mediumTraysCtrl = TextEditingController(text: '0');
  final _mediumIsolatedCtrl = TextEditingController(text: '');
  final _largeTraysCtrl = TextEditingController(text: '0');
  final _largeIsolatedCtrl = TextEditingController(text: '');
  final _xlTraysCtrl = TextEditingController(text: '0');
  final _xlIsolatedCtrl = TextEditingController(text: '');

  // broken eggs
  final _brokenTraysCtrl = TextEditingController(text: '0');
  final _brokenIsolatedCtrl = TextEditingController(text: '');

  // feed
  String? _selectedFeedItemId;
  final _feedBagsCtrl = TextEditingController(text: '0');

  // water
  String _waterMode = 'MANUAL'; // MANUAL | ESTIMATE
  final _waterLitersCtrl = TextEditingController(text: '0');
  final _waterNoteCtrl = TextEditingController();

  // vet (multi-produits)
  bool _noVetTreatment = true;
  final _vetNoteCtrl = TextEditingController();
  final List<_VetLine> _vetLines = [];
  List<_VetItem> _vetItems = const [];
  bool _loadingVetItems = false;

  // mortality
  final _mortalityQtyCtrl = TextEditingController(text: '0');
  final _mortalityCauseCtrl = TextEditingController();
  final _mortalityNoteCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _vetLines.add(_VetLine());
    _loadVetItems();
  }

  @override
  void dispose() {
    _smallTraysCtrl.dispose();
    _smallIsolatedCtrl.dispose();
    _mediumTraysCtrl.dispose();
    _mediumIsolatedCtrl.dispose();
    _largeTraysCtrl.dispose();
    _largeIsolatedCtrl.dispose();
    _xlTraysCtrl.dispose();
    _xlIsolatedCtrl.dispose();

    _brokenTraysCtrl.dispose();
    _brokenIsolatedCtrl.dispose();

    _feedBagsCtrl.dispose();

    _waterLitersCtrl.dispose();
    _waterNoteCtrl.dispose();

    _vetNoteCtrl.dispose();
    for (final l in _vetLines) {
      l.dispose();
    }

    _mortalityQtyCtrl.dispose();
    _mortalityCauseCtrl.dispose();
    _mortalityNoteCtrl.dispose();

    super.dispose();
  }

  // =========================
  // Helpers
  // =========================
  String _dateIso(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  int _parseInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int _traysToEggs(int trays) => trays * 30;

  int _isolatedEggs(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return 0;
    return int.tryParse(t) ?? 0;
  }

  int _asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;

  void _validateIsolated1to29OrEmpty(TextEditingController c, String label) {
    final t = c.text.trim();
    if (t.isEmpty) return;
    final v = int.tryParse(t);
    if (v == null || v < 1 || v > 29) {
      throw Exception("$label : les oeufs isolés doivent être entre 1 et 29 (ou vide).");
    }
  }

  DocumentReference<Map<String, dynamic>> _farmRef() => _db.collection('farms').doc(_farmId);

  DocumentReference<Map<String, dynamic>> _dailyEntryRef(String dateIso) {
    return _farmRef().collection('daily_entries').doc('${widget.building.id}_$dateIso');
  }

  void _snack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green : Colors.red),
    );
  }

  // =========================
  // Vet items list
  // =========================
  Future<void> _loadVetItems() async {
    setState(() => _loadingVetItems = true);
    try {
      final snap = await _farmRef()
          .collection('items')
          .get(const GetOptions(source: Source.serverAndCache));

      final items = <_VetItem>[];
      for (final d in snap.docs) {
        final data = d.data();
        final name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final type = (data['type'] ?? '').toString().toUpperCase();
        final category = (data['category'] ?? '').toString().toUpperCase();
        final kind = (data['kind'] ?? '').toString().toUpperCase();
        final isVet = data['isVet'] == true;

        items.add(_VetItem(
          id: d.id,
          name: name,
          unitLabel: (data['unitLabel'] ?? '').toString().trim().isEmpty
              ? 'unité'
              : (data['unitLabel'] ?? '').toString().trim(),
          isVet: isVet ||
              type == 'VET' ||
              category == 'VET' ||
              kind == 'VET' ||
              category.contains('VET') ||
              type.contains('VET'),
        ));
      }

      final vetOnly = items.where((e) => e.isVet).toList();
      setState(() {
        _vetItems = vetOnly.isNotEmpty ? vetOnly : items;
      });
    } catch (_) {
      setState(() => _vetItems = const []);
    } finally {
      if (mounted) setState(() => _loadingVetItems = false);
    }
  }

  // ✅ FIX: support two schemas for stocks_items:
  // 1) docId == itemId
  // 2) docId auto, with field { itemId: ... }
  Future<void> _loadVetStockForLine(_VetLine line, String itemId) async {
    try {
      final col = _farmRef().collection('stocks_items');

      // Try direct doc(itemId)
      final direct = await col.doc(itemId).get(const GetOptions(source: Source.serverAndCache));
      Map<String, dynamic>? data;
      if (direct.exists) {
        data = direct.data();
      } else {
        // Fallback: query by itemId field
        final q = await col
            .where('itemId', isEqualTo: itemId)
            .limit(1)
            .get(const GetOptions(source: Source.serverAndCache));
        if (q.docs.isNotEmpty) data = q.docs.first.data();
      }

      final qtyOnHand = (data?['qtyOnHand'] is num) ? (data!['qtyOnHand'] as num).toInt() : 0;
      final unit = (data?['unitLabel'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        line.stockOnHand = qtyOnHand;
        if (unit.isNotEmpty) line.unitLabel = unit;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        line.stockOnHand = null;
      });
    }
  }

  // =========================
  // Water estimate
  // =========================
  Future<int> _estimateWaterLiters() async {
    const litersPerHen = 0.25;

    // ✅ Estimation basée sur le stock sujets (plus fiable que la capacité)
    final farmRef = _db.collection('farms').doc(_farmId);
    final stockRef =
    farmRef.collection('stocks_subjects').doc('BUILDING_${widget.building.id}');

    try {
      final snap = await stockRef.get(const GetOptions(source: Source.serverAndCache));
      final data = snap.data();
      final onHand = _asInt(data?['totalOnHand']);
      final base = onHand > 0 ? onHand : widget.building.capacity;
      if (base > 0) return (base * litersPerHen).round();
    } catch (_) {
      // fallback below
    }

    final cap = widget.building.capacity;
    if (cap > 0) return (cap * litersPerHen).round();
    return 0;
  }

  Future<void> _applyWaterEstimateIfNeeded() async {
    if (_waterMode != 'ESTIMATE') return;
    final liters = await _estimateWaterLiters();
    if (!mounted) return;
    setState(() {
      _waterLitersCtrl.text = liters.toString();
      if (_waterNoteCtrl.text.trim().isEmpty && liters > 0) {
        _waterNoteCtrl.text = "Estimation automatique";
      }
    });
  }

  // =========================
  // Save all
  // =========================
  Future<void> _saveAll() async {
    if (_saving) return;

    final dateIso = _dateIso(_date);

    _validateIsolated1to29OrEmpty(_smallIsolatedCtrl, "SMALL");
    _validateIsolated1to29OrEmpty(_mediumIsolatedCtrl, "MEDIUM");
    _validateIsolated1to29OrEmpty(_largeIsolatedCtrl, "LARGE");
    _validateIsolated1to29OrEmpty(_xlIsolatedCtrl, "XL");
    _validateIsolated1to29OrEmpty(_brokenIsolatedCtrl, "Casses");

    setState(() => _saving = true);

    try {
      final eggsRes = await _saveEggsAndBrokenDelta(dateIso);
      final feedRes = await _saveFeedDelta(dateIso);
      final waterRes = await _saveWaterIfAny(dateIso);
      final vetRes = await _saveVetDelta(dateIso);
      final mortRes = await _saveMortalitySafe(dateIso);

      final parts = <String>[
        if (eggsRes != null) eggsRes,
        if (feedRes != null) feedRes,
        if (waterRes != null) waterRes,
        if (vetRes != null) vetRes,
        if (mortRes != null) mortRes,
      ];

      _snack(parts.isEmpty ? "Rien à enregistrer" : parts.join(" | "), ok: true);
    } catch (e) {
      _snack(e.toString(), ok: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // =========================
  // EGGS + BROKEN (delta + dot fields + totals)
  // =========================
  Future<String?> _saveEggsAndBrokenDelta(String dateIso) async {
    final newSmall =
        _traysToEggs(_parseInt(_smallTraysCtrl)) + _isolatedEggs(_smallIsolatedCtrl);
    final newMedium =
        _traysToEggs(_parseInt(_mediumTraysCtrl)) + _isolatedEggs(_mediumIsolatedCtrl);
    final newLarge =
        _traysToEggs(_parseInt(_largeTraysCtrl)) + _isolatedEggs(_largeIsolatedCtrl);
    final newXl = _traysToEggs(_parseInt(_xlTraysCtrl)) + _isolatedEggs(_xlIsolatedCtrl);

    final newBroken =
        _traysToEggs(_parseInt(_brokenTraysCtrl)) + _isolatedEggs(_brokenIsolatedCtrl);

    final newGoodTotal = newSmall + newMedium + newLarge + newXl;

    if (newGoodTotal < 0 || newBroken < 0) {
      throw Exception("Oeufs : valeurs négatives interdites.");
    }
    if (newGoodTotal == 0 && newBroken == 0) return null;

    final farmRef = _farmRef();
    final entryRef = _dailyEntryRef(dateIso);

    final buildingStockRef =
    farmRef.collection('stocks_eggs').doc('BUILDING_${widget.building.id}');
    final farmGlobalRef = farmRef.collection('stocks_eggs').doc('FARM_GLOBAL');

    int oldGoodTotal = 0, oldBroken = 0;
    int deltaGoodTotal = 0, deltaBroken = 0;
    int deltaSmall = 0, deltaMedium = 0, deltaLarge = 0, deltaXl = 0;

    await _db.runTransaction((tx) async {
      final entrySnap = await tx.get(entryRef);
      final entry = entrySnap.data() ?? <String, dynamic>{};
      final eggs = (entry['eggs'] is Map) ? (entry['eggs'] as Map) : <String, dynamic>{};
      final oldGoodByGrade =
      (eggs['goodByGrade'] is Map) ? (eggs['goodByGrade'] as Map) : <String, dynamic>{};

      final oldSmall = _asInt(oldGoodByGrade['SMALL']);
      final oldMedium = _asInt(oldGoodByGrade['MEDIUM']);
      final oldLarge = _asInt(oldGoodByGrade['LARGE']);
      final oldXl = _asInt(oldGoodByGrade['XL']);
      oldBroken = _asInt(eggs['brokenTotalEggs']);
      oldGoodTotal = oldSmall + oldMedium + oldLarge + oldXl;

      deltaSmall = newSmall - oldSmall;
      deltaMedium = newMedium - oldMedium;
      deltaLarge = newLarge - oldLarge;
      deltaXl = newXl - oldXl;
      deltaBroken = newBroken - oldBroken;
      deltaGoodTotal = newGoodTotal - oldGoodTotal;

      if (deltaSmall == 0 && deltaMedium == 0 && deltaLarge == 0 && deltaXl == 0 && deltaBroken == 0) {
        return;
      }

      // BUILDING (create if missing) + update with dot-paths
      tx.set(
        buildingStockRef,
        {
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'daily_entry',
          'buildingId': widget.building.id,
        },
        SetOptions(merge: true),
      );

      tx.update(buildingStockRef, <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'goodTotalEggs': FieldValue.increment(deltaGoodTotal),
        'brokenTotalEggs': FieldValue.increment(deltaBroken),
        'eggsByGrade.SMALL': FieldValue.increment(deltaSmall),
        'eggsByGrade.MEDIUM': FieldValue.increment(deltaMedium),
        'eggsByGrade.LARGE': FieldValue.increment(deltaLarge),
        'eggsByGrade.XL': FieldValue.increment(deltaXl),
      });

      // FARM_GLOBAL (create if missing) + update with dot-paths
      tx.set(
        farmGlobalRef,
        {
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'daily_entry',
        },
        SetOptions(merge: true),
      );

      tx.update(farmGlobalRef, <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'goodTotalEggs': FieldValue.increment(deltaGoodTotal),
        'brokenTotalEggs': FieldValue.increment(deltaBroken),
        'eggsByGrade.SMALL': FieldValue.increment(deltaSmall),
        'eggsByGrade.MEDIUM': FieldValue.increment(deltaMedium),
        'eggsByGrade.LARGE': FieldValue.increment(deltaLarge),
        'eggsByGrade.XL': FieldValue.increment(deltaXl),
      });

      // daily entry
      tx.set(
        entryRef,
        {
          'date': dateIso,
          'buildingId': widget.building.id,
          'eggs': {
            'goodByGrade': {
              'SMALL': newSmall,
              'MEDIUM': newMedium,
              'LARGE': newLarge,
              'XL': newXl,
            },
            'brokenTotalEggs': newBroken,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );
    });

    _smallTraysCtrl.text = "0";
    _smallIsolatedCtrl.clear();
    _mediumTraysCtrl.text = "0";
    _mediumIsolatedCtrl.clear();
    _largeTraysCtrl.text = "0";
    _largeIsolatedCtrl.clear();
    _xlTraysCtrl.text = "0";
    _xlIsolatedCtrl.clear();
    _brokenTraysCtrl.text = "0";
    _brokenIsolatedCtrl.clear();

    if (oldGoodTotal == 0 && oldBroken == 0) {
      return "Oeufs OK (+$newGoodTotal / cassés +$newBroken)";
    }
    return "Oeufs OK (maj Δ bon=$deltaGoodTotal / Δ cassés=$deltaBroken)";
  }

  // =========================
  // FEED (delta)
  // - If user modifies same day, adjust stock with delta
  // - If user changes item, return old qty to old item and take new qty from new item
  // =========================
  Future<String?> _saveFeedDelta(String dateIso) async {
    final newItemId = _selectedFeedItemId;
    final newBags = _parseInt(_feedBagsCtrl);

    if (newItemId == null || newItemId.isEmpty) return null;
    if (newBags < 0) throw Exception("Aliments : quantité négative interdite.");
    if (newBags == 0) return null;

    final farmRef = _farmRef();
    final entryRef = _dailyEntryRef(dateIso);

    final newStockRef = farmRef.collection('stocks_items').doc(newItemId);

    // deterministic movement doc (overwrite = net for the day)
    String movementDocId(String itemId) => 'FEED_${widget.building.id}_$dateIso\_$itemId';

    int oldBags = 0;
    String? oldItemId;

    await _db.runTransaction((tx) async {
      final entrySnap = await tx.get(entryRef);
      final entry = entrySnap.data() ?? <String, dynamic>{};
      final feed = (entry['feed'] is Map) ? (entry['feed'] as Map) : <String, dynamic>{};

      oldItemId = (feed['feedItemId'] ?? '').toString().trim();
      oldBags = _asInt(feed['bags50']);

      // If feed was previously saved with an item
      final hasOld = oldItemId != null && oldItemId!.isNotEmpty && oldBags > 0;

      if (hasOld && oldItemId == newItemId && oldBags == newBags) {
        // no change
        return;
      }

      // 1) If changing item OR decreasing/increasing -> compute stock adjustments
      // Return old bags to old item if needed
      if (hasOld) {
        final oldStockRef = farmRef.collection('stocks_items').doc(oldItemId!);
        final oldStockSnap = await tx.get(oldStockRef);
        final oldStock = oldStockSnap.data() as Map<String, dynamic>?;

        final oldQtyOnHand =
        (oldStock?['qtyOnHand'] is num) ? (oldStock!['qtyOnHand'] as num).toInt() : 0;

        // add back oldBags to old item stock
        tx.set(
          oldStockRef,
          {
            'qtyOnHand': oldQtyOnHand + oldBags,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // update movement doc for old item to 0 (net for the day = removed)
        final oldMovRef = farmRef.collection('items_movements').doc(movementDocId(oldItemId!));
        tx.set(
          oldMovRef,
          {
            'date': dateIso,
            'type': 'OUT',
            'itemId': oldItemId,
            'qty': 0, // net = 0 after modification
            'unitLabel': 'sac',
            'from': {'kind': 'FARM'},
            'to': {'kind': 'BUILDING', 'id': widget.building.id},
            'reason': 'FEED_CONSUMPTION',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'source': 'mobile_app',
          },
          SetOptions(merge: true),
        );
      }

      // 2) Take newBags from new item
      final newStockSnap = await tx.get(newStockRef);
      final newStock = newStockSnap.data() as Map<String, dynamic>?;
      final newQtyOnHand =
      (newStock?['qtyOnHand'] is num) ? (newStock!['qtyOnHand'] as num).toInt() : 0;

      if (newQtyOnHand < newBags) {
        throw Exception("Stock aliments insuffisant : $newQtyOnHand sacs dispo.");
      }

      tx.set(
        newStockRef,
        {
          'qtyOnHand': newQtyOnHand - newBags,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // deterministic movement for new item: qty = newBags (net for the day)
      final newMovRef = farmRef.collection('items_movements').doc(movementDocId(newItemId));
      tx.set(
        newMovRef,
        {
          'date': dateIso,
          'type': 'OUT',
          'itemId': newItemId,
          'qty': newBags,
          'unitLabel': 'sac',
          'from': {'kind': 'FARM'},
          'to': {'kind': 'BUILDING', 'id': widget.building.id},
          'reason': 'FEED_CONSUMPTION',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      // Save to daily entry
      tx.set(
        entryRef,
        {
          'feed': {
            'none': false,
            'feedItemId': newItemId,
            'bags50': newBags,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );
    });

    _feedBagsCtrl.text = "0";
    if (oldItemId == null || oldItemId!.isEmpty) return "Aliments OK (-$newBags sacs)";
    return "Aliments OK (maj possible)";
  }

  // =========================
  // WATER (idempotent as before)
  // =========================
  Future<String?> _saveWaterIfAny(String dateIso) async {
    final liters = _parseInt(_waterLitersCtrl);
    if (liters < 0) throw Exception("Eau : quantité négative interdite.");
    if (liters == 0 && _waterNoteCtrl.text.trim().isEmpty) return null;

    final farmRef = _farmRef();
    final entryRef = _dailyEntryRef(dateIso);

    // Keep idempotency for water (optional)
    final uniqueKey = ['WATER', _farmId, dateIso, widget.building.id, liters.toString(), _waterMode].join('|');
    final lockRef = farmRef.collection('idempotency').doc(uniqueKey);

    bool didWrite = false;

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        didWrite = false;
        return;
      }
      didWrite = true;

      tx.set(
        entryRef,
        {
          'water': {
            'mode': _waterMode,
            'liters': liters,
            'note': _waterNoteCtrl.text.trim().isEmpty ? null : _waterNoteCtrl.text.trim(),
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      tx.set(lockRef, {'kind': 'DAILY_WATER', 'createdAt': FieldValue.serverTimestamp()});
    });

    if (!didWrite) return "Eau déjà enregistrée";

    _waterNoteCtrl.clear();
    _waterLitersCtrl.text = "0";
    return "Eau OK ($liters L)";
  }

  // =========================
  // VET (delta, multi items)
  // - aggregates by itemId
  // - adjusts stocks_items with delta
  // - deterministic movements per item per day
  // - if "aucun traitement" => restore previous usage if any
  // =========================
  Future<String?> _saveVetDelta(String dateIso) async {
    final farmRef = _farmRef();
    final entryRef = _dailyEntryRef(dateIso);

    // Build new usage map
    final Map<String, int> newUsed = {};
    if (!_noVetTreatment) {
      for (final line in _vetLines) {
        final qty = _parseInt(line.qtyCtrl);
        if (qty < 0) throw Exception("Vétérinaire : quantité négative interdite.");
        if (qty == 0) continue;

        final itemId = line.itemId;
        if (itemId == null || itemId.isEmpty) {
          throw Exception("Vétérinaire : veuillez sélectionner un produit.");
        }
        newUsed[itemId] = (newUsed[itemId] ?? 0) + qty;
      }
    }

    final note = _noVetTreatment
        ? null
        : (_vetNoteCtrl.text.trim().isEmpty ? null : _vetNoteCtrl.text.trim());

    // If none and nothing to restore, just write 'none' and exit
    await _db.runTransaction((tx) async {
      final entrySnap = await tx.get(entryRef);
      final entry = entrySnap.data() ?? <String, dynamic>{};
      final vet = (entry['vet'] is Map) ? (entry['vet'] as Map) : <String, dynamic>{};
      final oldItems = (vet['items'] is List) ? (vet['items'] as List) : const <dynamic>[];

      // Build old usage map
      final Map<String, int> oldUsed = {};
      for (final it in oldItems) {
        if (it is Map) {
          final id = (it['itemId'] ?? '').toString();
          final q = _asInt(it['qtyUsed']);
          if (id.isNotEmpty && q > 0) oldUsed[id] = (oldUsed[id] ?? 0) + q;
        }
      }

      // union keys
      final keys = <String>{...oldUsed.keys, ...newUsed.keys};

      // if no change
      bool anyDelta = false;
      final Map<String, int> deltaByItem = {};
      for (final k in keys) {
        final d = (newUsed[k] ?? 0) - (oldUsed[k] ?? 0);
        if (d != 0) anyDelta = true;
        deltaByItem[k] = d;
      }

      if (!anyDelta && ((_noVetTreatment && (oldUsed.isEmpty)) || (!_noVetTreatment && oldUsed.isNotEmpty))) {
        // Still ensure we update entry's note/none flag if needed
        tx.set(
          entryRef,
          {
            'vet': {
              'none': _noVetTreatment,
              'items': _noVetTreatment
                  ? <dynamic>[]
                  : newUsed.entries
                  .map((e) => {'itemId': e.key, 'qtyUsed': e.value, 'unitLabel': 'unité'})
                  .toList(),
              'note': note,
              'savedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
            'source': 'mobile_app',
          },
          SetOptions(merge: true),
        );
        return;
      }

      // For each item, adjust stock by delta (delta>0 => consume more => subtract delta)
      // Ensure not negative.
      for (final entryItem in deltaByItem.entries) {
        final itemId = entryItem.key;
        final delta = entryItem.value;
        if (delta == 0) continue;

        final stockRef = farmRef.collection('stocks_items').doc(itemId);
        final stockSnap = await tx.get(stockRef);
        final stock = stockSnap.data() as Map<String, dynamic>?;
        final currentQty =
        (stock?['qtyOnHand'] is num) ? (stock!['qtyOnHand'] as num).toInt() : 0;

        // stock change = -delta (because usage reduces stock)
        final newQty = currentQty - delta;
        if (newQty < 0) {
          throw Exception("Stock véto insuffisant pour '$itemId' : $currentQty dispo, besoin +$delta.");
        }

        tx.set(
          stockRef,
          {'qtyOnHand': newQty, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );

        // deterministic movement: net qtyUsed for day (newUsed)
        final movRef = farmRef
            .collection('items_movements')
            .doc('VET_${widget.building.id}_$dateIso\_$itemId');

        tx.set(
          movRef,
          {
            'date': dateIso,
            'type': 'OUT',
            'itemId': itemId,
            'qty': newUsed[itemId] ?? 0,
            'unitLabel': 'unité',
            'from': {'kind': 'FARM'},
            'to': {'kind': 'BUILDING', 'id': widget.building.id},
            'reason': 'VET_TREATMENT',
            'note': note,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'source': 'mobile_app',
          },
          SetOptions(merge: true),
        );
      }

      // Save to daily entry (source of truth)
      tx.set(
        entryRef,
        {
          'vet': {
            'none': _noVetTreatment,
            'items': _noVetTreatment
                ? <dynamic>[]
                : newUsed.entries
                .map((e) => {'itemId': e.key, 'qtyUsed': e.value, 'unitLabel': 'unité'})
                .toList(),
            'note': note,
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );
    });

    // Reset quantities (keep selection)
    for (final l in _vetLines) {
      l.qtyCtrl.text = "0";
    }
    _vetNoteCtrl.clear();

    if (_noVetTreatment) return "Véto: aucun (maj)";
    final total = newUsed.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return null;
    return "Véto OK (maj, total $total)";
  }

  // =========================
  // Mortality (safe)
  // - if qty>0 => require active lotId and lot document exists
  // - otherwise show a clear error instead of "lot introuvable"
  // =========================
  Future<String?> _saveMortalitySafe(String dateIso) async {
    final qty = _parseInt(_mortalityQtyCtrl);
    if (qty < 0) throw Exception("Mortalité : quantité négative interdite.");

    final hasAnyField =
        qty != 0 || _mortalityCauseCtrl.text.trim().isNotEmpty || _mortalityNoteCtrl.text.trim().isNotEmpty;
    if (!hasAnyField) return null;

    // ✅ require lot if qty>0 (and even for a mortality report, it's safer)
    final lotId = await _getActiveLotIdCompat();
    if (lotId == null || lotId.trim().isEmpty) {
      throw Exception("Mortalité : aucun lot actif pour ce bâtiment. Active d’abord un lot avant de saisir une mortalité.");
    }

    // check lot existence
    final lotSnap = await _farmRef()
        .collection('lots')
        .doc(lotId)
        .get(const GetOptions(source: Source.serverAndCache));
    if (!lotSnap.exists) {
      throw Exception("Mortalité : lot actif introuvable (lotId=$lotId). Vérifie la création/activation du lot.");
    }

    final farmRef = _farmRef();
    final entryRef = _dailyEntryRef(dateIso);

    // deterministic mortality doc for the day/building
    final mortalityRef = farmRef.collection('daily_mortality').doc('${widget.building.id}_$dateIso');

    await _db.runTransaction((tx) async {
      tx.set(
        entryRef,
        {
          'mortality': {
            'qty': qty,
            'lotId': lotId,
            'cause': _mortalityCauseCtrl.text.trim().isEmpty ? null : _mortalityCauseCtrl.text.trim(),
            'note': _mortalityNoteCtrl.text.trim().isEmpty ? null : _mortalityNoteCtrl.text.trim(),
            'savedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );

      tx.set(
        mortalityRef,
        {
          'date': dateIso,
          'buildingId': widget.building.id,
          'lotId': lotId,
          'qty': qty,
          'cause': _mortalityCauseCtrl.text.trim().isEmpty ? null : _mortalityCauseCtrl.text.trim(),
          'note': _mortalityNoteCtrl.text.trim().isEmpty ? null : _mortalityNoteCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'mobile_app',
        },
        SetOptions(merge: true),
      );
    });

    _mortalityQtyCtrl.text = "0";
    _mortalityCauseCtrl.clear();
    _mortalityNoteCtrl.clear();

    return "Mortalité OK ($qty, lot=$lotId)";
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final dateIso = _dateIso(_date);

    return Scaffold(
      appBar: AppBar(
        title: Text('Rapport journalier - ${widget.building.name}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text("Date: $dateIso"),
              subtitle: const Text("Choisir la date du rapport"),
              onTap: _saving
                  ? null
                  : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020, 1, 1),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
          ),
          const SizedBox(height: 12),

          _sectionTitle("Ponte (bons oeufs)"),
          _gradeRow("SMALL", _smallTraysCtrl, _smallIsolatedCtrl),
          _gradeRow("MEDIUM", _mediumTraysCtrl, _mediumIsolatedCtrl),
          _gradeRow("LARGE", _largeTraysCtrl, _largeIsolatedCtrl),
          _gradeRow("XL", _xlTraysCtrl, _xlIsolatedCtrl),

          const SizedBox(height: 12),
          _sectionTitle("Casses"),
          _brokenRow(),

          const SizedBox(height: 18),

          _sectionTitle("Eau"),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'MANUAL',
                    groupValue: _waterMode,
                    title: const Text("Saisie manuelle"),
                    onChanged: _saving ? null : (v) => setState(() => _waterMode = v!),
                  ),
                  RadioListTile<String>(
                    value: 'ESTIMATE',
                    groupValue: _waterMode,
                    title: const Text("Estimation automatique"),
                    onChanged: _saving
                        ? null
                        : (v) async {
                      setState(() => _waterMode = v!);
                      await _applyWaterEstimateIfNeeded();
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _waterLitersCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _waterMode == 'MANUAL' ? "Litres consommés" : "Litres estimés (modifiable)",
                      helperText: _waterMode == 'ESTIMATE'
                          ? "Basé sur lot actif/capacité bâtiment (0.25L/poule/jour)"
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _waterNoteCtrl,
                    decoration: const InputDecoration(labelText: "Note (optionnel)"),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          _sectionTitle("Produits vétérinaires"),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _noVetTreatment,
                    onChanged: _saving ? null : (v) => setState(() => _noVetTreatment = v),
                    title: const Text("Aucun traitement"),
                    subtitle: const Text("Activez si aucun produit vétérinaire n’a été utilisé ce jour."),
                  ),
                  if (!_noVetTreatment) ...[
                    if (_loadingVetItems)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (_vetItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          "Aucun produit disponible (farms/farm_nkoteng/items).",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 6),
                    for (int i = 0; i < _vetLines.length; i++) _vetLineRow(i),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving ? null : () => setState(() => _vetLines.add(_VetLine())),
                        icon: const Icon(Icons.add),
                        label: const Text("Ajouter produit"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _vetNoteCtrl,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: "Note (optionnel)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          _sectionTitle("Mortalité"),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _mortalityQtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Nombre de morts"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _mortalityCauseCtrl,
                    decoration: const InputDecoration(labelText: "Cause (optionnel)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _mortalityNoteCtrl,
                    decoration: const InputDecoration(labelText: "Note (optionnel)"),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveAll,
              icon: _saving
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.save),
              label: Text(_saving ? "Enregistrement..." : "Enregistrer"),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _vetLineRow(int index) {
    final line = _vetLines[index];
    final currentItem = _vetItems.where((e) => e.id == line.itemId).toList();
    final selected = currentItem.isNotEmpty ? currentItem.first : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: line.itemId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Produit",
                    border: OutlineInputBorder(),
                  ),
                  items: _vetItems
                      .map((it) => DropdownMenuItem<String>(
                    value: it.id,
                    child: Text(it.name),
                  ))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) {
                    setState(() {
                      line.itemId = v;
                      final it = _vetItems.where((e) => e.id == v).toList();
                      if (it.isNotEmpty) line.unitLabel = it.first.unitLabel;
                    });
                    if (v != null && v.isNotEmpty) {
                      _loadVetStockForLine(line, v);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: line.qtyCtrl,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Qté",
                    helperText: line.unitLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: "Supprimer",
                onPressed: _saving || _vetLines.length <= 1
                    ? null
                    : () {
                  setState(() {
                    final removed = _vetLines.removeAt(index);
                    removed.dispose();
                  });
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (line.stockOnHand != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "Stock dispo: ${line.stockOnHand} ${line.unitLabel}",
                style: TextStyle(color: Colors.grey.shade700),
              ),
            )
          else if (selected != null && line.itemId != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "Stock dispo: (non chargé)",
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _gradeRow(String label, TextEditingController trays, TextEditingController isolated) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(width: 72, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: trays,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Alvéoles",
                  helperText: "30 oeufs / alvéole",
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: isolated,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Isolés",
                  helperText: "si saisi: 1..29",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brokenRow() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const SizedBox(width: 72, child: Text("Casse", style: TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _brokenTraysCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Alvéoles"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _brokenIsolatedCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Isolés",
                  helperText: "si saisi: 1..29",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VetItem {
  final String id;
  final String name;
  final String unitLabel;
  final bool isVet;

  const _VetItem({
    required this.id,
    required this.name,
    required this.unitLabel,
    required this.isVet,
  });
}

class _VetLine {
  String? itemId;
  final TextEditingController qtyCtrl = TextEditingController(text: '0');
  int? stockOnHand;
  String unitLabel = 'unité';

  void dispose() => qtyCtrl.dispose();
}
