import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database.dart';
import '../../database/database_provider.dart';

/// Poslední pracovní kontext — zakázka / patro / ucpávka (offline v Drift).
class WorkContext {
  const WorkContext({
    required this.jobId,
    this.floorId,
    this.sealId,
    this.jobName,
    this.floorName,
    required this.updatedAt,
  });

  final String jobId;
  final String? floorId;
  final String? sealId;
  final String? jobName;
  final String? floorName;
  final DateTime updatedAt;

  factory WorkContext.fromJson(Map<String, dynamic> json) {
    return WorkContext(
      jobId: json['jobId'] as String,
      floorId: json['floorId'] as String?,
      sealId: json['sealId'] as String?,
      jobName: json['jobName'] as String?,
      floorName: json['floorName'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        if (floorId != null) 'floorId': floorId,
        if (sealId != null) 'sealId': sealId,
        if (jobName != null) 'jobName': jobName,
        if (floorName != null) 'floorName': floorName,
        'updatedAt': updatedAt.toIso8601String(),
      };

  bool get hasResumeTarget => jobId.isNotEmpty;

  String get resumeSubtitle {
    final parts = <String>[];
    if (jobName != null && jobName!.isNotEmpty) parts.add(jobName!);
    if (floorName != null && floorName!.isNotEmpty) parts.add(floorName!);
    if (sealId != null) parts.add('ucpávka');
    if (parts.isEmpty) return jobId;
    return parts.join(' · ');
  }
}

class WorkContextService {
  WorkContextService(this.db);

  final AppDatabase db;

  static String _contextKey(String userId) => 'work_context_$userId';

  Future<void> _setPref(String key, String value) async {
    await db.into(db.localUserPrefs).insertOnConflictUpdate(
          LocalUserPrefsCompanion.insert(key: key, value: value),
        );
  }

  Future<String?> _getPref(String key) async {
    final row = await (db.select(db.localUserPrefs)
          ..where((p) => p.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<String?> _resolveJobName(String jobId) async {
    final job = await (db.select(db.localJobs)
          ..where((j) => j.id.equals(jobId)))
        .getSingleOrNull();
    return job?.name;
  }

  Future<String?> _resolveFloorName(String floorId) async {
    final floor = await (db.select(db.localFloors)
          ..where((f) => f.id.equals(floorId)))
        .getSingleOrNull();
    return floor?.name;
  }

  Future<void> _touchAssignment(String userId, String jobId, DateTime when) async {
    await (db.update(db.localMyJobAssignments)
          ..where((a) => a.userId.equals(userId) & a.jobId.equals(jobId)))
        .write(LocalMyJobAssignmentsCompanion(lastActivityAt: Value(when)));
  }

  Future<void> _persist(WorkContext ctx, String userId) async {
    await _setPref(_contextKey(userId), jsonEncode(ctx.toJson()));
    await _setPref('last_job_id_$userId', ctx.jobId);
    if (ctx.floorId != null) {
      await _setPref('last_floor_id_$userId', ctx.floorId!);
    }
    await _setPref('last_opened_at_$userId', ctx.updatedAt.toIso8601String());
    await _touchAssignment(userId, ctx.jobId, ctx.updatedAt);
  }

  /// Uloží kontext na úrovni zakázky (bez patra/ucpávky).
  Future<void> saveJob({
    required String userId,
    required String jobId,
    String? jobName,
  }) async {
    final now = DateTime.now();
    final ctx = WorkContext(
      jobId: jobId,
      jobName: jobName ?? await _resolveJobName(jobId),
      updatedAt: now,
    );
    await _persist(ctx, userId);
  }

  /// Uloží kontext patra (bez konkrétní ucpávky).
  Future<void> saveFloor({
    required String userId,
    required String jobId,
    required String floorId,
    String? jobName,
    String? floorName,
  }) async {
    final now = DateTime.now();
    final ctx = WorkContext(
      jobId: jobId,
      floorId: floorId,
      jobName: jobName ?? await _resolveJobName(jobId),
      floorName: floorName ?? await _resolveFloorName(floorId),
      updatedAt: now,
    );
    await _persist(ctx, userId);
  }

  /// Uloží kontext konkrétní ucpávky.
  Future<void> saveSeal({
    required String userId,
    required String jobId,
    required String floorId,
    required String sealId,
    String? jobName,
    String? floorName,
  }) async {
    final now = DateTime.now();
    final ctx = WorkContext(
      jobId: jobId,
      floorId: floorId,
      sealId: sealId,
      jobName: jobName ?? await _resolveJobName(jobId),
      floorName: floorName ?? await _resolveFloorName(floorId),
      updatedAt: now,
    );
    await _persist(ctx, userId);
  }

  Future<WorkContext?> load(String userId) async {
    final raw = await _getPref(_contextKey(userId));
    if (raw != null && raw.isNotEmpty) {
      try {
        final ctx = WorkContext.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (ctx.jobId.isEmpty) return null;
        return ctx;
      } catch (_) {}
    }

    final jobId = await _getPref('last_job_id_$userId');
    if (jobId == null || jobId.isEmpty) return null;
    final floorId = await _getPref('last_floor_id_$userId');
    final openedAt = await _getPref('last_opened_at_$userId');
    return WorkContext(
      jobId: jobId,
      floorId: floorId,
      jobName: await _resolveJobName(jobId),
      floorName: floorId != null ? await _resolveFloorName(floorId) : null,
      updatedAt: DateTime.tryParse(openedAt ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Cílová route pro návrat do práce (go_router).
  String resumeRoute(WorkContext ctx) {
    if (ctx.sealId != null && ctx.sealId!.isNotEmpty) {
      return '/seal/${ctx.sealId}';
    }
    if (ctx.floorId != null && ctx.floorId!.isNotEmpty) {
      return '/seals/${ctx.floorId}?jobId=${ctx.jobId}';
    }
    return '/floors/${ctx.jobId}';
  }
}

final workContextServiceProvider = Provider<WorkContextService>((ref) {
  return WorkContextService(ref.watch(databaseProvider));
});
