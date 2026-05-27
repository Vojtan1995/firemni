// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $LocalJobsTable extends LocalJobs
    with TableInfo<$LocalJobsTable, LocalJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _projectNumberMeta =
      const VerificationMeta('projectNumber');
  @override
  late final GeneratedColumn<String> projectNumber = GeneratedColumn<String>(
      'project_number', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _addressMeta =
      const VerificationMeta('address');
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
      'address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, projectNumber, name, address, isArchived, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_jobs';
  @override
  VerificationContext validateIntegrity(Insertable<LocalJob> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_number')) {
      context.handle(
          _projectNumberMeta,
          projectNumber.isAcceptableOrUnknown(
              data['project_number']!, _projectNumberMeta));
    } else if (isInserting) {
      context.missing(_projectNumberMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('address')) {
      context.handle(_addressMeta,
          address.isAcceptableOrUnknown(data['address']!, _addressMeta));
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalJob(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      projectNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}project_number'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      address: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}address']),
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LocalJobsTable createAlias(String alias) {
    return $LocalJobsTable(attachedDatabase, alias);
  }
}

class LocalJob extends DataClass implements Insertable<LocalJob> {
  final String id;
  final String projectNumber;
  final String name;
  final String? address;
  final bool isArchived;
  final DateTime updatedAt;
  const LocalJob(
      {required this.id,
      required this.projectNumber,
      required this.name,
      this.address,
      required this.isArchived,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_number'] = Variable<String>(projectNumber);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalJobsCompanion toCompanion(bool nullToAbsent) {
    return LocalJobsCompanion(
      id: Value(id),
      projectNumber: Value(projectNumber),
      name: Value(name),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      isArchived: Value(isArchived),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalJob.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalJob(
      id: serializer.fromJson<String>(json['id']),
      projectNumber: serializer.fromJson<String>(json['projectNumber']),
      name: serializer.fromJson<String>(json['name']),
      address: serializer.fromJson<String?>(json['address']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectNumber': serializer.toJson<String>(projectNumber),
      'name': serializer.toJson<String>(name),
      'address': serializer.toJson<String?>(address),
      'isArchived': serializer.toJson<bool>(isArchived),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalJob copyWith(
          {String? id,
          String? projectNumber,
          String? name,
          Value<String?> address = const Value.absent(),
          bool? isArchived,
          DateTime? updatedAt}) =>
      LocalJob(
        id: id ?? this.id,
        projectNumber: projectNumber ?? this.projectNumber,
        name: name ?? this.name,
        address: address.present ? address.value : this.address,
        isArchived: isArchived ?? this.isArchived,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LocalJob copyWithCompanion(LocalJobsCompanion data) {
    return LocalJob(
      id: data.id.present ? data.id.value : this.id,
      projectNumber: data.projectNumber.present
          ? data.projectNumber.value
          : this.projectNumber,
      name: data.name.present ? data.name.value : this.name,
      address: data.address.present ? data.address.value : this.address,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalJob(')
          ..write('id: $id, ')
          ..write('projectNumber: $projectNumber, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('isArchived: $isArchived, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, projectNumber, name, address, isArchived, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalJob &&
          other.id == this.id &&
          other.projectNumber == this.projectNumber &&
          other.name == this.name &&
          other.address == this.address &&
          other.isArchived == this.isArchived &&
          other.updatedAt == this.updatedAt);
}

class LocalJobsCompanion extends UpdateCompanion<LocalJob> {
  final Value<String> id;
  final Value<String> projectNumber;
  final Value<String> name;
  final Value<String?> address;
  final Value<bool> isArchived;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalJobsCompanion({
    this.id = const Value.absent(),
    this.projectNumber = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalJobsCompanion.insert({
    required String id,
    required String projectNumber,
    required String name,
    this.address = const Value.absent(),
    this.isArchived = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        projectNumber = Value(projectNumber),
        name = Value(name),
        updatedAt = Value(updatedAt);
  static Insertable<LocalJob> custom({
    Expression<String>? id,
    Expression<String>? projectNumber,
    Expression<String>? name,
    Expression<String>? address,
    Expression<bool>? isArchived,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectNumber != null) 'project_number': projectNumber,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (isArchived != null) 'is_archived': isArchived,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalJobsCompanion copyWith(
      {Value<String>? id,
      Value<String>? projectNumber,
      Value<String>? name,
      Value<String?>? address,
      Value<bool>? isArchived,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LocalJobsCompanion(
      id: id ?? this.id,
      projectNumber: projectNumber ?? this.projectNumber,
      name: name ?? this.name,
      address: address ?? this.address,
      isArchived: isArchived ?? this.isArchived,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectNumber.present) {
      map['project_number'] = Variable<String>(projectNumber.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalJobsCompanion(')
          ..write('id: $id, ')
          ..write('projectNumber: $projectNumber, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('isArchived: $isArchived, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalFloorsTable extends LocalFloors
    with TableInfo<$LocalFloorsTable, LocalFloor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFloorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
      'job_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, jobId, name, sortOrder, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_floors';
  @override
  VerificationContext validateIntegrity(Insertable<LocalFloor> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
          _jobIdMeta, jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta));
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalFloor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFloor(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      jobId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}job_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LocalFloorsTable createAlias(String alias) {
    return $LocalFloorsTable(attachedDatabase, alias);
  }
}

class LocalFloor extends DataClass implements Insertable<LocalFloor> {
  final String id;
  final String jobId;
  final String name;
  final int sortOrder;
  final DateTime updatedAt;
  const LocalFloor(
      {required this.id,
      required this.jobId,
      required this.name,
      required this.sortOrder,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['job_id'] = Variable<String>(jobId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalFloorsCompanion toCompanion(bool nullToAbsent) {
    return LocalFloorsCompanion(
      id: Value(id),
      jobId: Value(jobId),
      name: Value(name),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalFloor.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFloor(
      id: serializer.fromJson<String>(json['id']),
      jobId: serializer.fromJson<String>(json['jobId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'jobId': serializer.toJson<String>(jobId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalFloor copyWith(
          {String? id,
          String? jobId,
          String? name,
          int? sortOrder,
          DateTime? updatedAt}) =>
      LocalFloor(
        id: id ?? this.id,
        jobId: jobId ?? this.jobId,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LocalFloor copyWithCompanion(LocalFloorsCompanion data) {
    return LocalFloor(
      id: data.id.present ? data.id.value : this.id,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFloor(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, jobId, name, sortOrder, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFloor &&
          other.id == this.id &&
          other.jobId == this.jobId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt);
}

class LocalFloorsCompanion extends UpdateCompanion<LocalFloor> {
  final Value<String> id;
  final Value<String> jobId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalFloorsCompanion({
    this.id = const Value.absent(),
    this.jobId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFloorsCompanion.insert({
    required String id,
    required String jobId,
    required String name,
    this.sortOrder = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        jobId = Value(jobId),
        name = Value(name),
        updatedAt = Value(updatedAt);
  static Insertable<LocalFloor> custom({
    Expression<String>? id,
    Expression<String>? jobId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jobId != null) 'job_id': jobId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFloorsCompanion copyWith(
      {Value<String>? id,
      Value<String>? jobId,
      Value<String>? name,
      Value<int>? sortOrder,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LocalFloorsCompanion(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFloorsCompanion(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSealsTable extends LocalSeals
    with TableInfo<$LocalSealsTable, LocalSeal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSealsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
      'job_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _floorIdMeta =
      const VerificationMeta('floorId');
  @override
  late final GeneratedColumn<String> floorId = GeneratedColumn<String>(
      'floor_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sealNumberMeta =
      const VerificationMeta('sealNumber');
  @override
  late final GeneratedColumn<String> sealNumber = GeneratedColumn<String>(
      'seal_number', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _systemMeta = const VerificationMeta('system');
  @override
  late final GeneratedColumn<String> system = GeneratedColumn<String>(
      'system', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _constructionMeta =
      const VerificationMeta('construction');
  @override
  late final GeneratedColumn<String> construction = GeneratedColumn<String>(
      'construction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _locationMeta =
      const VerificationMeta('location');
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
      'location', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fireRatingMeta =
      const VerificationMeta('fireRating');
  @override
  late final GeneratedColumn<String> fireRating = GeneratedColumn<String>(
      'fire_rating', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('draft'));
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _syncConflictMeta =
      const VerificationMeta('syncConflict');
  @override
  late final GeneratedColumn<bool> syncConflict = GeneratedColumn<bool>(
      'sync_conflict', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("sync_conflict" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isSyncedMeta =
      const VerificationMeta('isSynced');
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
      'is_synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _jsonPayloadMeta =
      const VerificationMeta('jsonPayload');
  @override
  late final GeneratedColumn<String> jsonPayload = GeneratedColumn<String>(
      'json_payload', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        jobId,
        floorId,
        sealNumber,
        system,
        construction,
        location,
        fireRating,
        note,
        status,
        version,
        syncConflict,
        isSynced,
        jsonPayload,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_seals';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSeal> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
          _jobIdMeta, jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta));
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('floor_id')) {
      context.handle(_floorIdMeta,
          floorId.isAcceptableOrUnknown(data['floor_id']!, _floorIdMeta));
    } else if (isInserting) {
      context.missing(_floorIdMeta);
    }
    if (data.containsKey('seal_number')) {
      context.handle(
          _sealNumberMeta,
          sealNumber.isAcceptableOrUnknown(
              data['seal_number']!, _sealNumberMeta));
    } else if (isInserting) {
      context.missing(_sealNumberMeta);
    }
    if (data.containsKey('system')) {
      context.handle(_systemMeta,
          system.isAcceptableOrUnknown(data['system']!, _systemMeta));
    } else if (isInserting) {
      context.missing(_systemMeta);
    }
    if (data.containsKey('construction')) {
      context.handle(
          _constructionMeta,
          construction.isAcceptableOrUnknown(
              data['construction']!, _constructionMeta));
    } else if (isInserting) {
      context.missing(_constructionMeta);
    }
    if (data.containsKey('location')) {
      context.handle(_locationMeta,
          location.isAcceptableOrUnknown(data['location']!, _locationMeta));
    } else if (isInserting) {
      context.missing(_locationMeta);
    }
    if (data.containsKey('fire_rating')) {
      context.handle(
          _fireRatingMeta,
          fireRating.isAcceptableOrUnknown(
              data['fire_rating']!, _fireRatingMeta));
    } else if (isInserting) {
      context.missing(_fireRatingMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('sync_conflict')) {
      context.handle(
          _syncConflictMeta,
          syncConflict.isAcceptableOrUnknown(
              data['sync_conflict']!, _syncConflictMeta));
    }
    if (data.containsKey('is_synced')) {
      context.handle(_isSyncedMeta,
          isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta));
    }
    if (data.containsKey('json_payload')) {
      context.handle(
          _jsonPayloadMeta,
          jsonPayload.isAcceptableOrUnknown(
              data['json_payload']!, _jsonPayloadMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalSeal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSeal(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      jobId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}job_id'])!,
      floorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}floor_id'])!,
      sealNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}seal_number'])!,
      system: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}system'])!,
      construction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}construction'])!,
      location: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}location'])!,
      fireRating: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fire_rating'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      syncConflict: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}sync_conflict'])!,
      isSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_synced'])!,
      jsonPayload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json_payload']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LocalSealsTable createAlias(String alias) {
    return $LocalSealsTable(attachedDatabase, alias);
  }
}

class LocalSeal extends DataClass implements Insertable<LocalSeal> {
  final String id;
  final String jobId;
  final String floorId;
  final String sealNumber;
  final String system;
  final String construction;
  final String location;
  final String fireRating;
  final String? note;
  final String status;
  final int version;
  final bool syncConflict;
  final bool isSynced;
  final String? jsonPayload;
  final DateTime updatedAt;
  const LocalSeal(
      {required this.id,
      required this.jobId,
      required this.floorId,
      required this.sealNumber,
      required this.system,
      required this.construction,
      required this.location,
      required this.fireRating,
      this.note,
      required this.status,
      required this.version,
      required this.syncConflict,
      required this.isSynced,
      this.jsonPayload,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['job_id'] = Variable<String>(jobId);
    map['floor_id'] = Variable<String>(floorId);
    map['seal_number'] = Variable<String>(sealNumber);
    map['system'] = Variable<String>(system);
    map['construction'] = Variable<String>(construction);
    map['location'] = Variable<String>(location);
    map['fire_rating'] = Variable<String>(fireRating);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['status'] = Variable<String>(status);
    map['version'] = Variable<int>(version);
    map['sync_conflict'] = Variable<bool>(syncConflict);
    map['is_synced'] = Variable<bool>(isSynced);
    if (!nullToAbsent || jsonPayload != null) {
      map['json_payload'] = Variable<String>(jsonPayload);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalSealsCompanion toCompanion(bool nullToAbsent) {
    return LocalSealsCompanion(
      id: Value(id),
      jobId: Value(jobId),
      floorId: Value(floorId),
      sealNumber: Value(sealNumber),
      system: Value(system),
      construction: Value(construction),
      location: Value(location),
      fireRating: Value(fireRating),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      status: Value(status),
      version: Value(version),
      syncConflict: Value(syncConflict),
      isSynced: Value(isSynced),
      jsonPayload: jsonPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(jsonPayload),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalSeal.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSeal(
      id: serializer.fromJson<String>(json['id']),
      jobId: serializer.fromJson<String>(json['jobId']),
      floorId: serializer.fromJson<String>(json['floorId']),
      sealNumber: serializer.fromJson<String>(json['sealNumber']),
      system: serializer.fromJson<String>(json['system']),
      construction: serializer.fromJson<String>(json['construction']),
      location: serializer.fromJson<String>(json['location']),
      fireRating: serializer.fromJson<String>(json['fireRating']),
      note: serializer.fromJson<String?>(json['note']),
      status: serializer.fromJson<String>(json['status']),
      version: serializer.fromJson<int>(json['version']),
      syncConflict: serializer.fromJson<bool>(json['syncConflict']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      jsonPayload: serializer.fromJson<String?>(json['jsonPayload']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'jobId': serializer.toJson<String>(jobId),
      'floorId': serializer.toJson<String>(floorId),
      'sealNumber': serializer.toJson<String>(sealNumber),
      'system': serializer.toJson<String>(system),
      'construction': serializer.toJson<String>(construction),
      'location': serializer.toJson<String>(location),
      'fireRating': serializer.toJson<String>(fireRating),
      'note': serializer.toJson<String?>(note),
      'status': serializer.toJson<String>(status),
      'version': serializer.toJson<int>(version),
      'syncConflict': serializer.toJson<bool>(syncConflict),
      'isSynced': serializer.toJson<bool>(isSynced),
      'jsonPayload': serializer.toJson<String?>(jsonPayload),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalSeal copyWith(
          {String? id,
          String? jobId,
          String? floorId,
          String? sealNumber,
          String? system,
          String? construction,
          String? location,
          String? fireRating,
          Value<String?> note = const Value.absent(),
          String? status,
          int? version,
          bool? syncConflict,
          bool? isSynced,
          Value<String?> jsonPayload = const Value.absent(),
          DateTime? updatedAt}) =>
      LocalSeal(
        id: id ?? this.id,
        jobId: jobId ?? this.jobId,
        floorId: floorId ?? this.floorId,
        sealNumber: sealNumber ?? this.sealNumber,
        system: system ?? this.system,
        construction: construction ?? this.construction,
        location: location ?? this.location,
        fireRating: fireRating ?? this.fireRating,
        note: note.present ? note.value : this.note,
        status: status ?? this.status,
        version: version ?? this.version,
        syncConflict: syncConflict ?? this.syncConflict,
        isSynced: isSynced ?? this.isSynced,
        jsonPayload: jsonPayload.present ? jsonPayload.value : this.jsonPayload,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LocalSeal copyWithCompanion(LocalSealsCompanion data) {
    return LocalSeal(
      id: data.id.present ? data.id.value : this.id,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      floorId: data.floorId.present ? data.floorId.value : this.floorId,
      sealNumber:
          data.sealNumber.present ? data.sealNumber.value : this.sealNumber,
      system: data.system.present ? data.system.value : this.system,
      construction: data.construction.present
          ? data.construction.value
          : this.construction,
      location: data.location.present ? data.location.value : this.location,
      fireRating:
          data.fireRating.present ? data.fireRating.value : this.fireRating,
      note: data.note.present ? data.note.value : this.note,
      status: data.status.present ? data.status.value : this.status,
      version: data.version.present ? data.version.value : this.version,
      syncConflict: data.syncConflict.present
          ? data.syncConflict.value
          : this.syncConflict,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      jsonPayload:
          data.jsonPayload.present ? data.jsonPayload.value : this.jsonPayload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSeal(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('floorId: $floorId, ')
          ..write('sealNumber: $sealNumber, ')
          ..write('system: $system, ')
          ..write('construction: $construction, ')
          ..write('location: $location, ')
          ..write('fireRating: $fireRating, ')
          ..write('note: $note, ')
          ..write('status: $status, ')
          ..write('version: $version, ')
          ..write('syncConflict: $syncConflict, ')
          ..write('isSynced: $isSynced, ')
          ..write('jsonPayload: $jsonPayload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      jobId,
      floorId,
      sealNumber,
      system,
      construction,
      location,
      fireRating,
      note,
      status,
      version,
      syncConflict,
      isSynced,
      jsonPayload,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSeal &&
          other.id == this.id &&
          other.jobId == this.jobId &&
          other.floorId == this.floorId &&
          other.sealNumber == this.sealNumber &&
          other.system == this.system &&
          other.construction == this.construction &&
          other.location == this.location &&
          other.fireRating == this.fireRating &&
          other.note == this.note &&
          other.status == this.status &&
          other.version == this.version &&
          other.syncConflict == this.syncConflict &&
          other.isSynced == this.isSynced &&
          other.jsonPayload == this.jsonPayload &&
          other.updatedAt == this.updatedAt);
}

class LocalSealsCompanion extends UpdateCompanion<LocalSeal> {
  final Value<String> id;
  final Value<String> jobId;
  final Value<String> floorId;
  final Value<String> sealNumber;
  final Value<String> system;
  final Value<String> construction;
  final Value<String> location;
  final Value<String> fireRating;
  final Value<String?> note;
  final Value<String> status;
  final Value<int> version;
  final Value<bool> syncConflict;
  final Value<bool> isSynced;
  final Value<String?> jsonPayload;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalSealsCompanion({
    this.id = const Value.absent(),
    this.jobId = const Value.absent(),
    this.floorId = const Value.absent(),
    this.sealNumber = const Value.absent(),
    this.system = const Value.absent(),
    this.construction = const Value.absent(),
    this.location = const Value.absent(),
    this.fireRating = const Value.absent(),
    this.note = const Value.absent(),
    this.status = const Value.absent(),
    this.version = const Value.absent(),
    this.syncConflict = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.jsonPayload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSealsCompanion.insert({
    required String id,
    required String jobId,
    required String floorId,
    required String sealNumber,
    required String system,
    required String construction,
    required String location,
    required String fireRating,
    this.note = const Value.absent(),
    this.status = const Value.absent(),
    this.version = const Value.absent(),
    this.syncConflict = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.jsonPayload = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        jobId = Value(jobId),
        floorId = Value(floorId),
        sealNumber = Value(sealNumber),
        system = Value(system),
        construction = Value(construction),
        location = Value(location),
        fireRating = Value(fireRating),
        updatedAt = Value(updatedAt);
  static Insertable<LocalSeal> custom({
    Expression<String>? id,
    Expression<String>? jobId,
    Expression<String>? floorId,
    Expression<String>? sealNumber,
    Expression<String>? system,
    Expression<String>? construction,
    Expression<String>? location,
    Expression<String>? fireRating,
    Expression<String>? note,
    Expression<String>? status,
    Expression<int>? version,
    Expression<bool>? syncConflict,
    Expression<bool>? isSynced,
    Expression<String>? jsonPayload,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jobId != null) 'job_id': jobId,
      if (floorId != null) 'floor_id': floorId,
      if (sealNumber != null) 'seal_number': sealNumber,
      if (system != null) 'system': system,
      if (construction != null) 'construction': construction,
      if (location != null) 'location': location,
      if (fireRating != null) 'fire_rating': fireRating,
      if (note != null) 'note': note,
      if (status != null) 'status': status,
      if (version != null) 'version': version,
      if (syncConflict != null) 'sync_conflict': syncConflict,
      if (isSynced != null) 'is_synced': isSynced,
      if (jsonPayload != null) 'json_payload': jsonPayload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSealsCompanion copyWith(
      {Value<String>? id,
      Value<String>? jobId,
      Value<String>? floorId,
      Value<String>? sealNumber,
      Value<String>? system,
      Value<String>? construction,
      Value<String>? location,
      Value<String>? fireRating,
      Value<String?>? note,
      Value<String>? status,
      Value<int>? version,
      Value<bool>? syncConflict,
      Value<bool>? isSynced,
      Value<String?>? jsonPayload,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LocalSealsCompanion(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      floorId: floorId ?? this.floorId,
      sealNumber: sealNumber ?? this.sealNumber,
      system: system ?? this.system,
      construction: construction ?? this.construction,
      location: location ?? this.location,
      fireRating: fireRating ?? this.fireRating,
      note: note ?? this.note,
      status: status ?? this.status,
      version: version ?? this.version,
      syncConflict: syncConflict ?? this.syncConflict,
      isSynced: isSynced ?? this.isSynced,
      jsonPayload: jsonPayload ?? this.jsonPayload,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (floorId.present) {
      map['floor_id'] = Variable<String>(floorId.value);
    }
    if (sealNumber.present) {
      map['seal_number'] = Variable<String>(sealNumber.value);
    }
    if (system.present) {
      map['system'] = Variable<String>(system.value);
    }
    if (construction.present) {
      map['construction'] = Variable<String>(construction.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (fireRating.present) {
      map['fire_rating'] = Variable<String>(fireRating.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncConflict.present) {
      map['sync_conflict'] = Variable<bool>(syncConflict.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (jsonPayload.present) {
      map['json_payload'] = Variable<String>(jsonPayload.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSealsCompanion(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('floorId: $floorId, ')
          ..write('sealNumber: $sealNumber, ')
          ..write('system: $system, ')
          ..write('construction: $construction, ')
          ..write('location: $location, ')
          ..write('fireRating: $fireRating, ')
          ..write('note: $note, ')
          ..write('status: $status, ')
          ..write('version: $version, ')
          ..write('syncConflict: $syncConflict, ')
          ..write('isSynced: $isSynced, ')
          ..write('jsonPayload: $jsonPayload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalOutboxTable extends LocalOutbox
    with TableInfo<$LocalOutboxTable, LocalOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mutationIdMeta =
      const VerificationMeta('mutationId');
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
      'mutation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationMeta =
      const VerificationMeta('operation');
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
      'operation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _baseVersionMeta =
      const VerificationMeta('baseVersion');
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
      'base_version', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _nextRetryAtMeta =
      const VerificationMeta('nextRetryAt');
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
      'next_retry_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        mutationId,
        deviceId,
        entityType,
        operation,
        payload,
        baseVersion,
        status,
        createdAt,
        nextRetryAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_outbox';
  @override
  VerificationContext validateIntegrity(Insertable<LocalOutboxData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('mutation_id')) {
      context.handle(
          _mutationIdMeta,
          mutationId.isAcceptableOrUnknown(
              data['mutation_id']!, _mutationIdMeta));
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(_operationMeta,
          operation.isAcceptableOrUnknown(data['operation']!, _operationMeta));
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
          _baseVersionMeta,
          baseVersion.isAcceptableOrUnknown(
              data['base_version']!, _baseVersionMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
          _nextRetryAtMeta,
          nextRetryAt.isAcceptableOrUnknown(
              data['next_retry_at']!, _nextRetryAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalOutboxData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      mutationId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mutation_id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      operation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      baseVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_version']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      nextRetryAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}next_retry_at']),
    );
  }

  @override
  $LocalOutboxTable createAlias(String alias) {
    return $LocalOutboxTable(attachedDatabase, alias);
  }
}

class LocalOutboxData extends DataClass implements Insertable<LocalOutboxData> {
  final String id;
  final String mutationId;
  final String deviceId;
  final String entityType;
  final String operation;
  final String payload;
  final int? baseVersion;
  final String status;
  final DateTime createdAt;
  final DateTime? nextRetryAt;
  const LocalOutboxData(
      {required this.id,
      required this.mutationId,
      required this.deviceId,
      required this.entityType,
      required this.operation,
      required this.payload,
      this.baseVersion,
      required this.status,
      required this.createdAt,
      this.nextRetryAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['mutation_id'] = Variable<String>(mutationId);
    map['device_id'] = Variable<String>(deviceId);
    map['entity_type'] = Variable<String>(entityType);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || baseVersion != null) {
      map['base_version'] = Variable<int>(baseVersion);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    return map;
  }

  LocalOutboxCompanion toCompanion(bool nullToAbsent) {
    return LocalOutboxCompanion(
      id: Value(id),
      mutationId: Value(mutationId),
      deviceId: Value(deviceId),
      entityType: Value(entityType),
      operation: Value(operation),
      payload: Value(payload),
      baseVersion: baseVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(baseVersion),
      status: Value(status),
      createdAt: Value(createdAt),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
    );
  }

  factory LocalOutboxData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalOutboxData(
      id: serializer.fromJson<String>(json['id']),
      mutationId: serializer.fromJson<String>(json['mutationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      baseVersion: serializer.fromJson<int?>(json['baseVersion']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mutationId': serializer.toJson<String>(mutationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'entityType': serializer.toJson<String>(entityType),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'baseVersion': serializer.toJson<int?>(baseVersion),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
    };
  }

  LocalOutboxData copyWith(
          {String? id,
          String? mutationId,
          String? deviceId,
          String? entityType,
          String? operation,
          String? payload,
          Value<int?> baseVersion = const Value.absent(),
          String? status,
          DateTime? createdAt,
          Value<DateTime?> nextRetryAt = const Value.absent()}) =>
      LocalOutboxData(
        id: id ?? this.id,
        mutationId: mutationId ?? this.mutationId,
        deviceId: deviceId ?? this.deviceId,
        entityType: entityType ?? this.entityType,
        operation: operation ?? this.operation,
        payload: payload ?? this.payload,
        baseVersion: baseVersion.present ? baseVersion.value : this.baseVersion,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
      );
  LocalOutboxData copyWithCompanion(LocalOutboxCompanion data) {
    return LocalOutboxData(
      id: data.id.present ? data.id.value : this.id,
      mutationId:
          data.mutationId.present ? data.mutationId.value : this.mutationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      baseVersion:
          data.baseVersion.present ? data.baseVersion.value : this.baseVersion,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      nextRetryAt:
          data.nextRetryAt.present ? data.nextRetryAt.value : this.nextRetryAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalOutboxData(')
          ..write('id: $id, ')
          ..write('mutationId: $mutationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('entityType: $entityType, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('nextRetryAt: $nextRetryAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mutationId, deviceId, entityType,
      operation, payload, baseVersion, status, createdAt, nextRetryAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalOutboxData &&
          other.id == this.id &&
          other.mutationId == this.mutationId &&
          other.deviceId == this.deviceId &&
          other.entityType == this.entityType &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.baseVersion == this.baseVersion &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.nextRetryAt == this.nextRetryAt);
}

class LocalOutboxCompanion extends UpdateCompanion<LocalOutboxData> {
  final Value<String> id;
  final Value<String> mutationId;
  final Value<String> deviceId;
  final Value<String> entityType;
  final Value<String> operation;
  final Value<String> payload;
  final Value<int?> baseVersion;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime?> nextRetryAt;
  final Value<int> rowid;
  const LocalOutboxCompanion({
    this.id = const Value.absent(),
    this.mutationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalOutboxCompanion.insert({
    required String id,
    required String mutationId,
    required String deviceId,
    required String entityType,
    required String operation,
    required String payload,
    this.baseVersion = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    this.nextRetryAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        mutationId = Value(mutationId),
        deviceId = Value(deviceId),
        entityType = Value(entityType),
        operation = Value(operation),
        payload = Value(payload),
        createdAt = Value(createdAt);
  static Insertable<LocalOutboxData> custom({
    Expression<String>? id,
    Expression<String>? mutationId,
    Expression<String>? deviceId,
    Expression<String>? entityType,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<int>? baseVersion,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? nextRetryAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mutationId != null) 'mutation_id': mutationId,
      if (deviceId != null) 'device_id': deviceId,
      if (entityType != null) 'entity_type': entityType,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (baseVersion != null) 'base_version': baseVersion,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalOutboxCompanion copyWith(
      {Value<String>? id,
      Value<String>? mutationId,
      Value<String>? deviceId,
      Value<String>? entityType,
      Value<String>? operation,
      Value<String>? payload,
      Value<int?>? baseVersion,
      Value<String>? status,
      Value<DateTime>? createdAt,
      Value<DateTime?>? nextRetryAt,
      Value<int>? rowid}) {
    return LocalOutboxCompanion(
      id: id ?? this.id,
      mutationId: mutationId ?? this.mutationId,
      deviceId: deviceId ?? this.deviceId,
      entityType: entityType ?? this.entityType,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      baseVersion: baseVersion ?? this.baseVersion,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalOutboxCompanion(')
          ..write('id: $id, ')
          ..write('mutationId: $mutationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('entityType: $entityType, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalPhotosTable extends LocalPhotos
    with TableInfo<$LocalPhotosTable, LocalPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sealIdMeta = const VerificationMeta('sealId');
  @override
  late final GeneratedColumn<String> sealId = GeneratedColumn<String>(
      'seal_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localPathMeta =
      const VerificationMeta('localPath');
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
      'local_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _serverPathMeta =
      const VerificationMeta('serverPath');
  @override
  late final GeneratedColumn<String> serverPath = GeneratedColumn<String>(
      'server_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sealId, localPath, serverPath, status, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_photos';
  @override
  VerificationContext validateIntegrity(Insertable<LocalPhoto> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('seal_id')) {
      context.handle(_sealIdMeta,
          sealId.isAcceptableOrUnknown(data['seal_id']!, _sealIdMeta));
    } else if (isInserting) {
      context.missing(_sealIdMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(_localPathMeta,
          localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta));
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('server_path')) {
      context.handle(
          _serverPathMeta,
          serverPath.isAcceptableOrUnknown(
              data['server_path']!, _serverPathMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPhoto(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      sealId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}seal_id'])!,
      localPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_path'])!,
      serverPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_path']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $LocalPhotosTable createAlias(String alias) {
    return $LocalPhotosTable(attachedDatabase, alias);
  }
}

class LocalPhoto extends DataClass implements Insertable<LocalPhoto> {
  final String id;
  final String sealId;
  final String localPath;
  final String? serverPath;
  final String status;
  final DateTime createdAt;
  const LocalPhoto(
      {required this.id,
      required this.sealId,
      required this.localPath,
      this.serverPath,
      required this.status,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['seal_id'] = Variable<String>(sealId);
    map['local_path'] = Variable<String>(localPath);
    if (!nullToAbsent || serverPath != null) {
      map['server_path'] = Variable<String>(serverPath);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LocalPhotosCompanion toCompanion(bool nullToAbsent) {
    return LocalPhotosCompanion(
      id: Value(id),
      sealId: Value(sealId),
      localPath: Value(localPath),
      serverPath: serverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(serverPath),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory LocalPhoto.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPhoto(
      id: serializer.fromJson<String>(json['id']),
      sealId: serializer.fromJson<String>(json['sealId']),
      localPath: serializer.fromJson<String>(json['localPath']),
      serverPath: serializer.fromJson<String?>(json['serverPath']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sealId': serializer.toJson<String>(sealId),
      'localPath': serializer.toJson<String>(localPath),
      'serverPath': serializer.toJson<String?>(serverPath),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LocalPhoto copyWith(
          {String? id,
          String? sealId,
          String? localPath,
          Value<String?> serverPath = const Value.absent(),
          String? status,
          DateTime? createdAt}) =>
      LocalPhoto(
        id: id ?? this.id,
        sealId: sealId ?? this.sealId,
        localPath: localPath ?? this.localPath,
        serverPath: serverPath.present ? serverPath.value : this.serverPath,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
  LocalPhoto copyWithCompanion(LocalPhotosCompanion data) {
    return LocalPhoto(
      id: data.id.present ? data.id.value : this.id,
      sealId: data.sealId.present ? data.sealId.value : this.sealId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      serverPath:
          data.serverPath.present ? data.serverPath.value : this.serverPath,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPhoto(')
          ..write('id: $id, ')
          ..write('sealId: $sealId, ')
          ..write('localPath: $localPath, ')
          ..write('serverPath: $serverPath, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sealId, localPath, serverPath, status, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPhoto &&
          other.id == this.id &&
          other.sealId == this.sealId &&
          other.localPath == this.localPath &&
          other.serverPath == this.serverPath &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class LocalPhotosCompanion extends UpdateCompanion<LocalPhoto> {
  final Value<String> id;
  final Value<String> sealId;
  final Value<String> localPath;
  final Value<String?> serverPath;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalPhotosCompanion({
    this.id = const Value.absent(),
    this.sealId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.serverPath = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPhotosCompanion.insert({
    required String id,
    required String sealId,
    required String localPath,
    this.serverPath = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        sealId = Value(sealId),
        localPath = Value(localPath),
        createdAt = Value(createdAt);
  static Insertable<LocalPhoto> custom({
    Expression<String>? id,
    Expression<String>? sealId,
    Expression<String>? localPath,
    Expression<String>? serverPath,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sealId != null) 'seal_id': sealId,
      if (localPath != null) 'local_path': localPath,
      if (serverPath != null) 'server_path': serverPath,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPhotosCompanion copyWith(
      {Value<String>? id,
      Value<String>? sealId,
      Value<String>? localPath,
      Value<String?>? serverPath,
      Value<String>? status,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return LocalPhotosCompanion(
      id: id ?? this.id,
      sealId: sealId ?? this.sealId,
      localPath: localPath ?? this.localPath,
      serverPath: serverPath ?? this.serverPath,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sealId.present) {
      map['seal_id'] = Variable<String>(sealId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (serverPath.present) {
      map['server_path'] = Variable<String>(serverPath.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPhotosCompanion(')
          ..write('id: $id, ')
          ..write('sealId: $sealId, ')
          ..write('localPath: $localPath, ')
          ..write('serverPath: $serverPath, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorTable extends SyncCursor
    with TableInfo<$SyncCursorTable, SyncCursorData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastPullMeta =
      const VerificationMeta('lastPull');
  @override
  late final GeneratedColumn<DateTime> lastPull = GeneratedColumn<DateTime>(
      'last_pull', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, lastPull];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursor';
  @override
  VerificationContext validateIntegrity(Insertable<SyncCursorData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('last_pull')) {
      context.handle(_lastPullMeta,
          lastPull.isAcceptableOrUnknown(data['last_pull']!, _lastPullMeta));
    } else if (isInserting) {
      context.missing(_lastPullMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncCursorData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursorData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      lastPull: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_pull'])!,
    );
  }

  @override
  $SyncCursorTable createAlias(String alias) {
    return $SyncCursorTable(attachedDatabase, alias);
  }
}

class SyncCursorData extends DataClass implements Insertable<SyncCursorData> {
  final String key;
  final DateTime lastPull;
  const SyncCursorData({required this.key, required this.lastPull});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['last_pull'] = Variable<DateTime>(lastPull);
    return map;
  }

  SyncCursorCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorCompanion(
      key: Value(key),
      lastPull: Value(lastPull),
    );
  }

  factory SyncCursorData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursorData(
      key: serializer.fromJson<String>(json['key']),
      lastPull: serializer.fromJson<DateTime>(json['lastPull']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'lastPull': serializer.toJson<DateTime>(lastPull),
    };
  }

  SyncCursorData copyWith({String? key, DateTime? lastPull}) => SyncCursorData(
        key: key ?? this.key,
        lastPull: lastPull ?? this.lastPull,
      );
  SyncCursorData copyWithCompanion(SyncCursorCompanion data) {
    return SyncCursorData(
      key: data.key.present ? data.key.value : this.key,
      lastPull: data.lastPull.present ? data.lastPull.value : this.lastPull,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorData(')
          ..write('key: $key, ')
          ..write('lastPull: $lastPull')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, lastPull);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursorData &&
          other.key == this.key &&
          other.lastPull == this.lastPull);
}

class SyncCursorCompanion extends UpdateCompanion<SyncCursorData> {
  final Value<String> key;
  final Value<DateTime> lastPull;
  final Value<int> rowid;
  const SyncCursorCompanion({
    this.key = const Value.absent(),
    this.lastPull = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorCompanion.insert({
    required String key,
    required DateTime lastPull,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        lastPull = Value(lastPull);
  static Insertable<SyncCursorData> custom({
    Expression<String>? key,
    Expression<DateTime>? lastPull,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (lastPull != null) 'last_pull': lastPull,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorCompanion copyWith(
      {Value<String>? key, Value<DateTime>? lastPull, Value<int>? rowid}) {
    return SyncCursorCompanion(
      key: key ?? this.key,
      lastPull: lastPull ?? this.lastPull,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (lastPull.present) {
      map['last_pull'] = Variable<DateTime>(lastPull.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorCompanion(')
          ..write('key: $key, ')
          ..write('lastPull: $lastPull, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalJobsTable localJobs = $LocalJobsTable(this);
  late final $LocalFloorsTable localFloors = $LocalFloorsTable(this);
  late final $LocalSealsTable localSeals = $LocalSealsTable(this);
  late final $LocalOutboxTable localOutbox = $LocalOutboxTable(this);
  late final $LocalPhotosTable localPhotos = $LocalPhotosTable(this);
  late final $SyncCursorTable syncCursor = $SyncCursorTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        localJobs,
        localFloors,
        localSeals,
        localOutbox,
        localPhotos,
        syncCursor
      ];
}

typedef $$LocalJobsTableCreateCompanionBuilder = LocalJobsCompanion Function({
  required String id,
  required String projectNumber,
  required String name,
  Value<String?> address,
  Value<bool> isArchived,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$LocalJobsTableUpdateCompanionBuilder = LocalJobsCompanion Function({
  Value<String> id,
  Value<String> projectNumber,
  Value<String> name,
  Value<String?> address,
  Value<bool> isArchived,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$LocalJobsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalJobsTable> {
  $$LocalJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get projectNumber => $composableBuilder(
      column: $table.projectNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalJobsTable> {
  $$LocalJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get projectNumber => $composableBuilder(
      column: $table.projectNumber,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalJobsTable> {
  $$LocalJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get projectNumber => $composableBuilder(
      column: $table.projectNumber, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalJobsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalJobsTable,
    LocalJob,
    $$LocalJobsTableFilterComposer,
    $$LocalJobsTableOrderingComposer,
    $$LocalJobsTableAnnotationComposer,
    $$LocalJobsTableCreateCompanionBuilder,
    $$LocalJobsTableUpdateCompanionBuilder,
    (LocalJob, BaseReferences<_$AppDatabase, $LocalJobsTable, LocalJob>),
    LocalJob,
    PrefetchHooks Function()> {
  $$LocalJobsTableTableManager(_$AppDatabase db, $LocalJobsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> projectNumber = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> address = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalJobsCompanion(
            id: id,
            projectNumber: projectNumber,
            name: name,
            address: address,
            isArchived: isArchived,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String projectNumber,
            required String name,
            Value<String?> address = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalJobsCompanion.insert(
            id: id,
            projectNumber: projectNumber,
            name: name,
            address: address,
            isArchived: isArchived,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalJobsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalJobsTable,
    LocalJob,
    $$LocalJobsTableFilterComposer,
    $$LocalJobsTableOrderingComposer,
    $$LocalJobsTableAnnotationComposer,
    $$LocalJobsTableCreateCompanionBuilder,
    $$LocalJobsTableUpdateCompanionBuilder,
    (LocalJob, BaseReferences<_$AppDatabase, $LocalJobsTable, LocalJob>),
    LocalJob,
    PrefetchHooks Function()>;
typedef $$LocalFloorsTableCreateCompanionBuilder = LocalFloorsCompanion
    Function({
  required String id,
  required String jobId,
  required String name,
  Value<int> sortOrder,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$LocalFloorsTableUpdateCompanionBuilder = LocalFloorsCompanion
    Function({
  Value<String> id,
  Value<String> jobId,
  Value<String> name,
  Value<int> sortOrder,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$LocalFloorsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalFloorsTable> {
  $$LocalFloorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jobId => $composableBuilder(
      column: $table.jobId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalFloorsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalFloorsTable> {
  $$LocalFloorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jobId => $composableBuilder(
      column: $table.jobId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalFloorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalFloorsTable> {
  $$LocalFloorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalFloorsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalFloorsTable,
    LocalFloor,
    $$LocalFloorsTableFilterComposer,
    $$LocalFloorsTableOrderingComposer,
    $$LocalFloorsTableAnnotationComposer,
    $$LocalFloorsTableCreateCompanionBuilder,
    $$LocalFloorsTableUpdateCompanionBuilder,
    (LocalFloor, BaseReferences<_$AppDatabase, $LocalFloorsTable, LocalFloor>),
    LocalFloor,
    PrefetchHooks Function()> {
  $$LocalFloorsTableTableManager(_$AppDatabase db, $LocalFloorsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFloorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFloorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalFloorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> jobId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalFloorsCompanion(
            id: id,
            jobId: jobId,
            name: name,
            sortOrder: sortOrder,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String jobId,
            required String name,
            Value<int> sortOrder = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalFloorsCompanion.insert(
            id: id,
            jobId: jobId,
            name: name,
            sortOrder: sortOrder,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalFloorsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalFloorsTable,
    LocalFloor,
    $$LocalFloorsTableFilterComposer,
    $$LocalFloorsTableOrderingComposer,
    $$LocalFloorsTableAnnotationComposer,
    $$LocalFloorsTableCreateCompanionBuilder,
    $$LocalFloorsTableUpdateCompanionBuilder,
    (LocalFloor, BaseReferences<_$AppDatabase, $LocalFloorsTable, LocalFloor>),
    LocalFloor,
    PrefetchHooks Function()>;
typedef $$LocalSealsTableCreateCompanionBuilder = LocalSealsCompanion Function({
  required String id,
  required String jobId,
  required String floorId,
  required String sealNumber,
  required String system,
  required String construction,
  required String location,
  required String fireRating,
  Value<String?> note,
  Value<String> status,
  Value<int> version,
  Value<bool> syncConflict,
  Value<bool> isSynced,
  Value<String?> jsonPayload,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$LocalSealsTableUpdateCompanionBuilder = LocalSealsCompanion Function({
  Value<String> id,
  Value<String> jobId,
  Value<String> floorId,
  Value<String> sealNumber,
  Value<String> system,
  Value<String> construction,
  Value<String> location,
  Value<String> fireRating,
  Value<String?> note,
  Value<String> status,
  Value<int> version,
  Value<bool> syncConflict,
  Value<bool> isSynced,
  Value<String?> jsonPayload,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$LocalSealsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSealsTable> {
  $$LocalSealsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jobId => $composableBuilder(
      column: $table.jobId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get floorId => $composableBuilder(
      column: $table.floorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sealNumber => $composableBuilder(
      column: $table.sealNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get system => $composableBuilder(
      column: $table.system, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get construction => $composableBuilder(
      column: $table.construction, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get location => $composableBuilder(
      column: $table.location, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fireRating => $composableBuilder(
      column: $table.fireRating, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get syncConflict => $composableBuilder(
      column: $table.syncConflict, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jsonPayload => $composableBuilder(
      column: $table.jsonPayload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalSealsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSealsTable> {
  $$LocalSealsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jobId => $composableBuilder(
      column: $table.jobId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get floorId => $composableBuilder(
      column: $table.floorId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sealNumber => $composableBuilder(
      column: $table.sealNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get system => $composableBuilder(
      column: $table.system, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get construction => $composableBuilder(
      column: $table.construction,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get location => $composableBuilder(
      column: $table.location, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fireRating => $composableBuilder(
      column: $table.fireRating, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get syncConflict => $composableBuilder(
      column: $table.syncConflict,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jsonPayload => $composableBuilder(
      column: $table.jsonPayload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalSealsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSealsTable> {
  $$LocalSealsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get floorId =>
      $composableBuilder(column: $table.floorId, builder: (column) => column);

  GeneratedColumn<String> get sealNumber => $composableBuilder(
      column: $table.sealNumber, builder: (column) => column);

  GeneratedColumn<String> get system =>
      $composableBuilder(column: $table.system, builder: (column) => column);

  GeneratedColumn<String> get construction => $composableBuilder(
      column: $table.construction, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get fireRating => $composableBuilder(
      column: $table.fireRating, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get syncConflict => $composableBuilder(
      column: $table.syncConflict, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<String> get jsonPayload => $composableBuilder(
      column: $table.jsonPayload, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalSealsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalSealsTable,
    LocalSeal,
    $$LocalSealsTableFilterComposer,
    $$LocalSealsTableOrderingComposer,
    $$LocalSealsTableAnnotationComposer,
    $$LocalSealsTableCreateCompanionBuilder,
    $$LocalSealsTableUpdateCompanionBuilder,
    (LocalSeal, BaseReferences<_$AppDatabase, $LocalSealsTable, LocalSeal>),
    LocalSeal,
    PrefetchHooks Function()> {
  $$LocalSealsTableTableManager(_$AppDatabase db, $LocalSealsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSealsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSealsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSealsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> jobId = const Value.absent(),
            Value<String> floorId = const Value.absent(),
            Value<String> sealNumber = const Value.absent(),
            Value<String> system = const Value.absent(),
            Value<String> construction = const Value.absent(),
            Value<String> location = const Value.absent(),
            Value<String> fireRating = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<bool> syncConflict = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            Value<String?> jsonPayload = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSealsCompanion(
            id: id,
            jobId: jobId,
            floorId: floorId,
            sealNumber: sealNumber,
            system: system,
            construction: construction,
            location: location,
            fireRating: fireRating,
            note: note,
            status: status,
            version: version,
            syncConflict: syncConflict,
            isSynced: isSynced,
            jsonPayload: jsonPayload,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String jobId,
            required String floorId,
            required String sealNumber,
            required String system,
            required String construction,
            required String location,
            required String fireRating,
            Value<String?> note = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<bool> syncConflict = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            Value<String?> jsonPayload = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSealsCompanion.insert(
            id: id,
            jobId: jobId,
            floorId: floorId,
            sealNumber: sealNumber,
            system: system,
            construction: construction,
            location: location,
            fireRating: fireRating,
            note: note,
            status: status,
            version: version,
            syncConflict: syncConflict,
            isSynced: isSynced,
            jsonPayload: jsonPayload,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalSealsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalSealsTable,
    LocalSeal,
    $$LocalSealsTableFilterComposer,
    $$LocalSealsTableOrderingComposer,
    $$LocalSealsTableAnnotationComposer,
    $$LocalSealsTableCreateCompanionBuilder,
    $$LocalSealsTableUpdateCompanionBuilder,
    (LocalSeal, BaseReferences<_$AppDatabase, $LocalSealsTable, LocalSeal>),
    LocalSeal,
    PrefetchHooks Function()>;
typedef $$LocalOutboxTableCreateCompanionBuilder = LocalOutboxCompanion
    Function({
  required String id,
  required String mutationId,
  required String deviceId,
  required String entityType,
  required String operation,
  required String payload,
  Value<int?> baseVersion,
  Value<String> status,
  required DateTime createdAt,
  Value<DateTime?> nextRetryAt,
  Value<int> rowid,
});
typedef $$LocalOutboxTableUpdateCompanionBuilder = LocalOutboxCompanion
    Function({
  Value<String> id,
  Value<String> mutationId,
  Value<String> deviceId,
  Value<String> entityType,
  Value<String> operation,
  Value<String> payload,
  Value<int?> baseVersion,
  Value<String> status,
  Value<DateTime> createdAt,
  Value<DateTime?> nextRetryAt,
  Value<int> rowid,
});

class $$LocalOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mutationId => $composableBuilder(
      column: $table.mutationId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => ColumnFilters(column));
}

class $$LocalOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mutationId => $composableBuilder(
      column: $table.mutationId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mutationId => $composableBuilder(
      column: $table.mutationId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => column);
}

class $$LocalOutboxTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalOutboxTable,
    LocalOutboxData,
    $$LocalOutboxTableFilterComposer,
    $$LocalOutboxTableOrderingComposer,
    $$LocalOutboxTableAnnotationComposer,
    $$LocalOutboxTableCreateCompanionBuilder,
    $$LocalOutboxTableUpdateCompanionBuilder,
    (
      LocalOutboxData,
      BaseReferences<_$AppDatabase, $LocalOutboxTable, LocalOutboxData>
    ),
    LocalOutboxData,
    PrefetchHooks Function()> {
  $$LocalOutboxTableTableManager(_$AppDatabase db, $LocalOutboxTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> mutationId = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<String> operation = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int?> baseVersion = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> nextRetryAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalOutboxCompanion(
            id: id,
            mutationId: mutationId,
            deviceId: deviceId,
            entityType: entityType,
            operation: operation,
            payload: payload,
            baseVersion: baseVersion,
            status: status,
            createdAt: createdAt,
            nextRetryAt: nextRetryAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String mutationId,
            required String deviceId,
            required String entityType,
            required String operation,
            required String payload,
            Value<int?> baseVersion = const Value.absent(),
            Value<String> status = const Value.absent(),
            required DateTime createdAt,
            Value<DateTime?> nextRetryAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalOutboxCompanion.insert(
            id: id,
            mutationId: mutationId,
            deviceId: deviceId,
            entityType: entityType,
            operation: operation,
            payload: payload,
            baseVersion: baseVersion,
            status: status,
            createdAt: createdAt,
            nextRetryAt: nextRetryAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalOutboxTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalOutboxTable,
    LocalOutboxData,
    $$LocalOutboxTableFilterComposer,
    $$LocalOutboxTableOrderingComposer,
    $$LocalOutboxTableAnnotationComposer,
    $$LocalOutboxTableCreateCompanionBuilder,
    $$LocalOutboxTableUpdateCompanionBuilder,
    (
      LocalOutboxData,
      BaseReferences<_$AppDatabase, $LocalOutboxTable, LocalOutboxData>
    ),
    LocalOutboxData,
    PrefetchHooks Function()>;
typedef $$LocalPhotosTableCreateCompanionBuilder = LocalPhotosCompanion
    Function({
  required String id,
  required String sealId,
  required String localPath,
  Value<String?> serverPath,
  Value<String> status,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$LocalPhotosTableUpdateCompanionBuilder = LocalPhotosCompanion
    Function({
  Value<String> id,
  Value<String> sealId,
  Value<String> localPath,
  Value<String?> serverPath,
  Value<String> status,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$LocalPhotosTableFilterComposer
    extends Composer<_$AppDatabase, $LocalPhotosTable> {
  $$LocalPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sealId => $composableBuilder(
      column: $table.sealId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverPath => $composableBuilder(
      column: $table.serverPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$LocalPhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalPhotosTable> {
  $$LocalPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sealId => $composableBuilder(
      column: $table.sealId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverPath => $composableBuilder(
      column: $table.serverPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalPhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalPhotosTable> {
  $$LocalPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sealId =>
      $composableBuilder(column: $table.sealId, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get serverPath => $composableBuilder(
      column: $table.serverPath, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LocalPhotosTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalPhotosTable,
    LocalPhoto,
    $$LocalPhotosTableFilterComposer,
    $$LocalPhotosTableOrderingComposer,
    $$LocalPhotosTableAnnotationComposer,
    $$LocalPhotosTableCreateCompanionBuilder,
    $$LocalPhotosTableUpdateCompanionBuilder,
    (LocalPhoto, BaseReferences<_$AppDatabase, $LocalPhotosTable, LocalPhoto>),
    LocalPhoto,
    PrefetchHooks Function()> {
  $$LocalPhotosTableTableManager(_$AppDatabase db, $LocalPhotosTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> sealId = const Value.absent(),
            Value<String> localPath = const Value.absent(),
            Value<String?> serverPath = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalPhotosCompanion(
            id: id,
            sealId: sealId,
            localPath: localPath,
            serverPath: serverPath,
            status: status,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String sealId,
            required String localPath,
            Value<String?> serverPath = const Value.absent(),
            Value<String> status = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalPhotosCompanion.insert(
            id: id,
            sealId: sealId,
            localPath: localPath,
            serverPath: serverPath,
            status: status,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalPhotosTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalPhotosTable,
    LocalPhoto,
    $$LocalPhotosTableFilterComposer,
    $$LocalPhotosTableOrderingComposer,
    $$LocalPhotosTableAnnotationComposer,
    $$LocalPhotosTableCreateCompanionBuilder,
    $$LocalPhotosTableUpdateCompanionBuilder,
    (LocalPhoto, BaseReferences<_$AppDatabase, $LocalPhotosTable, LocalPhoto>),
    LocalPhoto,
    PrefetchHooks Function()>;
typedef $$SyncCursorTableCreateCompanionBuilder = SyncCursorCompanion Function({
  required String key,
  required DateTime lastPull,
  Value<int> rowid,
});
typedef $$SyncCursorTableUpdateCompanionBuilder = SyncCursorCompanion Function({
  Value<String> key,
  Value<DateTime> lastPull,
  Value<int> rowid,
});

class $$SyncCursorTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorTable> {
  $$SyncCursorTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastPull => $composableBuilder(
      column: $table.lastPull, builder: (column) => ColumnFilters(column));
}

class $$SyncCursorTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorTable> {
  $$SyncCursorTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastPull => $composableBuilder(
      column: $table.lastPull, builder: (column) => ColumnOrderings(column));
}

class $$SyncCursorTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorTable> {
  $$SyncCursorTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPull =>
      $composableBuilder(column: $table.lastPull, builder: (column) => column);
}

class $$SyncCursorTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncCursorTable,
    SyncCursorData,
    $$SyncCursorTableFilterComposer,
    $$SyncCursorTableOrderingComposer,
    $$SyncCursorTableAnnotationComposer,
    $$SyncCursorTableCreateCompanionBuilder,
    $$SyncCursorTableUpdateCompanionBuilder,
    (
      SyncCursorData,
      BaseReferences<_$AppDatabase, $SyncCursorTable, SyncCursorData>
    ),
    SyncCursorData,
    PrefetchHooks Function()> {
  $$SyncCursorTableTableManager(_$AppDatabase db, $SyncCursorTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<DateTime> lastPull = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncCursorCompanion(
            key: key,
            lastPull: lastPull,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required DateTime lastPull,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncCursorCompanion.insert(
            key: key,
            lastPull: lastPull,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncCursorTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncCursorTable,
    SyncCursorData,
    $$SyncCursorTableFilterComposer,
    $$SyncCursorTableOrderingComposer,
    $$SyncCursorTableAnnotationComposer,
    $$SyncCursorTableCreateCompanionBuilder,
    $$SyncCursorTableUpdateCompanionBuilder,
    (
      SyncCursorData,
      BaseReferences<_$AppDatabase, $SyncCursorTable, SyncCursorData>
    ),
    SyncCursorData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalJobsTableTableManager get localJobs =>
      $$LocalJobsTableTableManager(_db, _db.localJobs);
  $$LocalFloorsTableTableManager get localFloors =>
      $$LocalFloorsTableTableManager(_db, _db.localFloors);
  $$LocalSealsTableTableManager get localSeals =>
      $$LocalSealsTableTableManager(_db, _db.localSeals);
  $$LocalOutboxTableTableManager get localOutbox =>
      $$LocalOutboxTableTableManager(_db, _db.localOutbox);
  $$LocalPhotosTableTableManager get localPhotos =>
      $$LocalPhotosTableTableManager(_db, _db.localPhotos);
  $$SyncCursorTableTableManager get syncCursor =>
      $$SyncCursorTableTableManager(_db, _db.syncCursor);
}
