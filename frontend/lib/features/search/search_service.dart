import 'package:drift/drift.dart' hide Column;

import '../../database/database.dart';
import '../seals/seal_list_helpers.dart';

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
  required String? userId,
  required bool isWorker,
  int limit = 25,
}) async {
  final term = query.trim().toLowerCase();
  if (term.length < 2) return [];

  Set<String>? allowedJobIds;
  if (isWorker && userId != null) {
    final assignments = await (db.select(db.localMyJobAssignments)
          ..where((a) => a.userId.equals(userId)))
        .get();
    allowedJobIds = assignments.map((a) => a.jobId).toSet();
    if (allowedJobIds.isEmpty) return [];
  }

  final seals = await (db.select(db.localSeals)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
      .get();

  final jobs = await db.select(db.localJobs).get();
  final jobById = {for (final j in jobs) j.id: j};
  final floors = await db.select(db.localFloors).get();
  final floorById = {for (final f in floors) f.id: f};

  final hits = <SearchHit>[];

  for (final job in jobs) {
    if (job.deletedAt != null) continue;
    if (allowedJobIds != null && !allowedJobIds.contains(job.id)) continue;
    if (_containsTerm(job.name, term) || _containsTerm(job.projectNumber, term)) {
      hits.add(SearchHit(
        type: 'job',
        id: job.id,
        jobName: job.name,
        projectNumber: job.projectNumber,
        subtitle: job.projectNumber,
      ));
    }
  }

  for (final row in seals) {
    if (allowedJobIds != null && !allowedJobIds.contains(row.jobId)) continue;
    final job = jobById[row.jobId];
    final floor = floorById[row.floorId];
    final match = _containsTerm(row.sealNumber, term) ||
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
    if (!match) continue;
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
