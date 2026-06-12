import 'dart:convert';

import '../../database/database.dart';

int compareSealsByUpdatedAt(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aTime = DateTime.tryParse(a['updatedAt'] as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = DateTime.tryParse(b['updatedAt'] as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
  return bTime.compareTo(aTime);
}

void sortSealsByUpdatedAt(List<Map<String, dynamic>> seals) {
  seals.sort(compareSealsByUpdatedAt);
}

bool sealHasNoteForList(Map<String, dynamic> seal, {required bool isWorker}) {
  if (isWorker) {
    return seal['hasInternalNote'] == true;
  }
  return seal['hasPublicNote'] == true || seal['hasInternalNote'] == true;
}

Map<String, dynamic> mapLocalSealListRow(
  LocalSeal row, {
  int photoCount = 0,
  bool isWorker = true,
}) {
  String? reviewStatus;
  if (row.jsonPayload != null && row.jsonPayload!.isNotEmpty) {
    try {
      final payload = jsonDecode(row.jsonPayload!) as Map<String, dynamic>;
      reviewStatus = payload['reviewStatus'] as String?;
    } catch (_) {}
  }

  final hasInternal = row.internalNote != null && row.internalNote!.trim().isNotEmpty;
  final hasPublic = row.note != null && row.note!.trim().isNotEmpty;

  return {
    'id': row.id,
    'sealNumber': row.sealNumber,
    'status': row.status,
    'version': row.version,
    'photoCount': photoCount,
    'updatedAt': row.updatedAt.toIso8601String(),
    'hasInternalNote': hasInternal,
    'hasPublicNote': !isWorker && hasPublic,
    'reviewStatus': reviewStatus,
    'isSynced': row.isSynced,
    'syncConflict': row.syncConflict,
    'markerPlacementPending': row.markerPlacementPending,
  };
}
