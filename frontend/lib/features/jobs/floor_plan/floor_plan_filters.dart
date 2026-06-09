enum FloorPlanMarkerFilter {
  all,
  mine,
  byWorker,
  byStatus,
  selected,
  placedOnly,
  unplacedOnly,
  draftOnly,
  checkedOnly,
  invoicedOnly,
  returnedOnly,
}

class FloorPlanWorkerOption {
  const FloorPlanWorkerOption({required this.id, required this.name});

  final String id;
  final String name;
}

class FloorPlanFilterState {
  const FloorPlanFilterState({
    this.mode = FloorPlanMarkerFilter.all,
    this.workerId,
    this.workerName,
    this.status,
    this.selectedSealIds = const {},
    this.selectedSealNumbers = const {},
  });

  final FloorPlanMarkerFilter mode;
  final String? workerId;
  final String? workerName;
  final String? status;
  final Set<String> selectedSealIds;
  final Set<String> selectedSealNumbers;

  bool get isActive => mode != FloorPlanMarkerFilter.all;

  FloorPlanFilterState copyWith({
    FloorPlanMarkerFilter? mode,
    String? workerId,
    String? workerName,
    String? status,
    Set<String>? selectedSealIds,
    Set<String>? selectedSealNumbers,
    bool clearWorker = false,
    bool clearStatus = false,
    bool clearSelected = false,
  }) {
    return FloorPlanFilterState(
      mode: mode ?? this.mode,
      workerId: clearWorker ? null : (workerId ?? this.workerId),
      workerName: clearWorker ? null : (workerName ?? this.workerName),
      status: clearStatus ? null : (status ?? this.status),
      selectedSealIds:
          clearSelected ? const {} : (selectedSealIds ?? this.selectedSealIds),
      selectedSealNumbers: clearSelected
          ? const {}
          : (selectedSealNumbers ?? this.selectedSealNumbers),
    );
  }

  static const FloorPlanFilterState allFilters = FloorPlanFilterState();

  bool matchesMarker({
    required Map<String, dynamic> marker,
    required Set<String> placedSealIds,
    required String? currentUserId,
    required String? createdById,
  }) {
    final sealId = marker['sealId'] as String;
    final status = marker['status'] as String? ?? 'draft';
    final reviewStatus = marker['reviewStatus'] as String?;

    switch (mode) {
      case FloorPlanMarkerFilter.all:
        return true;
      case FloorPlanMarkerFilter.mine:
        return createdById != null && createdById == currentUserId;
      case FloorPlanMarkerFilter.byWorker:
        return workerId != null && createdById == workerId;
      case FloorPlanMarkerFilter.byStatus:
        if (this.status == null) return false;
        if (this.status == 'returned') return reviewStatus == 'returned';
        return status == this.status && reviewStatus != 'returned';
      case FloorPlanMarkerFilter.selected:
        return selectedSealIds.contains(sealId);
      case FloorPlanMarkerFilter.placedOnly:
        return placedSealIds.contains(sealId);
      case FloorPlanMarkerFilter.unplacedOnly:
        return false;
      case FloorPlanMarkerFilter.draftOnly:
        return status == 'draft' && reviewStatus != 'returned';
      case FloorPlanMarkerFilter.checkedOnly:
        return status == 'checked';
      case FloorPlanMarkerFilter.invoicedOnly:
        return status == 'invoiced';
      case FloorPlanMarkerFilter.returnedOnly:
        return reviewStatus == 'returned';
    }
  }

  bool matchesUnplacedSeal(Map<String, dynamic> seal, String? currentUserId) {
    if (mode == FloorPlanMarkerFilter.selected) {
      return selectedSealIds.contains(seal['id']);
    }
    if (mode != FloorPlanMarkerFilter.unplacedOnly &&
        mode != FloorPlanMarkerFilter.all) {
      final status = seal['status'] as String? ?? 'draft';
      final reviewStatus = seal['reviewStatus'] as String?;
      final createdById = seal['createdById'] as String?;
      switch (mode) {
        case FloorPlanMarkerFilter.mine:
          if (createdById != currentUserId) return false;
          break;
        case FloorPlanMarkerFilter.byWorker:
          if (workerId == null || createdById != workerId) return false;
          break;
        case FloorPlanMarkerFilter.byStatus:
          if (this.status == null) return false;
          if (this.status == 'returned') {
            if (reviewStatus != 'returned') return false;
          } else if (status != this.status || reviewStatus == 'returned') {
            return false;
          }
          break;
        case FloorPlanMarkerFilter.draftOnly:
          if (status != 'draft' || reviewStatus == 'returned') return false;
          break;
        case FloorPlanMarkerFilter.checkedOnly:
          if (status != 'checked') return false;
          break;
        case FloorPlanMarkerFilter.invoicedOnly:
          if (status != 'invoiced') return false;
          break;
        case FloorPlanMarkerFilter.returnedOnly:
          if (reviewStatus != 'returned') return false;
          break;
        default:
          break;
      }
    }
    return true;
  }

