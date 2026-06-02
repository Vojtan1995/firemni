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
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
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
  TextColumn get system => text()();
  TextColumn get construction => text()();
  TextColumn get location => text()();
  TextColumn get fireRating => text()();
  TextColumn get note => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get syncConflict => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
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

@DriftDatabase(tables: [
  LocalJobs,
  LocalFloors,
  LocalSeals,
  LocalOutbox,
  LocalPhotos,
  SyncCursor
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory DB pro testy / ověření bez path_provider.
  AppDatabase.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

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
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'ucpavky.sqlite'));
    return NativeDatabase(file);
  });
}
