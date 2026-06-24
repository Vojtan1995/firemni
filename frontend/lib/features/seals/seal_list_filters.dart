import 'seal_list_helpers.dart';
import 'seal_validation.dart';

/// Problémové filtry seznamu ucpávek (Task 3.5).
enum SealProblemFilter {
  noPhoto('no_photo', 'Bez fotky'),
  onePhoto('one_photo', '1 fotka'),
  awaitingReview('awaiting_review', 'Čeká kontrolu'),
  pendingSync('pending_sync', 'Čeká sync'),
  hasNote('has_note', 'Má poznámku'),
  missingData('missing_data', 'Nedokončené'),
  // Task 6 – praktické filtry.
  mine('mine', 'Moje'),
  statusDraft('status_draft', 'Rozpracované'),
  statusChecked('status_checked', 'Zkontrolované'),
  statusInvoiced('status_invoiced', 'Fakturované'),
  attention('attention', 'K řešení');

  const SealProblemFilter(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static SealProblemFilter? fromApi(String value) {
    for (final f in SealProblemFilter.values) {
      if (f.apiValue == value) return f;
    }
    return null;
  }
}

List<String> sealFiltersToApi(Set<SealProblemFilter> filters) {
  return filters
      .where((f) => f != SealProblemFilter.pendingSync)
      .map((f) => f.apiValue)
      .toList();
}

bool sealMatchesFilters(
  Map<String, dynamic> seal, {
  required Set<SealProblemFilter> filters,
  required bool isWorker,
  String? currentUserId,
}) {
  if (filters.isEmpty) return true;

  final photoCount = seal['photoCount'] as int? ?? 0;
  final status = seal['status'] as String? ?? 'draft';
  final isSynced = seal['isSynced'] as bool? ?? true;

  for (final f in filters) {
    switch (f) {
      case SealProblemFilter.noPhoto:
        if (photoCount > 0) return false;
      case SealProblemFilter.onePhoto:
        if (photoCount != 1) return false;
      case SealProblemFilter.awaitingReview:
        if (status != 'draft') return false;
      case SealProblemFilter.pendingSync:
        if (isSynced) return false;
      case SealProblemFilter.hasNote:
        if (!sealHasNoteForList(seal, isWorker: isWorker)) return false;
      case SealProblemFilter.missingData:
        if (validateSealForChecked(_sealForValidation(seal)).isEmpty) {
          return false;
        }
      case SealProblemFilter.mine:
        if (currentUserId == null || seal['createdById'] != currentUserId) {
          return false;
        }
      case SealProblemFilter.statusDraft:
        if (status != 'draft') return false;
      case SealProblemFilter.statusChecked:
        if (status != 'checked') return false;
      case SealProblemFilter.statusInvoiced:
        if (status != 'invoiced') return false;
      case SealProblemFilter.attention:
        // „K řešení": nedokončené.
        final hasMissing =
            validateSealForChecked(_sealForValidation(seal)).isNotEmpty;
        if (!hasMissing) return false;
    }
  }
  return true;
}

Map<String, dynamic> _sealForValidation(Map<String, dynamic> seal) {
  final photoCount = seal['photoCount'] as int? ?? 0;
  return {
    'system': seal['system'] ?? '',
    'construction': seal['construction'] ?? '',
    'location': seal['location'] ?? '',
    'fireRating': seal['fireRating'] ?? '',
    'photos': List.generate(photoCount, (i) => {'id': '$i'}),
    'entries': seal['entries'] as List? ?? [],
  };
}

List<Map<String, dynamic>> applySealListFilters(
  List<Map<String, dynamic>> seals, {
  required Set<SealProblemFilter> filters,
  required bool isWorker,
  String? currentUserId,
}) {
  if (filters.isEmpty) return seals;
  return seals
      .where((s) => sealMatchesFilters(
            s,
            filters: filters,
            isWorker: isWorker,
            currentUserId: currentUserId,
          ))
      .toList();
}
