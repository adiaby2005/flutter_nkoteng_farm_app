import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/building.dart';
import 'daily_entry_detail_screen.dart';

class DailyEntriesHistoryScreen extends StatefulWidget {
  final Building building;
  final String farmId;

  const DailyEntriesHistoryScreen({
    super.key,
    required this.building,
    this.farmId = 'farm_nkoteng',
  });

  @override
  State<DailyEntriesHistoryScreen> createState() =>
      _DailyEntriesHistoryScreenState();
}

class _DailyEntriesHistoryScreenState extends State<DailyEntriesHistoryScreen> {
  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  bool _importing = false;
  String? _error;

  // Filtre de dates (optionnel)
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pagination
  static const int _pageSize = 20;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _rows = [];

  String _dateIso(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = _db
        .collection('farms')
        .doc(widget.farmId)
        .collection('daily_entries')
        .where('buildingId', isEqualTo: widget.building.id);

    // Filtre de période (date ISO en string)
    if (_fromDate != null) {
      q = q.where('date', isGreaterThanOrEqualTo: _dateIso(_fromDate!));
    }
    if (_toDate != null) {
      q = q.where('date', isLessThanOrEqualTo: _dateIso(_toDate!));
    }

    return q.orderBy('date', descending: true);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows.clear();
      _lastDoc = null;
      _hasMore = true;
    });

    try {
      await _loadMore();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore) return;

    Query<Map<String, dynamic>> q = _baseQuery().limit(_pageSize);
    if (_lastDoc != null) {
      q = q.startAfterDocument(_lastDoc!);
    }

    final snap = await q.get();
    if (snap.docs.isEmpty) {
      setState(() => _hasMore = false);
      return;
    }

    setState(() {
      _rows.addAll(snap.docs);
      _lastDoc = snap.docs.last;
      if (snap.docs.length < _pageSize) _hasMore = false;
    });
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() => _fromDate = _startOfDay(picked));
      await _refresh();
    }
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() => _toDate = _endOfDay(picked));
      await _refresh();
    }
  }

  Future<void> _clearFilters() async {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    await _refresh();
  }

  Map<String, dynamic> _getMap(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  int _getInt(Map<String, dynamic> m, String key, [int def = 0]) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return def;
  }

  String _summaryLine(Map<String, dynamic> data) {
    final prod = _getMap(data, 'production');
    final broken = _getMap(data, 'broken');
    final feed = _getMap(data, 'feed');
    final water = _getMap(data, 'water');
    final mort = _getMap(data, 'mortality');
    final vet = _getMap(data, 'vet');

    final totalEggs = _getInt(prod, 'totalEggs', 0);
    final totalBroken = _getInt(broken, 'totalBrokenEggs', 0);
    final feedBags = _getInt(feed, 'bags50', 0);
    final waterL = _getInt(water, 'liters', 0);
    final mortQty = _getInt(mort, 'qty', 0);

    final bool vetNone = (vet['none'] == true);

    final parts = <String>[];
    if (totalEggs > 0) parts.add("Ponte $totalEggs");
    if (totalBroken > 0) parts.add("Casses $totalBroken");
    if (feedBags > 0) parts.add("Alim $feedBags sacs");
    if (waterL > 0) parts.add("Eau $waterL L");
    if (mortQty > 0) parts.add("Mort $mortQty");
    if (vet.isNotEmpty) {
      parts.add(vetNone ? "Véto: aucun" : "Véto: oui");
    }

    return parts.isEmpty ? "Aucune donnée saisie" : parts.join(" • ");
  }

  /// Import "best-effort" des anciens jours: construit daily_entries à partir des collections existantes
  /// Limité aux derniers [maxDays] jours + docs existants dans daily_production.
  Future<void> _importHistory({int maxDays = 120, int limit = 200}) async {
    if (_importing) return;

    setState(() {
      _importing = true;
      _error = null;
    });

    final farmRef = _db.collection('farms').doc(widget.farmId);

    try {
      // 1) On part des dates présentes dans daily_production (souvent la base)
      final prodSnap = await farmRef
          .collection('daily_production')
          .where('buildingId', isEqualTo: widget.building.id)
          .orderBy('date', descending: true)
          .limit(limit)
          .get();

      if (prodSnap.docs.isEmpty) {
        throw Exception(
          "Aucune production trouvée pour ce bâtiment. Rien à importer.",
        );
      }

      // 2) Filtrage jours récents (maxDays)
      final cutoff = DateTime.now().subtract(Duration(days: maxDays));
      final cutoffIso = _dateIso(cutoff);

      final dates = <String>{};
      for (final d in prodSnap.docs) {
        final date = (d.data()['date'] ?? '').toString();
        if (date.isEmpty) continue;
        if (date.compareTo(cutoffIso) >= 0) {
          dates.add(date);
        }
      }

      if (dates.isEmpty) {
        throw Exception("Aucune date récente (<= $maxDays jours) à importer.");
      }

      // 3) Pour chaque date : on lit les sources et on set daily_entries/{buildingId_date}
      // On écrit en batch par paquets
      final sortedDates = dates.toList()..sort((a, b) => b.compareTo(a));

      WriteBatch batch = _db.batch();
      int ops = 0;

      for (final dateIso in sortedDates) {
        final dailyEntryId = "${widget.building.id}_$dateIso";
        final entryRef = farmRef.collection('daily_entries').doc(dailyEntryId);

        // Production (on prend 1 doc/jour)
        final prodDaySnap = await farmRef
            .collection('daily_production')
            .where('buildingId', isEqualTo: widget.building.id)
            .where('date', isEqualTo: dateIso)
            .limit(1)
            .get();

        Map<String, dynamic> production = {};
        if (prodDaySnap.docs.isNotEmpty) {
          final p = prodDaySnap.docs.first.data();
          production = {
            'lotId': p['lotId'],
            'eggsByGrade': p['eggsByGrade'],
            'totalEggs': p['totalEggs'] ?? 0,
            'savedAt': FieldValue.serverTimestamp(),
          };
        }

        // Casses (on somme si plusieurs)
        final brokenSnap = await farmRef
            .collection('broken_egg_inflows')
            .where('buildingId', isEqualTo: widget.building.id)
            .where('date', isEqualTo: dateIso)
            .get();

        int brokenTotal = 0;
        int brokenAlv = 0;
        int brokenIso = 0;
        for (final b in brokenSnap.docs) {
          final bd = b.data();
          brokenTotal += (bd['totalBrokenEggs'] ?? 0) as int;
          brokenAlv += (bd['brokenAlveoles'] ?? 0) as int;
          brokenIso += (bd['brokenIsolated'] ?? 0) as int;
        }
        final broken = (brokenTotal > 0 || brokenSnap.docs.isNotEmpty)
            ? {
          'totalBrokenEggs': brokenTotal,
          'brokenAlveoles': brokenAlv,
          'brokenIsolated': brokenIso,
          'savedAt': FieldValue.serverTimestamp(),
        }
            : {};

        // Aliments (si plusieurs, on somme bags50 + kgTotal, et on garde feedItemId du 1er)
        final feedSnap = await farmRef
            .collection('daily_feed_consumption')
            .where('buildingId', isEqualTo: widget.building.id)
            .where('date', isEqualTo: dateIso)
            .get();

        int bagsTotal = 0;
        int kgTotal = 0;
        String? feedItemId;
        for (final f in feedSnap.docs) {
          final fd = f.data();
          bagsTotal += (fd['bags50'] ?? 0) as int;
          kgTotal += (fd['kgTotal'] ?? 0) as int;
          feedItemId ??= (fd['feedItemId'] ?? '').toString();
        }
        final feed = (bagsTotal > 0 || feedSnap.docs.isNotEmpty)
            ? {
          'feedItemId': feedItemId,
          'bags50': bagsTotal,
          'kgTotal': kgTotal,
          'savedAt': FieldValue.serverTimestamp(),
        }
            : {};

        // Eau (on prend 1 doc/jour si existe, sinon ignore)
        final waterSnap = await farmRef
            .collection('daily_water_consumption')
            .where('buildingId', isEqualTo: widget.building.id)
            .where('date', isEqualTo: dateIso)
            .limit(1)
            .get();

        final water = waterSnap.docs.isNotEmpty
            ? {
          'mode': waterSnap.docs.first.data()['mode'],
          'liters': waterSnap.docs.first.data()['liters'] ?? 0,
          'note': waterSnap.docs.first.data()['note'],
          'savedAt': FieldValue.serverTimestamp(),
        }
            : {};

        // Véto (si plusieurs, on marque "oui" et on prend le 1er)
        final vetSnap = await farmRef
            .collection('vet_treatments')
            .where('buildingId', isEqualTo: widget.building.id)
            .where('date', isEqualTo: dateIso)
            .orderBy('createdAt', descending: false)
            .limit(1)
            .get();

        final vet = vetSnap.docs.isNotEmpty
            ? {
          'none': false,
          'itemId': vetSnap.docs.first.data()['itemId'],
          'qtyUsed': vetSnap.docs.first.data()['qtyUsed'] ?? 0,
          'unitLabel': vetSnap.docs.first.data()['unitLabel'],
          'lotId': vetSnap.docs.first.data()['lotId'],
          'note': vetSnap.docs.first.data()['note'],
          'savedAt': FieldValue.serverTimestamp(),
        }
            : {};

        // Mortalité (si plusieurs, on somme qty, et on garde cause/note du 1er)
        final mortSnap = await farmRef
            .collection('daily_mortality')
            .where('buildingId', isEqualTo: widget.building.id)
            .where('date', isEqualTo: dateIso)
            .get();

        int mortTotal = 0;
        String? mortCause;
        String? mortNote;
        String? mortLotId;
        for (final m in mortSnap.docs) {
          final md = m.data();
          mortTotal += (md['qty'] ?? 0) as int;
          mortCause ??= (md['cause'] ?? '').toString();
          mortNote ??= (md['note'] ?? '').toString();
          mortLotId ??= (md['lotId'] ?? '').toString();
        }
        final mortality = (mortTotal > 0 || mortSnap.docs.isNotEmpty)
            ? {
          'qty': mortTotal,
          'cause': (mortCause != null && mortCause!.trim().isEmpty) ? null : mortCause,
          'note': (mortNote != null && mortNote!.trim().isEmpty) ? null : mortNote,
          'lotId': (mortLotId != null && mortLotId!.trim().isEmpty) ? null : mortLotId,
          'savedAt': FieldValue.serverTimestamp(),
        }
            : {};

        final payload = <String, dynamic>{
          'date': dateIso,
          'buildingId': widget.building.id,
          'buildingName': widget.building.name,
          'production': production.isEmpty ? FieldValue.delete() : production,
          'broken': broken.isEmpty ? FieldValue.delete() : broken,
          'feed': feed.isEmpty ? FieldValue.delete() : feed,
          'water': water.isEmpty ? FieldValue.delete() : water,
          'vet': vet.isEmpty ? FieldValue.delete() : vet,
          'mortality': mortality.isEmpty ? FieldValue.delete() : mortality,
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'import_history',
        };

        batch.set(entryRef, payload, SetOptions(merge: true));
        ops++;

        // commit par paquets (500 max par batch)
        if (ops >= 400) {
          await batch.commit();
          batch = _db.batch();
          ops = 0;
        }
      }

      if (ops > 0) {
        await batch.commit();
      }

      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Import terminé : historique agrégé.")),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = "Historique – ${widget.building.name}";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: "Rafraîchir",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : () => _importHistory(maxDays: 180, limit: 300),
        icon: _importing
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Icon(Icons.download),
        label: Text(_importing ? "Import..." : "Importer l'historique"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickFromDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    _fromDate == null ? "Du" : "Du ${_dateIso(_fromDate!)}",
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickToDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    _toDate == null ? "Au" : "Au ${_dateIso(_toDate!)}",
                  ),
                ),
                TextButton(
                  onPressed: (_loading || (_fromDate == null && _toDate == null))
                      ? null
                      : _clearFilters,
                  child: const Text("Effacer filtre"),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _error != null
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Erreur: $_error",
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
                : ListView.separated(
              itemCount: _rows.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == _rows.length) {
                  if (_loading && _rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!_hasMore) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          _rows.isEmpty
                              ? "Aucun jour agrégé pour l’instant.\nUtilise “Importer l'historique” ou fais des saisies avec “Enregistrer tout”."
                              : "Fin de liste",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () async {
                          setState(() => _loading = true);
                          try {
                            await _loadMore();
                          } catch (e) {
                            setState(() => _error = e.toString());
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        },
                        icon: const Icon(Icons.expand_more),
                        label: const Text("Charger plus"),
                      ),
                    ),
                  );
                }

                final doc = _rows[index];
                final data = doc.data();
                final date = (data['date'] ?? '').toString();
                final subtitle = _summaryLine(data);

                return ListTile(
                  title: Text(
                    date.isEmpty ? doc.id : date,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(subtitle),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DailyEntryDetailScreen(
                          farmId: widget.farmId,
                          building: widget.building,
                          dailyEntryDocId: doc.id,
                          dateIso: date,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