  String get label {
    switch (mode) {
      case FloorPlanMarkerFilter.all:
        return 'Všechny ucpávky';
      case FloorPlanMarkerFilter.mine:
        return 'Pouze moje';
      case FloorPlanMarkerFilter.byWorker:
        return 'Podle montéra';
      case FloorPlanMarkerFilter.byStatus:
        return 'Podle stavu';
      case FloorPlanMarkerFilter.selected:
        return 'Vybrané ucpávky';
      case FloorPlanMarkerFilter.placedOnly:
        return 'Pouze umístěné';
      case FloorPlanMarkerFilter.unplacedOnly:
        return 'Pouze neumístěné';
      case FloorPlanMarkerFilter.draftOnly:
        return 'Rozpracované';
      case FloorPlanMarkerFilter.checkedOnly:
        return 'Zkontrolované';
      case FloorPlanMarkerFilter.invoicedOnly:
        return 'Fakturované';
      case FloorPlanMarkerFilter.returnedOnly:
        return 'Vrácené k opravě';
    }
  }

  String get description {
    switch (mode) {
      case FloorPlanMarkerFilter.all:
        return label;
      case FloorPlanMarkerFilter.byWorker:
        if (workerName != null && workerName!.isNotEmpty) {
          return '$label: $workerName';
        }
        return label;
      case FloorPlanMarkerFilter.byStatus:
        if (status != null) return '$label: ${_statusLabel(status!)}';
        return label;
      case FloorPlanMarkerFilter.selected:
        if (selectedSealNumbers.isEmpty) return label;
        final nums = selectedSealNumbers.toList()..sort();
        final preview = nums.length <= 5
            ? nums.join(', ')
            : '${nums.take(5).join(', ')}…';
        return '$label (${nums.length}): $preview';
      default:
        return label;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Rozpracované';
      case 'checked':
        return 'Zkontrolované';
      case 'invoiced':
        return 'Fakturované';
      case 'returned':
        return 'Vrácené k opravě';
      default:
        return status;
    }
  }

  static Set<String> sealIdsFromNumbers(
    String input,
    List<Map<String, dynamic>> floorSeals,
  ) {
    final numbers = input
        .split(RegExp(r'[,;\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (numbers.isEmpty) return {};
    final byNumber = {
      for (final s in floorSeals) s['sealNumber'] as String: s['id'] as String,
    };
    return numbers
        .map((n) => byNumber[n])
        .whereType<String>()
        .toSet();
  }

  static Set<String> sealNumbersFromIds(
    Set<String> ids,
    List<Map<String, dynamic>> floorSeals,
  ) {
    final byId = {
      for (final s in floorSeals) s['id'] as String: s['sealNumber'] as String,
    };
    return ids.map((id) => byId[id]).whereType<String>().toSet();
  }

  static List<FloorPlanWorkerOption> workersFromSeals(
    List<Map<String, dynamic>> floorSeals,
  ) {
    final map = <String, String>{};
    for (final s in floorSeals) {
      final id = s['createdById'] as String?;
      if (id == null) continue;
      final name = s['createdByName'] as String? ?? id;
      map[id] = name;
    }
    return map.entries
        .map((e) => FloorPlanWorkerOption(id: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  bool get isValidForApply {
    switch (mode) {
      case FloorPlanMarkerFilter.byWorker:
        return workerId != null;
      case FloorPlanMarkerFilter.byStatus:
        return status != null;
      case FloorPlanMarkerFilter.selected:
        return selectedSealIds.isNotEmpty;
      default:
        return true;
    }
  }

  /// Query params for PDF export API. Returns `null` when export is not supported.
  Map<String, String>? toExportQueryParams({required String? currentUserId}) {
    switch (mode) {
      case FloorPlanMarkerFilter.all:
      case FloorPlanMarkerFilter.placedOnly:
        return {};
      case FloorPlanMarkerFilter.unplacedOnly:
        return null;
      case FloorPlanMarkerFilter.mine:
        if (currentUserId == null) return {};
        return {'workerId': currentUserId};
      case FloorPlanMarkerFilter.byWorker:
        if (workerId == null) return {};
        return {'workerId': workerId!};
      case FloorPlanMarkerFilter.byStatus:
        if (status == null) return {};
        if (status == 'returned') return {'reviewStatus': 'returned'};
        return {'status': status!};
      case FloorPlanMarkerFilter.draftOnly:
        return {'status': 'draft'};
      case FloorPlanMarkerFilter.checkedOnly:
        return {'status': 'checked'};
      case FloorPlanMarkerFilter.invoicedOnly:
        return {'status': 'invoiced'};
      case FloorPlanMarkerFilter.returnedOnly:
        return {'reviewStatus': 'returned'};
      case FloorPlanMarkerFilter.selected:
        if (selectedSealIds.isEmpty) return {};
        return {'sealIds': selectedSealIds.join(',')};
    }
  }
}
