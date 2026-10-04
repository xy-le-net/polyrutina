// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $JournalTable extends Journal with TableInfo<$JournalTable, JournalData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<int> time = GeneratedColumn<int>(
      'time', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _flagsMeta = const VerificationMeta('flags');
  @override
  late final GeneratedColumn<int> flags = GeneratedColumn<int>(
      'flags', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
      'type', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
      'body', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, time, flags, type, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal';
  @override
  VerificationContext validateIntegrity(Insertable<JournalData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('time')) {
      context.handle(
          _timeMeta, time.isAcceptableOrUnknown(data['time']!, _timeMeta));
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('flags')) {
      context.handle(
          _flagsMeta, flags.isAcceptableOrUnknown(data['flags']!, _flagsMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
          _bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JournalData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      time: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}time'])!,
      flags: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}flags'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}type'])!,
      body: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}body'])!,
    );
  }

  @override
  $JournalTable createAlias(String alias) {
    return $JournalTable(attachedDatabase, alias);
  }
}

class JournalData extends DataClass implements Insertable<JournalData> {
  final int id;
  final int time;
  final int flags;
  final int type;
  final String body;
  const JournalData(
      {required this.id,
      required this.time,
      required this.flags,
      required this.type,
      required this.body});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['time'] = Variable<int>(time);
    map['flags'] = Variable<int>(flags);
    map['type'] = Variable<int>(type);
    map['body'] = Variable<String>(body);
    return map;
  }

  JournalCompanion toCompanion(bool nullToAbsent) {
    return JournalCompanion(
      id: Value(id),
      time: Value(time),
      flags: Value(flags),
      type: Value(type),
      body: Value(body),
    );
  }

  factory JournalData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalData(
      id: serializer.fromJson<int>(json['id']),
      time: serializer.fromJson<int>(json['time']),
      flags: serializer.fromJson<int>(json['flags']),
      type: serializer.fromJson<int>(json['type']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'time': serializer.toJson<int>(time),
      'flags': serializer.toJson<int>(flags),
      'type': serializer.toJson<int>(type),
      'body': serializer.toJson<String>(body),
    };
  }

  JournalData copyWith(
          {int? id, int? time, int? flags, int? type, String? body}) =>
      JournalData(
        id: id ?? this.id,
        time: time ?? this.time,
        flags: flags ?? this.flags,
        type: type ?? this.type,
        body: body ?? this.body,
      );
  JournalData copyWithCompanion(JournalCompanion data) {
    return JournalData(
      id: data.id.present ? data.id.value : this.id,
      time: data.time.present ? data.time.value : this.time,
      flags: data.flags.present ? data.flags.value : this.flags,
      type: data.type.present ? data.type.value : this.type,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalData(')
          ..write('id: $id, ')
          ..write('time: $time, ')
          ..write('flags: $flags, ')
          ..write('type: $type, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, time, flags, type, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalData &&
          other.id == this.id &&
          other.time == this.time &&
          other.flags == this.flags &&
          other.type == this.type &&
          other.body == this.body);
}

class JournalCompanion extends UpdateCompanion<JournalData> {
  final Value<int> id;
  final Value<int> time;
  final Value<int> flags;
  final Value<int> type;
  final Value<String> body;
  const JournalCompanion({
    this.id = const Value.absent(),
    this.time = const Value.absent(),
    this.flags = const Value.absent(),
    this.type = const Value.absent(),
    this.body = const Value.absent(),
  });
  JournalCompanion.insert({
    this.id = const Value.absent(),
    required int time,
    this.flags = const Value.absent(),
    required int type,
    required String body,
  })  : time = Value(time),
        type = Value(type),
        body = Value(body);
  static Insertable<JournalData> custom({
    Expression<int>? id,
    Expression<int>? time,
    Expression<int>? flags,
    Expression<int>? type,
    Expression<String>? body,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (time != null) 'time': time,
      if (flags != null) 'flags': flags,
      if (type != null) 'type': type,
      if (body != null) 'body': body,
    });
  }

  JournalCompanion copyWith(
      {Value<int>? id,
      Value<int>? time,
      Value<int>? flags,
      Value<int>? type,
      Value<String>? body}) {
    return JournalCompanion(
      id: id ?? this.id,
      time: time ?? this.time,
      flags: flags ?? this.flags,
      type: type ?? this.type,
      body: body ?? this.body,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (time.present) {
      map['time'] = Variable<int>(time.value);
    }
    if (flags.present) {
      map['flags'] = Variable<int>(flags.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalCompanion(')
          ..write('id: $id, ')
          ..write('time: $time, ')
          ..write('flags: $flags, ')
          ..write('type: $type, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $JournalTable journal = $JournalTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [journal];
}

typedef $$JournalTableCreateCompanionBuilder = JournalCompanion Function({
  Value<int> id,
  required int time,
  Value<int> flags,
  required int type,
  required String body,
});
typedef $$JournalTableUpdateCompanionBuilder = JournalCompanion Function({
  Value<int> id,
  Value<int> time,
  Value<int> flags,
  Value<int> type,
  Value<String> body,
});

class $$JournalTableFilterComposer extends Composer<_$AppDb, $JournalTable> {
  $$JournalTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get time => $composableBuilder(
      column: $table.time, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get flags => $composableBuilder(
      column: $table.flags, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnFilters(column));
}

class $$JournalTableOrderingComposer extends Composer<_$AppDb, $JournalTable> {
  $$JournalTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get time => $composableBuilder(
      column: $table.time, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get flags => $composableBuilder(
      column: $table.flags, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnOrderings(column));
}

class $$JournalTableAnnotationComposer
    extends Composer<_$AppDb, $JournalTable> {
  $$JournalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<int> get flags =>
      $composableBuilder(column: $table.flags, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$JournalTableTableManager extends RootTableManager<
    _$AppDb,
    $JournalTable,
    JournalData,
    $$JournalTableFilterComposer,
    $$JournalTableOrderingComposer,
    $$JournalTableAnnotationComposer,
    $$JournalTableCreateCompanionBuilder,
    $$JournalTableUpdateCompanionBuilder,
    (JournalData, BaseReferences<_$AppDb, $JournalTable, JournalData>),
    JournalData,
    PrefetchHooks Function()> {
  $$JournalTableTableManager(_$AppDb db, $JournalTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> time = const Value.absent(),
            Value<int> flags = const Value.absent(),
            Value<int> type = const Value.absent(),
            Value<String> body = const Value.absent(),
          }) =>
              JournalCompanion(
            id: id,
            time: time,
            flags: flags,
            type: type,
            body: body,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int time,
            Value<int> flags = const Value.absent(),
            required int type,
            required String body,
          }) =>
              JournalCompanion.insert(
            id: id,
            time: time,
            flags: flags,
            type: type,
            body: body,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$JournalTable, JournalData>(table),
                    BaseReferences<_$AppDb, $JournalTable, JournalData>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$JournalTableProcessedTableManager = ProcessedTableManager<
    _$AppDb,
    $JournalTable,
    JournalData,
    $$JournalTableFilterComposer,
    $$JournalTableOrderingComposer,
    $$JournalTableAnnotationComposer,
    $$JournalTableCreateCompanionBuilder,
    $$JournalTableUpdateCompanionBuilder,
    (JournalData, BaseReferences<_$AppDb, $JournalTable, JournalData>),
    JournalData,
    PrefetchHooks Function()>;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$JournalTableTableManager get journal =>
      $$JournalTableTableManager(_db, _db.journal);
}
