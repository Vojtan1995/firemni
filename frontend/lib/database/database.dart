import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class LocalJobs extends Table {
  TextColumn get id => text()();
  TextColumn get projectNumber => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  TextColumn get status => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class LocalMyJobAssignments extends Table {
  TextColumn get userId => text()();
  TextColumn get jobId => text()();
  TextColumn get roleOnJob => text().withDefault(const Constant('worker'))();
  DateTimeColumn get lastActivityAt => dateTime()();
  @override
  Set<Column> get primaryKey => {userId, jobId};
}

class LocalFloors extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class LocalSeals extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text()();
  TextColumn get floorId => text()();
  TextColumn get sealNumber => text()();
  TextColumn get trade => text().withDefault(const Constant('neurceno'))();
  TextColumn get system => text()();
  TextColumn get construction => text()();
  TextColumn get location => text()();
  TextColumn get fireRating => text()();
  TextColumn get note => text().nullable()();
  TextColumn get internalNote => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get syncConflict => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get markerPlacementPending =>
      boolean().withDefault(const Constant(false))();
  TextColumn get jsonPayload => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class LocalOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get mutationId => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get deviceId => text()();
  TextColumn get entityType => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get conflictMessage => text().nullable()();
  DateTimeColumn get dismissedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class LocalPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get sealId => text()();
  TextColumn get localPath => text()();
  TextColumn get serverPath => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncCursor extends Table {
  TextColumn get key => text()();
  DateTimeColumn get lastPull => dateTime()();
  @override
  Set<Column> get primaryKey => {key};
}

class LocalUserPrefs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class LocalFloorDrawings extends Table {
  TextColumn get floorId => text()();
  TextColumn get jobId => text()();
  TextColumn get filePath => text()();
  TextColumn get localPath => text().nullable()();
  TextColumn get mimeType => text()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();

  /// missing | downloading | downloaded | error
  TextColumn get downloadStatus =>
      text().withDefault(const Constant('downloading'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {floorId};
}

class LocalSealMarkers extends Table {
  TextColumn get sealId => text()();
  TextColumn get floorId => text()();
  TextColumn get sealNumber => text()();
  RealColumn get x => real()();
  RealColumn get y => real()();
  RealColumn get labelOffsetX => real().nullable()();
  RealColumn get labelOffsetY => real().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {sealId};
}

@DriftDatabase(tables: [
  LocalJobs,
  LocalFloors,
  LocalMyJobAssignments,
  LocalSeals,
  LocalOutbox,
  LocalPhotos,
  LocalFloorDrawings,
  LocalSealMarkers,
  SyncCursor,
  LocalUserPrefs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory DB pro testy / ověření bez path_provider.
  AppDatabase.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(localOutbox, localOutbox.conflictMessage);
            await migrator.addColumn(localOutbox, localOutbox.dismissedAt);
          }
          if (from < 3) {
            await migrator.addColumn(localOutbox, localOutbox.retryCount);
            await migrator.addColumn(localOutbox, localOutbox.lastError);
            await migrator.addColumn(localPhotos, localPhotos.nextRetryAt);
            await migrator.addColumn(localPhotos, localPhotos.retryCount);
            await migrator.addColumn(localPhotos, localPhotos.lastError);
          }
          if (from < 4) {
            await migrator.addColumn(localJobs, localJobs.deletedAt);
            await migrator.addColumn(localFloors, localFloors.deletedAt);
            await migrator.addColumn(localSeals, localSeals.deletedAt);
          }
          if (from < 5) {
            await migrator.addColumn(localOutbox, localOutbox.userId);
          }
          if (from < 6) {
            await migrator.addColumn(localSeals, localSeals.internalNote);
          }
          if (from < 7) {
            await migrator.addColumn(localJobs, localJobs.status);
            await migrator.addColumn(localJobs, localJobs.lastSyncedAt);
            await migrator.createTable(localMyJobAssignments);
            await migrator.createTable(localUserPrefs);
          }
          if (from < 8) {
            await migrator.createTable(localFloorDrawings);
            await migrator.createTable(localSealMarkers);
          }
          if (from < 9) {
            await migrator.addColumn(
                localFloorDrawings, localFloorDrawings.downloadStatus);
            await migrator.addColumn(
                localFloorDrawings, localFloorDrawings.retryCount);
            await migrator.addColumn(
                localFloorDrawings, localFloorDrawings.nextRetryAt);
            await migrator.addColumn(
                localFloorDrawings, localFloorDrawings.lastError);
            await migrator.addColumn(
                localSeals, localSeals.markerPlacementPending);
          }
          if (from < 10) {
            await migrator.addColumn(localSeals, localSeals.trade);
          }
          if (from < 11) {
            await migrator.addColumn(localPhotos, localPhotos.userId);
          }
          if (from < 12) {
            await _createPerformanceIndexes();
          }
          if (from < 13) {
            await migrator.addColumn(
                localSealMarkers, localSealMarkers.labelOffsetX);
            await migrator.addColumn(
                localSealMarkers, localSealMarkers.labelOffsetY);
          }
        },
        beforeOpen: (_) async {
          await _createPerformanceIndexes();
        },
      );

  Future<void> _createPerformanceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS local_seals_floor_deleted_updated_idx '
      'ON local_seals(floor_id, deleted_at, updated_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS local_seals_job_idx ON local_seals(job_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS local_photos_user_seal_status_idx '
      'ON local_photos(user_id, seal_id, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS local_outbox_user_status_retry_idx '
      'ON local_outbox(user_id, status, next_retry_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS local_floors_job_idx ON local_floors(job_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS local_my_job_assignments_user_activity_idx '
      'ON local_my_job_assignments(user_id, last_activity_at)',
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'ucpavky.sqlite'));
    return NativeDatabase(file);
  });
}
