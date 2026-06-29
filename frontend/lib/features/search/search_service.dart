import 'dart:convert';

import 'package:drift/drift.dart' hide Column;

import '../../database/database.dart';
import '../seals/seal_list_filters.dart';

class SearchHit {
  SearchHit({
    required this.type,
    required this.id,
    this.sealNumber,
    this.jobId,
    this.jobName,
    this.projectNumber,
    this.floorId,
    this.floorName,
    this.system,
    this.status,
    this.subtitle,
    this.reviewStatus,
    this.photoCount,
  });

  final String type;
  final String id;
  final String? sealNumber;
  final String? jobId;
  final String? jobName;
  final String? projectNumber;
  final String? floorId;
  final String? floorName;
  final String? system;
  final String? status;
  final String? subtitle;
  final String? reviewStatus;
  final int? photoCount;

  factory SearchHit.fromApi(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'seal';
    if (type == 'job') {
      return SearchHit(
        type: 'job',
        id: json['id'] as String,
        jobName: json['jobName'] as String?,
        projectNumber: json['projectNumber'] as String?,
        subtitle: json['projectNumber'] as String?,
      );
    }
    return SearchHit(
      type: 'seal',
      id: json['id'] as String,
      sealNumber: json['sealNumber'] as String?,
      jobId: json['jobId'] as String?,
      jobName: json['jobName'] as String?,
      projectNumber: json['projectNumber'] as String?,
      floorId: json['floorId'] as String?,
      floorName: json['floorName'] as String?,
      system: json['system'] as String?,
      status: json['status'] as String?,
      reviewStatus: json['reviewStatus'] as String?,
      photoCount: json['photoCount'] as int?,
      subtitle: [
        json['jobName'],
        json['floorName'],
        if (json['sealNumber'] != null) '#${json['sealNumber']}',
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
    );
  }
}

bool _containsTerm(String? value, String term) {
  if (value == null || value.isEmpty) return false;
  return value.toLowerCase().contains(term);
}

Future<List<SearchHit>> searchLocal(
  AppDatabase db, {
  required String query,
  String? filters,
  required String? userId,
  required bool isWorker,
  int limit = 25,
}) async {
  final term = query.trim().toLowerCase();
  final parsedFilters = (filters ?? '')
      .split(',')
      .map((v) => SealProblemFilter.fromApi(v.trim()))
      .whereType<SealProblemFilter>()
      .toSet();
  if (term.length < 2 && parsedFilters.isEmpty) return [];

  Set<String>? allowedJobIds;
  if (isWorker && userId != null) {
    final assignments = await (db.select(db.localMyJobAssignments)
          ..where((a) => a.userId.equals(userId)))
        .get();
    allowedJobIds = assignments.map((a) => a.jobId).toSet();
    if (allowedJobIds.isEmpty) return [];
  }

  final hits = <SearchHit>[];
  final likeTerm = '%$term%';
  final matchingJobs = term.length >= 2
      ? await (db.select(db.localJobs)
            ..where((j) {
              var expr = j.deletedAt.isNull() &
                  (j.name.like(likeTerm) | j.projectNumber.like(likeTerm));
              if (allowedJobIds != null) {
                expr = expr & j.id.isIn(allowedJobIds.toList());
              }
              return expr;
            })
            ..limit(limit))
          .get()
      : <LocalJob>[];

  final matchingFloors = term.length >= 2
      ? await (db.select(db.localFloors)
            ..where((f) {
              var expr = f.deletedAt.isNull() & f.name.like(likeTerm);
              if (allowedJobIds != null) {
                expr = expr & f.jobId.isIn(allowedJobIds.toList());
              }
              return expr;
            })
            ..limit(limit * 2))
          .get()
      : <LocalFloor>[];

  if (term.length >= 2) {
    for (final job in matchingJobs) {
      hits.add(SearchHit(
        type: 'job',
        id: job.id,
        jobName: job.name,
        projectNumber: job.projectNumber,
        subtitle: job.projectNumber,
      ));
    }
  }

  final matchingJobIds = matchingJobs.map((j) => j.id).toSet();
  final matchingFloorIds = matchingFloors.map((f) => f.id).toSet();
  final seals = await (db.select(db.localSeals)
        ..where((s) {
          var expr = s.deletedAt.isNull();
          if (allowedJobIds != null) {
            expr = expr & s.jobId.isIn(allowedJobIds.toList());
          }
          if (term.length >= 2) {
            expr = expr &
                (s.sealNumber.like(likeTerm) |
                    s.system.like(likeTerm) |
                    s.construction.like(likeTerm) |
                    s.location.like(likeTerm) |
                    s.fireRating.like(likeTerm) |
                    s.internalNote.like(likeTerm) |
                    (isWorker
                        ? const Constant(false)
                        : s.note.like(likeTerm)) |
                    (matchingJobIds.isEmpty
                        ? const Constant(false)
                        : s.jobId.isIn(matchingJobIds.toList())) |
                    (matchingFloorIds.isEmpty
                        ? const Constant(false)
                        : s.floorId.isIn(matchingFloorIds.toList())));
          }
          return expr;
        })
        ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
        ..limit(limit * 4))
      .get();

  final sealJobIds = seals.map((s) => s.jobId).toSet();
  final sealFloorIds = seals.map((s) => s.floorId).toSet();
  final jobs = sealJobIds.isEmpty
      ? matchingJobs
      : await (db.select(db.localJobs)
            ..where((j) => j.id.isIn({...sealJobIds, ...matchingJobIds}.toList())))
          .get();
  final jobById = {for (final j in jobs) j.id: j};
  final floors = sealFloorIds.isEmpty
      ? matchingFloors
      : await (db.select(db.localFloors)
            ..where((f) =>
                f.id.isIn({...sealFloorIds, ...matchingFloorIds}.toList())))
          .get();
  final floorById = {for (final f in floors) f.id: f};

  final photos = userId == null || seals.isEmpty
      ? <LocalPhoto>[]
      : await (db.select(db.localPhotos)
            ..where((p) => Expression.and([
                  p.userId.equals(userId),
                  p.sealId.isIn(seals.map((s) => s.id).toList()),
                ])))
          .get();
  final photoCounts = <String, int>{};
  for (final photo in photos) {
    photoCounts[photo.sealId] = (photoCounts[photo.sealId] ?? 0) + 1;
  }

  for (final row in seals) {
    if (allowedJobIds != null && !allowedJobIds.contains(row.jobId)) continue;
    final job = jobById[row.jobId];
    final floor = floorById[row.floorId];
    final textMatches = term.length < 2 ||
        _containsTerm(row.sealNumber, term) ||
        _containsTerm(row.system, term) ||
        _containsTerm(row.construction, term) ||
        _containsTerm(row.location, term) ||
        _containsTerm(row.fireRating, term) ||
        _containsTerm(job?.name, term) ||
        _containsTerm(job?.projectNumber, term) ||
        _containsTerm(floor?.name, term) ||
        (isWorker
            ? _containsTerm(row.internalNote, term)
            : _containsTerm(row.note, term) ||
                _containsTerm(row.internalNote, term));
    if (!textMatches) continue;

    final reviewStatus = _localReviewStatus(row);
    final photoCount = photoCounts[row.id] ?? 0;
    if (!_matchesLocalFilters(
      row,
      filters: parsedFilters,
      photoCount: photoCount,
      reviewStatus: reviewStatus,
      currentUserId: userId,
    )) {
      continue;
    }

    hits.add(SearchHit(
      type: 'seal',
      id: row.id,
      sealNumber: row.sealNumber,
      jobId: row.jobId,
      jobName: job?.name,
      projectNumber: job?.projectNumber,
      floorId: row.floorId,
      floorName: floor?.name,
      system: row.system,
      status: row.status,
      reviewStatus: reviewStatus,
      photoCount: photoCount,
      subtitle: [
        job?.name,
        floor?.name,
        '#${row.sealNumber}',
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
    ));
    if (hits.length >= limit) break;
  }

  return hits.take(limit).toList();
}

String? _localReviewStatus(LocalSeal row) {
  final payload = row.jsonPayload;
  if (payload == null || payload.isEmpty) return null;
  try {
    final parsed = jsonDecode(payload) as Map<String, dynamic>;
    return parsed['reviewStatus'] as String?;
  } catch (_) {
    return null;
  }
}

bool _matchesLocalFilters(
  LocalSeal row, {
  required Set<SealProblemFilter> filters,
  required int photoCount,
  required String? reviewStatus,
  required String? currentUserId,
}) {
  for (final filter in filters) {
    switch (filter) {
      case SealProblemFilter.noPhoto:
        if (photoCount > 0) return false;
      case SealProblemFilter.onePhoto:
        if (photoCount != 1) return false;
      case SealProblemFilter.statusDraft:
      case SealProblemFilter.awaitingReview:
        if (row.status != 'draft') return false;
      case SealProblemFilter.statusChecked:
        if (row.status != 'checked') return false;
      case SealProblemFilter.statusInvoiced:
        if (row.status != 'invoiced') return false;
      case SealProblemFilter.mine:
        if (currentUserId == null) return false;
      case SealProblemFilter.attention:
        if (!row.markerPlacementPending) {
          return false;
        }
      case SealProblemFilter.pendingSync:
        if (row.isSynced) return false;
      case SealProblemFilter.hasNote:
        final hasNote = (row.note?.trim().isNotEmpty ?? false) ||
            (row.internalNote?.trim().isNotEmpty ?? false);
        if (!hasNote) return false;
      case SealProblemFilter.missingData:
        if (!row.markerPlacementPending) return false;
    }
  }
  return true;
}
