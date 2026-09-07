// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_database.dart';

// ignore_for_file: type=lint
class Bookshelf extends Table with TableInfo<Bookshelf, BookshelfData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Bookshelf(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _novelIdMeta = const VerificationMeta(
    'novelId',
  );
  late final GeneratedColumn<String> novelId = GeneratedColumn<String>(
    'novel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _summaryJsonMeta = const VerificationMeta(
    'summaryJson',
  );
  late final GeneratedColumn<String> summaryJson = GeneratedColumn<String>(
    'summary_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    novelId,
    summaryJson,
    addedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookshelf';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookshelfData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('novel_id')) {
      context.handle(
        _novelIdMeta,
        novelId.isAcceptableOrUnknown(data['novel_id']!, _novelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_novelIdMeta);
    }
    if (data.containsKey('summary_json')) {
      context.handle(
        _summaryJsonMeta,
        summaryJson.isAcceptableOrUnknown(
          data['summary_json']!,
          _summaryJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryJsonMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, novelId};
  @override
  BookshelfData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookshelfData(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      novelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}novel_id'],
      )!,
      summaryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_json'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  Bookshelf createAlias(String alias) {
    return Bookshelf(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(source_id, novel_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class BookshelfData extends DataClass implements Insertable<BookshelfData> {
  final String sourceId;
  final String novelId;
  final String summaryJson;
  final int addedAt;
  final int updatedAt;
  const BookshelfData({
    required this.sourceId,
    required this.novelId,
    required this.summaryJson,
    required this.addedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['novel_id'] = Variable<String>(novelId);
    map['summary_json'] = Variable<String>(summaryJson);
    map['added_at'] = Variable<int>(addedAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BookshelfCompanion toCompanion(bool nullToAbsent) {
    return BookshelfCompanion(
      sourceId: Value(sourceId),
      novelId: Value(novelId),
      summaryJson: Value(summaryJson),
      addedAt: Value(addedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookshelfData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookshelfData(
      sourceId: serializer.fromJson<String>(json['source_id']),
      novelId: serializer.fromJson<String>(json['novel_id']),
      summaryJson: serializer.fromJson<String>(json['summary_json']),
      addedAt: serializer.fromJson<int>(json['added_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_id': serializer.toJson<String>(sourceId),
      'novel_id': serializer.toJson<String>(novelId),
      'summary_json': serializer.toJson<String>(summaryJson),
      'added_at': serializer.toJson<int>(addedAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  BookshelfData copyWith({
    String? sourceId,
    String? novelId,
    String? summaryJson,
    int? addedAt,
    int? updatedAt,
  }) => BookshelfData(
    sourceId: sourceId ?? this.sourceId,
    novelId: novelId ?? this.novelId,
    summaryJson: summaryJson ?? this.summaryJson,
    addedAt: addedAt ?? this.addedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookshelfData copyWithCompanion(BookshelfCompanion data) {
    return BookshelfData(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      novelId: data.novelId.present ? data.novelId.value : this.novelId,
      summaryJson: data.summaryJson.present
          ? data.summaryJson.value
          : this.summaryJson,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookshelfData(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('addedAt: $addedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceId, novelId, summaryJson, addedAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookshelfData &&
          other.sourceId == this.sourceId &&
          other.novelId == this.novelId &&
          other.summaryJson == this.summaryJson &&
          other.addedAt == this.addedAt &&
          other.updatedAt == this.updatedAt);
}

class BookshelfCompanion extends UpdateCompanion<BookshelfData> {
  final Value<String> sourceId;
  final Value<String> novelId;
  final Value<String> summaryJson;
  final Value<int> addedAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const BookshelfCompanion({
    this.sourceId = const Value.absent(),
    this.novelId = const Value.absent(),
    this.summaryJson = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookshelfCompanion.insert({
    required String sourceId,
    required String novelId,
    required String summaryJson,
    required int addedAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       novelId = Value(novelId),
       summaryJson = Value(summaryJson),
       addedAt = Value(addedAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookshelfData> custom({
    Expression<String>? sourceId,
    Expression<String>? novelId,
    Expression<String>? summaryJson,
    Expression<int>? addedAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (novelId != null) 'novel_id': novelId,
      if (summaryJson != null) 'summary_json': summaryJson,
      if (addedAt != null) 'added_at': addedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookshelfCompanion copyWith({
    Value<String>? sourceId,
    Value<String>? novelId,
    Value<String>? summaryJson,
    Value<int>? addedAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return BookshelfCompanion(
      sourceId: sourceId ?? this.sourceId,
      novelId: novelId ?? this.novelId,
      summaryJson: summaryJson ?? this.summaryJson,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (novelId.present) {
      map['novel_id'] = Variable<String>(novelId.value);
    }
    if (summaryJson.present) {
      map['summary_json'] = Variable<String>(summaryJson.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookshelfCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('addedAt: $addedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ProgressSessions extends Table
    with TableInfo<ProgressSessions, ProgressSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ProgressSessions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _novelIdMeta = const VerificationMeta(
    'novelId',
  );
  late final GeneratedColumn<String> novelId = GeneratedColumn<String>(
    'novel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (generation >= 1)',
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT (-1) CHECK (sequence >= -1)',
    defaultValue: const CustomExpression('-1'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    novelId,
    generation,
    sequence,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progress_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('novel_id')) {
      context.handle(
        _novelIdMeta,
        novelId.isAcceptableOrUnknown(data['novel_id']!, _novelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_novelIdMeta);
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    } else if (isInserting) {
      context.missing(_generationMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, novelId};
  @override
  ProgressSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressSession(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      novelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}novel_id'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
    );
  }

  @override
  ProgressSessions createAlias(String alias) {
    return ProgressSessions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(source_id, novel_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ProgressSession extends DataClass implements Insertable<ProgressSession> {
  final String sourceId;
  final String novelId;
  final int generation;
  final int sequence;
  const ProgressSession({
    required this.sourceId,
    required this.novelId,
    required this.generation,
    required this.sequence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['novel_id'] = Variable<String>(novelId);
    map['generation'] = Variable<int>(generation);
    map['sequence'] = Variable<int>(sequence);
    return map;
  }

  ProgressSessionsCompanion toCompanion(bool nullToAbsent) {
    return ProgressSessionsCompanion(
      sourceId: Value(sourceId),
      novelId: Value(novelId),
      generation: Value(generation),
      sequence: Value(sequence),
    );
  }

  factory ProgressSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressSession(
      sourceId: serializer.fromJson<String>(json['source_id']),
      novelId: serializer.fromJson<String>(json['novel_id']),
      generation: serializer.fromJson<int>(json['generation']),
      sequence: serializer.fromJson<int>(json['sequence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_id': serializer.toJson<String>(sourceId),
      'novel_id': serializer.toJson<String>(novelId),
      'generation': serializer.toJson<int>(generation),
      'sequence': serializer.toJson<int>(sequence),
    };
  }

  ProgressSession copyWith({
    String? sourceId,
    String? novelId,
    int? generation,
    int? sequence,
  }) => ProgressSession(
    sourceId: sourceId ?? this.sourceId,
    novelId: novelId ?? this.novelId,
    generation: generation ?? this.generation,
    sequence: sequence ?? this.sequence,
  );
  ProgressSession copyWithCompanion(ProgressSessionsCompanion data) {
    return ProgressSession(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      novelId: data.novelId.present ? data.novelId.value : this.novelId,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressSession(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('generation: $generation, ')
          ..write('sequence: $sequence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, novelId, generation, sequence);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressSession &&
          other.sourceId == this.sourceId &&
          other.novelId == this.novelId &&
          other.generation == this.generation &&
          other.sequence == this.sequence);
}

class ProgressSessionsCompanion extends UpdateCompanion<ProgressSession> {
  final Value<String> sourceId;
  final Value<String> novelId;
  final Value<int> generation;
  final Value<int> sequence;
  final Value<int> rowid;
  const ProgressSessionsCompanion({
    this.sourceId = const Value.absent(),
    this.novelId = const Value.absent(),
    this.generation = const Value.absent(),
    this.sequence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressSessionsCompanion.insert({
    required String sourceId,
    required String novelId,
    required int generation,
    this.sequence = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       novelId = Value(novelId),
       generation = Value(generation);
  static Insertable<ProgressSession> custom({
    Expression<String>? sourceId,
    Expression<String>? novelId,
    Expression<int>? generation,
    Expression<int>? sequence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (novelId != null) 'novel_id': novelId,
      if (generation != null) 'generation': generation,
      if (sequence != null) 'sequence': sequence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressSessionsCompanion copyWith({
    Value<String>? sourceId,
    Value<String>? novelId,
    Value<int>? generation,
    Value<int>? sequence,
    Value<int>? rowid,
  }) {
    return ProgressSessionsCompanion(
      sourceId: sourceId ?? this.sourceId,
      novelId: novelId ?? this.novelId,
      generation: generation ?? this.generation,
      sequence: sequence ?? this.sequence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (novelId.present) {
      map['novel_id'] = Variable<String>(novelId.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressSessionsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('generation: $generation, ')
          ..write('sequence: $sequence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ReadingProgress extends Table
    with TableInfo<ReadingProgress, ReadingProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ReadingProgress(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _novelIdMeta = const VerificationMeta(
    'novelId',
  );
  late final GeneratedColumn<String> novelId = GeneratedColumn<String>(
    'novel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _summaryJsonMeta = const VerificationMeta(
    'summaryJson',
  );
  late final GeneratedColumn<String> summaryJson = GeneratedColumn<String>(
    'summary_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _chapterOrdinalMeta = const VerificationMeta(
    'chapterOrdinal',
  );
  late final GeneratedColumn<int> chapterOrdinal = GeneratedColumn<int>(
    'chapter_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (chapter_ordinal >= 0)',
  );
  static const VerificationMeta _catalogRevisionMeta = const VerificationMeta(
    'catalogRevision',
  );
  late final GeneratedColumn<String> catalogRevision = GeneratedColumn<String>(
    'catalog_revision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _contentRevisionMeta = const VerificationMeta(
    'contentRevision',
  );
  late final GeneratedColumn<String> contentRevision = GeneratedColumn<String>(
    'content_revision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _blockKeyMeta = const VerificationMeta(
    'blockKey',
  );
  late final GeneratedColumn<String> blockKey = GeneratedColumn<String>(
    'block_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _blockIndexMeta = const VerificationMeta(
    'blockIndex',
  );
  late final GeneratedColumn<int> blockIndex = GeneratedColumn<int>(
    'block_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (block_index >= 0)',
  );
  static const VerificationMeta _blockFractionMeta = const VerificationMeta(
    'blockFraction',
  );
  late final GeneratedColumn<double> blockFraction = GeneratedColumn<double>(
    'block_fraction',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (block_fraction >= 0 AND block_fraction <= 1)',
  );
  static const VerificationMeta _chapterFractionMeta = const VerificationMeta(
    'chapterFraction',
  );
  late final GeneratedColumn<double> chapterFraction = GeneratedColumn<double>(
    'chapter_fraction',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (chapter_fraction >= 0 AND chapter_fraction <= 1)',
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  late final GeneratedColumn<int> completed = GeneratedColumn<int>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (completed IN (0, 1))',
  );
  static const VerificationMeta _pixelOffsetMeta = const VerificationMeta(
    'pixelOffset',
  );
  late final GeneratedColumn<double> pixelOffset = GeneratedColumn<double>(
    'pixel_offset',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (pixel_offset >= 0)',
  );
  static const VerificationMeta _layoutKeyMeta = const VerificationMeta(
    'layoutKey',
  );
  late final GeneratedColumn<String> layoutKey = GeneratedColumn<String>(
    'layout_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _positionVersionMeta = const VerificationMeta(
    'positionVersion',
  );
  late final GeneratedColumn<int> positionVersion = GeneratedColumn<int>(
    'position_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (position_version >= 1)',
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  late final GeneratedColumn<int> lastReadAt = GeneratedColumn<int>(
    'last_read_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    novelId,
    chapterId,
    summaryJson,
    chapterOrdinal,
    catalogRevision,
    contentRevision,
    blockKey,
    blockIndex,
    blockFraction,
    chapterFraction,
    completed,
    pixelOffset,
    layoutKey,
    positionVersion,
    lastReadAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('novel_id')) {
      context.handle(
        _novelIdMeta,
        novelId.isAcceptableOrUnknown(data['novel_id']!, _novelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_novelIdMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterIdMeta);
    }
    if (data.containsKey('summary_json')) {
      context.handle(
        _summaryJsonMeta,
        summaryJson.isAcceptableOrUnknown(
          data['summary_json']!,
          _summaryJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryJsonMeta);
    }
    if (data.containsKey('chapter_ordinal')) {
      context.handle(
        _chapterOrdinalMeta,
        chapterOrdinal.isAcceptableOrUnknown(
          data['chapter_ordinal']!,
          _chapterOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterOrdinalMeta);
    }
    if (data.containsKey('catalog_revision')) {
      context.handle(
        _catalogRevisionMeta,
        catalogRevision.isAcceptableOrUnknown(
          data['catalog_revision']!,
          _catalogRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_catalogRevisionMeta);
    }
    if (data.containsKey('content_revision')) {
      context.handle(
        _contentRevisionMeta,
        contentRevision.isAcceptableOrUnknown(
          data['content_revision']!,
          _contentRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentRevisionMeta);
    }
    if (data.containsKey('block_key')) {
      context.handle(
        _blockKeyMeta,
        blockKey.isAcceptableOrUnknown(data['block_key']!, _blockKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_blockKeyMeta);
    }
    if (data.containsKey('block_index')) {
      context.handle(
        _blockIndexMeta,
        blockIndex.isAcceptableOrUnknown(data['block_index']!, _blockIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_blockIndexMeta);
    }
    if (data.containsKey('block_fraction')) {
      context.handle(
        _blockFractionMeta,
        blockFraction.isAcceptableOrUnknown(
          data['block_fraction']!,
          _blockFractionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_blockFractionMeta);
    }
    if (data.containsKey('chapter_fraction')) {
      context.handle(
        _chapterFractionMeta,
        chapterFraction.isAcceptableOrUnknown(
          data['chapter_fraction']!,
          _chapterFractionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterFractionMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    } else if (isInserting) {
      context.missing(_completedMeta);
    }
    if (data.containsKey('pixel_offset')) {
      context.handle(
        _pixelOffsetMeta,
        pixelOffset.isAcceptableOrUnknown(
          data['pixel_offset']!,
          _pixelOffsetMeta,
        ),
      );
    }
    if (data.containsKey('layout_key')) {
      context.handle(
        _layoutKeyMeta,
        layoutKey.isAcceptableOrUnknown(data['layout_key']!, _layoutKeyMeta),
      );
    }
    if (data.containsKey('position_version')) {
      context.handle(
        _positionVersionMeta,
        positionVersion.isAcceptableOrUnknown(
          data['position_version']!,
          _positionVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_positionVersionMeta);
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastReadAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, novelId};
  @override
  ReadingProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingProgressData(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      novelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}novel_id'],
      )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      )!,
      summaryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_json'],
      )!,
      chapterOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_ordinal'],
      )!,
      catalogRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catalog_revision'],
      )!,
      contentRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_revision'],
      )!,
      blockKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}block_key'],
      )!,
      blockIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}block_index'],
      )!,
      blockFraction: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}block_fraction'],
      )!,
      chapterFraction: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}chapter_fraction'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed'],
      )!,
      pixelOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pixel_offset'],
      ),
      layoutKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}layout_key'],
      ),
      positionVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_version'],
      )!,
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  ReadingProgress createAlias(String alias) {
    return ReadingProgress(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'CHECK((pixel_offset IS NULL)=(layout_key IS NULL))',
    'PRIMARY KEY(source_id, novel_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ReadingProgressData extends DataClass
    implements Insertable<ReadingProgressData> {
  final String sourceId;
  final String novelId;
  final String chapterId;
  final String summaryJson;
  final int chapterOrdinal;
  final String catalogRevision;
  final String contentRevision;
  final String blockKey;
  final int blockIndex;
  final double blockFraction;
  final double chapterFraction;
  final int completed;
  final double? pixelOffset;
  final String? layoutKey;
  final int positionVersion;
  final int lastReadAt;
  final int updatedAt;
  const ReadingProgressData({
    required this.sourceId,
    required this.novelId,
    required this.chapterId,
    required this.summaryJson,
    required this.chapterOrdinal,
    required this.catalogRevision,
    required this.contentRevision,
    required this.blockKey,
    required this.blockIndex,
    required this.blockFraction,
    required this.chapterFraction,
    required this.completed,
    this.pixelOffset,
    this.layoutKey,
    required this.positionVersion,
    required this.lastReadAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['novel_id'] = Variable<String>(novelId);
    map['chapter_id'] = Variable<String>(chapterId);
    map['summary_json'] = Variable<String>(summaryJson);
    map['chapter_ordinal'] = Variable<int>(chapterOrdinal);
    map['catalog_revision'] = Variable<String>(catalogRevision);
    map['content_revision'] = Variable<String>(contentRevision);
    map['block_key'] = Variable<String>(blockKey);
    map['block_index'] = Variable<int>(blockIndex);
    map['block_fraction'] = Variable<double>(blockFraction);
    map['chapter_fraction'] = Variable<double>(chapterFraction);
    map['completed'] = Variable<int>(completed);
    if (!nullToAbsent || pixelOffset != null) {
      map['pixel_offset'] = Variable<double>(pixelOffset);
    }
    if (!nullToAbsent || layoutKey != null) {
      map['layout_key'] = Variable<String>(layoutKey);
    }
    map['position_version'] = Variable<int>(positionVersion);
    map['last_read_at'] = Variable<int>(lastReadAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ReadingProgressCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressCompanion(
      sourceId: Value(sourceId),
      novelId: Value(novelId),
      chapterId: Value(chapterId),
      summaryJson: Value(summaryJson),
      chapterOrdinal: Value(chapterOrdinal),
      catalogRevision: Value(catalogRevision),
      contentRevision: Value(contentRevision),
      blockKey: Value(blockKey),
      blockIndex: Value(blockIndex),
      blockFraction: Value(blockFraction),
      chapterFraction: Value(chapterFraction),
      completed: Value(completed),
      pixelOffset: pixelOffset == null && nullToAbsent
          ? const Value.absent()
          : Value(pixelOffset),
      layoutKey: layoutKey == null && nullToAbsent
          ? const Value.absent()
          : Value(layoutKey),
      positionVersion: Value(positionVersion),
      lastReadAt: Value(lastReadAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReadingProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingProgressData(
      sourceId: serializer.fromJson<String>(json['source_id']),
      novelId: serializer.fromJson<String>(json['novel_id']),
      chapterId: serializer.fromJson<String>(json['chapter_id']),
      summaryJson: serializer.fromJson<String>(json['summary_json']),
      chapterOrdinal: serializer.fromJson<int>(json['chapter_ordinal']),
      catalogRevision: serializer.fromJson<String>(json['catalog_revision']),
      contentRevision: serializer.fromJson<String>(json['content_revision']),
      blockKey: serializer.fromJson<String>(json['block_key']),
      blockIndex: serializer.fromJson<int>(json['block_index']),
      blockFraction: serializer.fromJson<double>(json['block_fraction']),
      chapterFraction: serializer.fromJson<double>(json['chapter_fraction']),
      completed: serializer.fromJson<int>(json['completed']),
      pixelOffset: serializer.fromJson<double?>(json['pixel_offset']),
      layoutKey: serializer.fromJson<String?>(json['layout_key']),
      positionVersion: serializer.fromJson<int>(json['position_version']),
      lastReadAt: serializer.fromJson<int>(json['last_read_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_id': serializer.toJson<String>(sourceId),
      'novel_id': serializer.toJson<String>(novelId),
      'chapter_id': serializer.toJson<String>(chapterId),
      'summary_json': serializer.toJson<String>(summaryJson),
      'chapter_ordinal': serializer.toJson<int>(chapterOrdinal),
      'catalog_revision': serializer.toJson<String>(catalogRevision),
      'content_revision': serializer.toJson<String>(contentRevision),
      'block_key': serializer.toJson<String>(blockKey),
      'block_index': serializer.toJson<int>(blockIndex),
      'block_fraction': serializer.toJson<double>(blockFraction),
      'chapter_fraction': serializer.toJson<double>(chapterFraction),
      'completed': serializer.toJson<int>(completed),
      'pixel_offset': serializer.toJson<double?>(pixelOffset),
      'layout_key': serializer.toJson<String?>(layoutKey),
      'position_version': serializer.toJson<int>(positionVersion),
      'last_read_at': serializer.toJson<int>(lastReadAt),
      'updated_at': serializer.toJson<int>(updatedAt),
    };
  }

  ReadingProgressData copyWith({
    String? sourceId,
    String? novelId,
    String? chapterId,
    String? summaryJson,
    int? chapterOrdinal,
    String? catalogRevision,
    String? contentRevision,
    String? blockKey,
    int? blockIndex,
    double? blockFraction,
    double? chapterFraction,
    int? completed,
    Value<double?> pixelOffset = const Value.absent(),
    Value<String?> layoutKey = const Value.absent(),
    int? positionVersion,
    int? lastReadAt,
    int? updatedAt,
  }) => ReadingProgressData(
    sourceId: sourceId ?? this.sourceId,
    novelId: novelId ?? this.novelId,
    chapterId: chapterId ?? this.chapterId,
    summaryJson: summaryJson ?? this.summaryJson,
    chapterOrdinal: chapterOrdinal ?? this.chapterOrdinal,
    catalogRevision: catalogRevision ?? this.catalogRevision,
    contentRevision: contentRevision ?? this.contentRevision,
    blockKey: blockKey ?? this.blockKey,
    blockIndex: blockIndex ?? this.blockIndex,
    blockFraction: blockFraction ?? this.blockFraction,
    chapterFraction: chapterFraction ?? this.chapterFraction,
    completed: completed ?? this.completed,
    pixelOffset: pixelOffset.present ? pixelOffset.value : this.pixelOffset,
    layoutKey: layoutKey.present ? layoutKey.value : this.layoutKey,
    positionVersion: positionVersion ?? this.positionVersion,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReadingProgressData copyWithCompanion(ReadingProgressCompanion data) {
    return ReadingProgressData(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      novelId: data.novelId.present ? data.novelId.value : this.novelId,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      summaryJson: data.summaryJson.present
          ? data.summaryJson.value
          : this.summaryJson,
      chapterOrdinal: data.chapterOrdinal.present
          ? data.chapterOrdinal.value
          : this.chapterOrdinal,
      catalogRevision: data.catalogRevision.present
          ? data.catalogRevision.value
          : this.catalogRevision,
      contentRevision: data.contentRevision.present
          ? data.contentRevision.value
          : this.contentRevision,
      blockKey: data.blockKey.present ? data.blockKey.value : this.blockKey,
      blockIndex: data.blockIndex.present
          ? data.blockIndex.value
          : this.blockIndex,
      blockFraction: data.blockFraction.present
          ? data.blockFraction.value
          : this.blockFraction,
      chapterFraction: data.chapterFraction.present
          ? data.chapterFraction.value
          : this.chapterFraction,
      completed: data.completed.present ? data.completed.value : this.completed,
      pixelOffset: data.pixelOffset.present
          ? data.pixelOffset.value
          : this.pixelOffset,
      layoutKey: data.layoutKey.present ? data.layoutKey.value : this.layoutKey,
      positionVersion: data.positionVersion.present
          ? data.positionVersion.value
          : this.positionVersion,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressData(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('chapterId: $chapterId, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('chapterOrdinal: $chapterOrdinal, ')
          ..write('catalogRevision: $catalogRevision, ')
          ..write('contentRevision: $contentRevision, ')
          ..write('blockKey: $blockKey, ')
          ..write('blockIndex: $blockIndex, ')
          ..write('blockFraction: $blockFraction, ')
          ..write('chapterFraction: $chapterFraction, ')
          ..write('completed: $completed, ')
          ..write('pixelOffset: $pixelOffset, ')
          ..write('layoutKey: $layoutKey, ')
          ..write('positionVersion: $positionVersion, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    novelId,
    chapterId,
    summaryJson,
    chapterOrdinal,
    catalogRevision,
    contentRevision,
    blockKey,
    blockIndex,
    blockFraction,
    chapterFraction,
    completed,
    pixelOffset,
    layoutKey,
    positionVersion,
    lastReadAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingProgressData &&
          other.sourceId == this.sourceId &&
          other.novelId == this.novelId &&
          other.chapterId == this.chapterId &&
          other.summaryJson == this.summaryJson &&
          other.chapterOrdinal == this.chapterOrdinal &&
          other.catalogRevision == this.catalogRevision &&
          other.contentRevision == this.contentRevision &&
          other.blockKey == this.blockKey &&
          other.blockIndex == this.blockIndex &&
          other.blockFraction == this.blockFraction &&
          other.chapterFraction == this.chapterFraction &&
          other.completed == this.completed &&
          other.pixelOffset == this.pixelOffset &&
          other.layoutKey == this.layoutKey &&
          other.positionVersion == this.positionVersion &&
          other.lastReadAt == this.lastReadAt &&
          other.updatedAt == this.updatedAt);
}

class ReadingProgressCompanion extends UpdateCompanion<ReadingProgressData> {
  final Value<String> sourceId;
  final Value<String> novelId;
  final Value<String> chapterId;
  final Value<String> summaryJson;
  final Value<int> chapterOrdinal;
  final Value<String> catalogRevision;
  final Value<String> contentRevision;
  final Value<String> blockKey;
  final Value<int> blockIndex;
  final Value<double> blockFraction;
  final Value<double> chapterFraction;
  final Value<int> completed;
  final Value<double?> pixelOffset;
  final Value<String?> layoutKey;
  final Value<int> positionVersion;
  final Value<int> lastReadAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ReadingProgressCompanion({
    this.sourceId = const Value.absent(),
    this.novelId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.summaryJson = const Value.absent(),
    this.chapterOrdinal = const Value.absent(),
    this.catalogRevision = const Value.absent(),
    this.contentRevision = const Value.absent(),
    this.blockKey = const Value.absent(),
    this.blockIndex = const Value.absent(),
    this.blockFraction = const Value.absent(),
    this.chapterFraction = const Value.absent(),
    this.completed = const Value.absent(),
    this.pixelOffset = const Value.absent(),
    this.layoutKey = const Value.absent(),
    this.positionVersion = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressCompanion.insert({
    required String sourceId,
    required String novelId,
    required String chapterId,
    required String summaryJson,
    required int chapterOrdinal,
    required String catalogRevision,
    required String contentRevision,
    required String blockKey,
    required int blockIndex,
    required double blockFraction,
    required double chapterFraction,
    required int completed,
    this.pixelOffset = const Value.absent(),
    this.layoutKey = const Value.absent(),
    required int positionVersion,
    required int lastReadAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       novelId = Value(novelId),
       chapterId = Value(chapterId),
       summaryJson = Value(summaryJson),
       chapterOrdinal = Value(chapterOrdinal),
       catalogRevision = Value(catalogRevision),
       contentRevision = Value(contentRevision),
       blockKey = Value(blockKey),
       blockIndex = Value(blockIndex),
       blockFraction = Value(blockFraction),
       chapterFraction = Value(chapterFraction),
       completed = Value(completed),
       positionVersion = Value(positionVersion),
       lastReadAt = Value(lastReadAt),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingProgressData> custom({
    Expression<String>? sourceId,
    Expression<String>? novelId,
    Expression<String>? chapterId,
    Expression<String>? summaryJson,
    Expression<int>? chapterOrdinal,
    Expression<String>? catalogRevision,
    Expression<String>? contentRevision,
    Expression<String>? blockKey,
    Expression<int>? blockIndex,
    Expression<double>? blockFraction,
    Expression<double>? chapterFraction,
    Expression<int>? completed,
    Expression<double>? pixelOffset,
    Expression<String>? layoutKey,
    Expression<int>? positionVersion,
    Expression<int>? lastReadAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (novelId != null) 'novel_id': novelId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (summaryJson != null) 'summary_json': summaryJson,
      if (chapterOrdinal != null) 'chapter_ordinal': chapterOrdinal,
      if (catalogRevision != null) 'catalog_revision': catalogRevision,
      if (contentRevision != null) 'content_revision': contentRevision,
      if (blockKey != null) 'block_key': blockKey,
      if (blockIndex != null) 'block_index': blockIndex,
      if (blockFraction != null) 'block_fraction': blockFraction,
      if (chapterFraction != null) 'chapter_fraction': chapterFraction,
      if (completed != null) 'completed': completed,
      if (pixelOffset != null) 'pixel_offset': pixelOffset,
      if (layoutKey != null) 'layout_key': layoutKey,
      if (positionVersion != null) 'position_version': positionVersion,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressCompanion copyWith({
    Value<String>? sourceId,
    Value<String>? novelId,
    Value<String>? chapterId,
    Value<String>? summaryJson,
    Value<int>? chapterOrdinal,
    Value<String>? catalogRevision,
    Value<String>? contentRevision,
    Value<String>? blockKey,
    Value<int>? blockIndex,
    Value<double>? blockFraction,
    Value<double>? chapterFraction,
    Value<int>? completed,
    Value<double?>? pixelOffset,
    Value<String?>? layoutKey,
    Value<int>? positionVersion,
    Value<int>? lastReadAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReadingProgressCompanion(
      sourceId: sourceId ?? this.sourceId,
      novelId: novelId ?? this.novelId,
      chapterId: chapterId ?? this.chapterId,
      summaryJson: summaryJson ?? this.summaryJson,
      chapterOrdinal: chapterOrdinal ?? this.chapterOrdinal,
      catalogRevision: catalogRevision ?? this.catalogRevision,
      contentRevision: contentRevision ?? this.contentRevision,
      blockKey: blockKey ?? this.blockKey,
      blockIndex: blockIndex ?? this.blockIndex,
      blockFraction: blockFraction ?? this.blockFraction,
      chapterFraction: chapterFraction ?? this.chapterFraction,
      completed: completed ?? this.completed,
      pixelOffset: pixelOffset ?? this.pixelOffset,
      layoutKey: layoutKey ?? this.layoutKey,
      positionVersion: positionVersion ?? this.positionVersion,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (novelId.present) {
      map['novel_id'] = Variable<String>(novelId.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (summaryJson.present) {
      map['summary_json'] = Variable<String>(summaryJson.value);
    }
    if (chapterOrdinal.present) {
      map['chapter_ordinal'] = Variable<int>(chapterOrdinal.value);
    }
    if (catalogRevision.present) {
      map['catalog_revision'] = Variable<String>(catalogRevision.value);
    }
    if (contentRevision.present) {
      map['content_revision'] = Variable<String>(contentRevision.value);
    }
    if (blockKey.present) {
      map['block_key'] = Variable<String>(blockKey.value);
    }
    if (blockIndex.present) {
      map['block_index'] = Variable<int>(blockIndex.value);
    }
    if (blockFraction.present) {
      map['block_fraction'] = Variable<double>(blockFraction.value);
    }
    if (chapterFraction.present) {
      map['chapter_fraction'] = Variable<double>(chapterFraction.value);
    }
    if (completed.present) {
      map['completed'] = Variable<int>(completed.value);
    }
    if (pixelOffset.present) {
      map['pixel_offset'] = Variable<double>(pixelOffset.value);
    }
    if (layoutKey.present) {
      map['layout_key'] = Variable<String>(layoutKey.value);
    }
    if (positionVersion.present) {
      map['position_version'] = Variable<int>(positionVersion.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<int>(lastReadAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('chapterId: $chapterId, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('chapterOrdinal: $chapterOrdinal, ')
          ..write('catalogRevision: $catalogRevision, ')
          ..write('contentRevision: $contentRevision, ')
          ..write('blockKey: $blockKey, ')
          ..write('blockIndex: $blockIndex, ')
          ..write('blockFraction: $blockFraction, ')
          ..write('chapterFraction: $chapterFraction, ')
          ..write('completed: $completed, ')
          ..write('pixelOffset: $pixelOffset, ')
          ..write('layoutKey: $layoutKey, ')
          ..write('positionVersion: $positionVersion, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class PrefetchChoices extends Table
    with TableInfo<PrefetchChoices, PrefetchChoice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PrefetchChoices(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _novelIdMeta = const VerificationMeta(
    'novelId',
  );
  late final GeneratedColumn<String> novelId = GeneratedColumn<String>(
    'novel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    novelId,
    chapterId,
    targetId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prefetch_choices';
  @override
  VerificationContext validateIntegrity(
    Insertable<PrefetchChoice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('novel_id')) {
      context.handle(
        _novelIdMeta,
        novelId.isAcceptableOrUnknown(data['novel_id']!, _novelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_novelIdMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterIdMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, novelId, chapterId};
  @override
  PrefetchChoice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrefetchChoice(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      novelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}novel_id'],
      )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
    );
  }

  @override
  PrefetchChoices createAlias(String alias) {
    return PrefetchChoices(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(source_id, novel_id, chapter_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class PrefetchChoice extends DataClass implements Insertable<PrefetchChoice> {
  final String sourceId;
  final String novelId;
  final String chapterId;
  final String targetId;
  const PrefetchChoice({
    required this.sourceId,
    required this.novelId,
    required this.chapterId,
    required this.targetId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['novel_id'] = Variable<String>(novelId);
    map['chapter_id'] = Variable<String>(chapterId);
    map['target_id'] = Variable<String>(targetId);
    return map;
  }

  PrefetchChoicesCompanion toCompanion(bool nullToAbsent) {
    return PrefetchChoicesCompanion(
      sourceId: Value(sourceId),
      novelId: Value(novelId),
      chapterId: Value(chapterId),
      targetId: Value(targetId),
    );
  }

  factory PrefetchChoice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrefetchChoice(
      sourceId: serializer.fromJson<String>(json['source_id']),
      novelId: serializer.fromJson<String>(json['novel_id']),
      chapterId: serializer.fromJson<String>(json['chapter_id']),
      targetId: serializer.fromJson<String>(json['target_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_id': serializer.toJson<String>(sourceId),
      'novel_id': serializer.toJson<String>(novelId),
      'chapter_id': serializer.toJson<String>(chapterId),
      'target_id': serializer.toJson<String>(targetId),
    };
  }

  PrefetchChoice copyWith({
    String? sourceId,
    String? novelId,
    String? chapterId,
    String? targetId,
  }) => PrefetchChoice(
    sourceId: sourceId ?? this.sourceId,
    novelId: novelId ?? this.novelId,
    chapterId: chapterId ?? this.chapterId,
    targetId: targetId ?? this.targetId,
  );
  PrefetchChoice copyWithCompanion(PrefetchChoicesCompanion data) {
    return PrefetchChoice(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      novelId: data.novelId.present ? data.novelId.value : this.novelId,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrefetchChoice(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('chapterId: $chapterId, ')
          ..write('targetId: $targetId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, novelId, chapterId, targetId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrefetchChoice &&
          other.sourceId == this.sourceId &&
          other.novelId == this.novelId &&
          other.chapterId == this.chapterId &&
          other.targetId == this.targetId);
}

class PrefetchChoicesCompanion extends UpdateCompanion<PrefetchChoice> {
  final Value<String> sourceId;
  final Value<String> novelId;
  final Value<String> chapterId;
  final Value<String> targetId;
  final Value<int> rowid;
  const PrefetchChoicesCompanion({
    this.sourceId = const Value.absent(),
    this.novelId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PrefetchChoicesCompanion.insert({
    required String sourceId,
    required String novelId,
    required String chapterId,
    required String targetId,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       novelId = Value(novelId),
       chapterId = Value(chapterId),
       targetId = Value(targetId);
  static Insertable<PrefetchChoice> custom({
    Expression<String>? sourceId,
    Expression<String>? novelId,
    Expression<String>? chapterId,
    Expression<String>? targetId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (novelId != null) 'novel_id': novelId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (targetId != null) 'target_id': targetId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PrefetchChoicesCompanion copyWith({
    Value<String>? sourceId,
    Value<String>? novelId,
    Value<String>? chapterId,
    Value<String>? targetId,
    Value<int>? rowid,
  }) {
    return PrefetchChoicesCompanion(
      sourceId: sourceId ?? this.sourceId,
      novelId: novelId ?? this.novelId,
      chapterId: chapterId ?? this.chapterId,
      targetId: targetId ?? this.targetId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (novelId.present) {
      map['novel_id'] = Variable<String>(novelId.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrefetchChoicesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('chapterId: $chapterId, ')
          ..write('targetId: $targetId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class PrefetchSettings extends Table
    with TableInfo<PrefetchSettings, PrefetchSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PrefetchSettings(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (id = 1)',
  );
  static const VerificationMeta _currentEnabledMeta = const VerificationMeta(
    'currentEnabled',
  );
  late final GeneratedColumn<int> currentEnabled = GeneratedColumn<int>(
    'current_enabled',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _nextEnabledMeta = const VerificationMeta(
    'nextEnabled',
  );
  late final GeneratedColumn<int> nextEnabled = GeneratedColumn<int>(
    'next_enabled',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [id, currentEnabled, nextEnabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prefetch_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<PrefetchSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('current_enabled')) {
      context.handle(
        _currentEnabledMeta,
        currentEnabled.isAcceptableOrUnknown(
          data['current_enabled']!,
          _currentEnabledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentEnabledMeta);
    }
    if (data.containsKey('next_enabled')) {
      context.handle(
        _nextEnabledMeta,
        nextEnabled.isAcceptableOrUnknown(
          data['next_enabled']!,
          _nextEnabledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextEnabledMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PrefetchSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrefetchSetting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      currentEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_enabled'],
      )!,
      nextEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_enabled'],
      )!,
    );
  }

  @override
  PrefetchSettings createAlias(String alias) {
    return PrefetchSettings(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PrefetchSetting extends DataClass implements Insertable<PrefetchSetting> {
  final int id;
  final int currentEnabled;
  final int nextEnabled;
  const PrefetchSetting({
    required this.id,
    required this.currentEnabled,
    required this.nextEnabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['current_enabled'] = Variable<int>(currentEnabled);
    map['next_enabled'] = Variable<int>(nextEnabled);
    return map;
  }

  PrefetchSettingsCompanion toCompanion(bool nullToAbsent) {
    return PrefetchSettingsCompanion(
      id: Value(id),
      currentEnabled: Value(currentEnabled),
      nextEnabled: Value(nextEnabled),
    );
  }

  factory PrefetchSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrefetchSetting(
      id: serializer.fromJson<int>(json['id']),
      currentEnabled: serializer.fromJson<int>(json['current_enabled']),
      nextEnabled: serializer.fromJson<int>(json['next_enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'current_enabled': serializer.toJson<int>(currentEnabled),
      'next_enabled': serializer.toJson<int>(nextEnabled),
    };
  }

  PrefetchSetting copyWith({int? id, int? currentEnabled, int? nextEnabled}) =>
      PrefetchSetting(
        id: id ?? this.id,
        currentEnabled: currentEnabled ?? this.currentEnabled,
        nextEnabled: nextEnabled ?? this.nextEnabled,
      );
  PrefetchSetting copyWithCompanion(PrefetchSettingsCompanion data) {
    return PrefetchSetting(
      id: data.id.present ? data.id.value : this.id,
      currentEnabled: data.currentEnabled.present
          ? data.currentEnabled.value
          : this.currentEnabled,
      nextEnabled: data.nextEnabled.present
          ? data.nextEnabled.value
          : this.nextEnabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrefetchSetting(')
          ..write('id: $id, ')
          ..write('currentEnabled: $currentEnabled, ')
          ..write('nextEnabled: $nextEnabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, currentEnabled, nextEnabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrefetchSetting &&
          other.id == this.id &&
          other.currentEnabled == this.currentEnabled &&
          other.nextEnabled == this.nextEnabled);
}

class PrefetchSettingsCompanion extends UpdateCompanion<PrefetchSetting> {
  final Value<int> id;
  final Value<int> currentEnabled;
  final Value<int> nextEnabled;
  const PrefetchSettingsCompanion({
    this.id = const Value.absent(),
    this.currentEnabled = const Value.absent(),
    this.nextEnabled = const Value.absent(),
  });
  PrefetchSettingsCompanion.insert({
    this.id = const Value.absent(),
    required int currentEnabled,
    required int nextEnabled,
  }) : currentEnabled = Value(currentEnabled),
       nextEnabled = Value(nextEnabled);
  static Insertable<PrefetchSetting> custom({
    Expression<int>? id,
    Expression<int>? currentEnabled,
    Expression<int>? nextEnabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (currentEnabled != null) 'current_enabled': currentEnabled,
      if (nextEnabled != null) 'next_enabled': nextEnabled,
    });
  }

  PrefetchSettingsCompanion copyWith({
    Value<int>? id,
    Value<int>? currentEnabled,
    Value<int>? nextEnabled,
  }) {
    return PrefetchSettingsCompanion(
      id: id ?? this.id,
      currentEnabled: currentEnabled ?? this.currentEnabled,
      nextEnabled: nextEnabled ?? this.nextEnabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (currentEnabled.present) {
      map['current_enabled'] = Variable<int>(currentEnabled.value);
    }
    if (nextEnabled.present) {
      map['next_enabled'] = Variable<int>(nextEnabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrefetchSettingsCompanion(')
          ..write('id: $id, ')
          ..write('currentEnabled: $currentEnabled, ')
          ..write('nextEnabled: $nextEnabled')
          ..write(')'))
        .toString();
  }
}

class LocalBooks extends Table with TableInfo<LocalBooks, LocalBook> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LocalBooks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _digestMeta = const VerificationMeta('digest');
  late final GeneratedColumn<String> digest = GeneratedColumn<String>(
    'digest',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(digest) = 64)',
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (format IN (\'txt\', \'epub\'))',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  late final GeneratedColumn<int> importedAt = GeneratedColumn<int>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _manifestHashMeta = const VerificationMeta(
    'manifestHash',
  );
  late final GeneratedColumn<String> manifestHash = GeneratedColumn<String>(
    'manifest_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(manifest_hash) = 64)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    digest,
    format,
    title,
    importedAt,
    manifestHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_books';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalBook> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('digest')) {
      context.handle(
        _digestMeta,
        digest.isAcceptableOrUnknown(data['digest']!, _digestMeta),
      );
    } else if (isInserting) {
      context.missing(_digestMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('manifest_hash')) {
      context.handle(
        _manifestHashMeta,
        manifestHash.isAcceptableOrUnknown(
          data['manifest_hash']!,
          _manifestHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestHashMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {digest};
  @override
  LocalBook map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalBook(
      digest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}digest'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_at'],
      )!,
      manifestHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_hash'],
      )!,
    );
  }

  @override
  LocalBooks createAlias(String alias) {
    return LocalBooks(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class LocalBook extends DataClass implements Insertable<LocalBook> {
  final String digest;
  final String format;
  final String title;
  final int importedAt;
  final String manifestHash;
  const LocalBook({
    required this.digest,
    required this.format,
    required this.title,
    required this.importedAt,
    required this.manifestHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['digest'] = Variable<String>(digest);
    map['format'] = Variable<String>(format);
    map['title'] = Variable<String>(title);
    map['imported_at'] = Variable<int>(importedAt);
    map['manifest_hash'] = Variable<String>(manifestHash);
    return map;
  }

  LocalBooksCompanion toCompanion(bool nullToAbsent) {
    return LocalBooksCompanion(
      digest: Value(digest),
      format: Value(format),
      title: Value(title),
      importedAt: Value(importedAt),
      manifestHash: Value(manifestHash),
    );
  }

  factory LocalBook.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalBook(
      digest: serializer.fromJson<String>(json['digest']),
      format: serializer.fromJson<String>(json['format']),
      title: serializer.fromJson<String>(json['title']),
      importedAt: serializer.fromJson<int>(json['imported_at']),
      manifestHash: serializer.fromJson<String>(json['manifest_hash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'digest': serializer.toJson<String>(digest),
      'format': serializer.toJson<String>(format),
      'title': serializer.toJson<String>(title),
      'imported_at': serializer.toJson<int>(importedAt),
      'manifest_hash': serializer.toJson<String>(manifestHash),
    };
  }

  LocalBook copyWith({
    String? digest,
    String? format,
    String? title,
    int? importedAt,
    String? manifestHash,
  }) => LocalBook(
    digest: digest ?? this.digest,
    format: format ?? this.format,
    title: title ?? this.title,
    importedAt: importedAt ?? this.importedAt,
    manifestHash: manifestHash ?? this.manifestHash,
  );
  LocalBook copyWithCompanion(LocalBooksCompanion data) {
    return LocalBook(
      digest: data.digest.present ? data.digest.value : this.digest,
      format: data.format.present ? data.format.value : this.format,
      title: data.title.present ? data.title.value : this.title,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      manifestHash: data.manifestHash.present
          ? data.manifestHash.value
          : this.manifestHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalBook(')
          ..write('digest: $digest, ')
          ..write('format: $format, ')
          ..write('title: $title, ')
          ..write('importedAt: $importedAt, ')
          ..write('manifestHash: $manifestHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(digest, format, title, importedAt, manifestHash);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalBook &&
          other.digest == this.digest &&
          other.format == this.format &&
          other.title == this.title &&
          other.importedAt == this.importedAt &&
          other.manifestHash == this.manifestHash);
}

class LocalBooksCompanion extends UpdateCompanion<LocalBook> {
  final Value<String> digest;
  final Value<String> format;
  final Value<String> title;
  final Value<int> importedAt;
  final Value<String> manifestHash;
  final Value<int> rowid;
  const LocalBooksCompanion({
    this.digest = const Value.absent(),
    this.format = const Value.absent(),
    this.title = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.manifestHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalBooksCompanion.insert({
    required String digest,
    required String format,
    required String title,
    required int importedAt,
    required String manifestHash,
    this.rowid = const Value.absent(),
  }) : digest = Value(digest),
       format = Value(format),
       title = Value(title),
       importedAt = Value(importedAt),
       manifestHash = Value(manifestHash);
  static Insertable<LocalBook> custom({
    Expression<String>? digest,
    Expression<String>? format,
    Expression<String>? title,
    Expression<int>? importedAt,
    Expression<String>? manifestHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (digest != null) 'digest': digest,
      if (format != null) 'format': format,
      if (title != null) 'title': title,
      if (importedAt != null) 'imported_at': importedAt,
      if (manifestHash != null) 'manifest_hash': manifestHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalBooksCompanion copyWith({
    Value<String>? digest,
    Value<String>? format,
    Value<String>? title,
    Value<int>? importedAt,
    Value<String>? manifestHash,
    Value<int>? rowid,
  }) {
    return LocalBooksCompanion(
      digest: digest ?? this.digest,
      format: format ?? this.format,
      title: title ?? this.title,
      importedAt: importedAt ?? this.importedAt,
      manifestHash: manifestHash ?? this.manifestHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (digest.present) {
      map['digest'] = Variable<String>(digest.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
    }
    if (manifestHash.present) {
      map['manifest_hash'] = Variable<String>(manifestHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalBooksCompanion(')
          ..write('digest: $digest, ')
          ..write('format: $format, ')
          ..write('title: $title, ')
          ..write('importedAt: $importedAt, ')
          ..write('manifestHash: $manifestHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$UserDatabase extends GeneratedDatabase {
  _$UserDatabase(QueryExecutor e) : super(e);
  $UserDatabaseManager get managers => $UserDatabaseManager(this);
  late final Bookshelf bookshelf = Bookshelf(this);
  late final Index bookshelfAdded = Index(
    'bookshelf_added',
    'CREATE INDEX bookshelf_added ON bookshelf (added_at DESC)',
  );
  late final ProgressSessions progressSessions = ProgressSessions(this);
  late final ReadingProgress readingProgress = ReadingProgress(this);
  late final Index progressRecent = Index(
    'progress_recent',
    'CREATE INDEX progress_recent ON reading_progress (last_read_at DESC)',
  );
  late final PrefetchChoices prefetchChoices = PrefetchChoices(this);
  late final PrefetchSettings prefetchSettings = PrefetchSettings(this);
  late final LocalBooks localBooks = LocalBooks(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    bookshelf,
    bookshelfAdded,
    progressSessions,
    readingProgress,
    progressRecent,
    prefetchChoices,
    prefetchSettings,
    localBooks,
  ];
}

typedef $BookshelfCreateCompanionBuilder =
    BookshelfCompanion Function({
      required String sourceId,
      required String novelId,
      required String summaryJson,
      required int addedAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $BookshelfUpdateCompanionBuilder =
    BookshelfCompanion Function({
      Value<String> sourceId,
      Value<String> novelId,
      Value<String> summaryJson,
      Value<int> addedAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $BookshelfFilterComposer extends Composer<_$UserDatabase, Bookshelf> {
  $BookshelfFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $BookshelfOrderingComposer extends Composer<_$UserDatabase, Bookshelf> {
  $BookshelfOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $BookshelfAnnotationComposer extends Composer<_$UserDatabase, Bookshelf> {
  $BookshelfAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get novelId =>
      $composableBuilder(column: $table.novelId, builder: (column) => column);

  GeneratedColumn<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $BookshelfTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          Bookshelf,
          BookshelfData,
          $BookshelfFilterComposer,
          $BookshelfOrderingComposer,
          $BookshelfAnnotationComposer,
          $BookshelfCreateCompanionBuilder,
          $BookshelfUpdateCompanionBuilder,
          (
            BookshelfData,
            BaseReferences<_$UserDatabase, Bookshelf, BookshelfData>,
          ),
          BookshelfData,
          PrefetchHooks Function()
        > {
  $BookshelfTableManager(_$UserDatabase db, Bookshelf table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $BookshelfFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $BookshelfOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $BookshelfAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<String> novelId = const Value.absent(),
                Value<String> summaryJson = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookshelfCompanion(
                sourceId: sourceId,
                novelId: novelId,
                summaryJson: summaryJson,
                addedAt: addedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required String novelId,
                required String summaryJson,
                required int addedAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BookshelfCompanion.insert(
                sourceId: sourceId,
                novelId: novelId,
                summaryJson: summaryJson,
                addedAt: addedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $BookshelfProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      Bookshelf,
      BookshelfData,
      $BookshelfFilterComposer,
      $BookshelfOrderingComposer,
      $BookshelfAnnotationComposer,
      $BookshelfCreateCompanionBuilder,
      $BookshelfUpdateCompanionBuilder,
      (BookshelfData, BaseReferences<_$UserDatabase, Bookshelf, BookshelfData>),
      BookshelfData,
      PrefetchHooks Function()
    >;
typedef $ProgressSessionsCreateCompanionBuilder =
    ProgressSessionsCompanion Function({
      required String sourceId,
      required String novelId,
      required int generation,
      Value<int> sequence,
      Value<int> rowid,
    });
typedef $ProgressSessionsUpdateCompanionBuilder =
    ProgressSessionsCompanion Function({
      Value<String> sourceId,
      Value<String> novelId,
      Value<int> generation,
      Value<int> sequence,
      Value<int> rowid,
    });

class $ProgressSessionsFilterComposer
    extends Composer<_$UserDatabase, ProgressSessions> {
  $ProgressSessionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );
}

class $ProgressSessionsOrderingComposer
    extends Composer<_$UserDatabase, ProgressSessions> {
  $ProgressSessionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ProgressSessionsAnnotationComposer
    extends Composer<_$UserDatabase, ProgressSessions> {
  $ProgressSessionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get novelId =>
      $composableBuilder(column: $table.novelId, builder: (column) => column);

  GeneratedColumn<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);
}

class $ProgressSessionsTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          ProgressSessions,
          ProgressSession,
          $ProgressSessionsFilterComposer,
          $ProgressSessionsOrderingComposer,
          $ProgressSessionsAnnotationComposer,
          $ProgressSessionsCreateCompanionBuilder,
          $ProgressSessionsUpdateCompanionBuilder,
          (
            ProgressSession,
            BaseReferences<_$UserDatabase, ProgressSessions, ProgressSession>,
          ),
          ProgressSession,
          PrefetchHooks Function()
        > {
  $ProgressSessionsTableManager(_$UserDatabase db, ProgressSessions table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ProgressSessionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ProgressSessionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ProgressSessionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<String> novelId = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressSessionsCompanion(
                sourceId: sourceId,
                novelId: novelId,
                generation: generation,
                sequence: sequence,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required String novelId,
                required int generation,
                Value<int> sequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressSessionsCompanion.insert(
                sourceId: sourceId,
                novelId: novelId,
                generation: generation,
                sequence: sequence,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ProgressSessionsProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      ProgressSessions,
      ProgressSession,
      $ProgressSessionsFilterComposer,
      $ProgressSessionsOrderingComposer,
      $ProgressSessionsAnnotationComposer,
      $ProgressSessionsCreateCompanionBuilder,
      $ProgressSessionsUpdateCompanionBuilder,
      (
        ProgressSession,
        BaseReferences<_$UserDatabase, ProgressSessions, ProgressSession>,
      ),
      ProgressSession,
      PrefetchHooks Function()
    >;
typedef $ReadingProgressCreateCompanionBuilder =
    ReadingProgressCompanion Function({
      required String sourceId,
      required String novelId,
      required String chapterId,
      required String summaryJson,
      required int chapterOrdinal,
      required String catalogRevision,
      required String contentRevision,
      required String blockKey,
      required int blockIndex,
      required double blockFraction,
      required double chapterFraction,
      required int completed,
      Value<double?> pixelOffset,
      Value<String?> layoutKey,
      required int positionVersion,
      required int lastReadAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $ReadingProgressUpdateCompanionBuilder =
    ReadingProgressCompanion Function({
      Value<String> sourceId,
      Value<String> novelId,
      Value<String> chapterId,
      Value<String> summaryJson,
      Value<int> chapterOrdinal,
      Value<String> catalogRevision,
      Value<String> contentRevision,
      Value<String> blockKey,
      Value<int> blockIndex,
      Value<double> blockFraction,
      Value<double> chapterFraction,
      Value<int> completed,
      Value<double?> pixelOffset,
      Value<String?> layoutKey,
      Value<int> positionVersion,
      Value<int> lastReadAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $ReadingProgressFilterComposer
    extends Composer<_$UserDatabase, ReadingProgress> {
  $ReadingProgressFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterOrdinal => $composableBuilder(
    column: $table.chapterOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get catalogRevision => $composableBuilder(
    column: $table.catalogRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentRevision => $composableBuilder(
    column: $table.contentRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockKey => $composableBuilder(
    column: $table.blockKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get blockFraction => $composableBuilder(
    column: $table.blockFraction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get chapterFraction => $composableBuilder(
    column: $table.chapterFraction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pixelOffset => $composableBuilder(
    column: $table.pixelOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get layoutKey => $composableBuilder(
    column: $table.layoutKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionVersion => $composableBuilder(
    column: $table.positionVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $ReadingProgressOrderingComposer
    extends Composer<_$UserDatabase, ReadingProgress> {
  $ReadingProgressOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterOrdinal => $composableBuilder(
    column: $table.chapterOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get catalogRevision => $composableBuilder(
    column: $table.catalogRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentRevision => $composableBuilder(
    column: $table.contentRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockKey => $composableBuilder(
    column: $table.blockKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get blockFraction => $composableBuilder(
    column: $table.blockFraction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get chapterFraction => $composableBuilder(
    column: $table.chapterFraction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pixelOffset => $composableBuilder(
    column: $table.pixelOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get layoutKey => $composableBuilder(
    column: $table.layoutKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionVersion => $composableBuilder(
    column: $table.positionVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ReadingProgressAnnotationComposer
    extends Composer<_$UserDatabase, ReadingProgress> {
  $ReadingProgressAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get novelId =>
      $composableBuilder(column: $table.novelId, builder: (column) => column);

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterOrdinal => $composableBuilder(
    column: $table.chapterOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get catalogRevision => $composableBuilder(
    column: $table.catalogRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentRevision => $composableBuilder(
    column: $table.contentRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blockKey =>
      $composableBuilder(column: $table.blockKey, builder: (column) => column);

  GeneratedColumn<int> get blockIndex => $composableBuilder(
    column: $table.blockIndex,
    builder: (column) => column,
  );

  GeneratedColumn<double> get blockFraction => $composableBuilder(
    column: $table.blockFraction,
    builder: (column) => column,
  );

  GeneratedColumn<double> get chapterFraction => $composableBuilder(
    column: $table.chapterFraction,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<double> get pixelOffset => $composableBuilder(
    column: $table.pixelOffset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get layoutKey =>
      $composableBuilder(column: $table.layoutKey, builder: (column) => column);

  GeneratedColumn<int> get positionVersion => $composableBuilder(
    column: $table.positionVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $ReadingProgressTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          ReadingProgress,
          ReadingProgressData,
          $ReadingProgressFilterComposer,
          $ReadingProgressOrderingComposer,
          $ReadingProgressAnnotationComposer,
          $ReadingProgressCreateCompanionBuilder,
          $ReadingProgressUpdateCompanionBuilder,
          (
            ReadingProgressData,
            BaseReferences<
              _$UserDatabase,
              ReadingProgress,
              ReadingProgressData
            >,
          ),
          ReadingProgressData,
          PrefetchHooks Function()
        > {
  $ReadingProgressTableManager(_$UserDatabase db, ReadingProgress table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ReadingProgressFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ReadingProgressOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ReadingProgressAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<String> novelId = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<String> summaryJson = const Value.absent(),
                Value<int> chapterOrdinal = const Value.absent(),
                Value<String> catalogRevision = const Value.absent(),
                Value<String> contentRevision = const Value.absent(),
                Value<String> blockKey = const Value.absent(),
                Value<int> blockIndex = const Value.absent(),
                Value<double> blockFraction = const Value.absent(),
                Value<double> chapterFraction = const Value.absent(),
                Value<int> completed = const Value.absent(),
                Value<double?> pixelOffset = const Value.absent(),
                Value<String?> layoutKey = const Value.absent(),
                Value<int> positionVersion = const Value.absent(),
                Value<int> lastReadAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressCompanion(
                sourceId: sourceId,
                novelId: novelId,
                chapterId: chapterId,
                summaryJson: summaryJson,
                chapterOrdinal: chapterOrdinal,
                catalogRevision: catalogRevision,
                contentRevision: contentRevision,
                blockKey: blockKey,
                blockIndex: blockIndex,
                blockFraction: blockFraction,
                chapterFraction: chapterFraction,
                completed: completed,
                pixelOffset: pixelOffset,
                layoutKey: layoutKey,
                positionVersion: positionVersion,
                lastReadAt: lastReadAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required String novelId,
                required String chapterId,
                required String summaryJson,
                required int chapterOrdinal,
                required String catalogRevision,
                required String contentRevision,
                required String blockKey,
                required int blockIndex,
                required double blockFraction,
                required double chapterFraction,
                required int completed,
                Value<double?> pixelOffset = const Value.absent(),
                Value<String?> layoutKey = const Value.absent(),
                required int positionVersion,
                required int lastReadAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressCompanion.insert(
                sourceId: sourceId,
                novelId: novelId,
                chapterId: chapterId,
                summaryJson: summaryJson,
                chapterOrdinal: chapterOrdinal,
                catalogRevision: catalogRevision,
                contentRevision: contentRevision,
                blockKey: blockKey,
                blockIndex: blockIndex,
                blockFraction: blockFraction,
                chapterFraction: chapterFraction,
                completed: completed,
                pixelOffset: pixelOffset,
                layoutKey: layoutKey,
                positionVersion: positionVersion,
                lastReadAt: lastReadAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ReadingProgressProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      ReadingProgress,
      ReadingProgressData,
      $ReadingProgressFilterComposer,
      $ReadingProgressOrderingComposer,
      $ReadingProgressAnnotationComposer,
      $ReadingProgressCreateCompanionBuilder,
      $ReadingProgressUpdateCompanionBuilder,
      (
        ReadingProgressData,
        BaseReferences<_$UserDatabase, ReadingProgress, ReadingProgressData>,
      ),
      ReadingProgressData,
      PrefetchHooks Function()
    >;
typedef $PrefetchChoicesCreateCompanionBuilder =
    PrefetchChoicesCompanion Function({
      required String sourceId,
      required String novelId,
      required String chapterId,
      required String targetId,
      Value<int> rowid,
    });
typedef $PrefetchChoicesUpdateCompanionBuilder =
    PrefetchChoicesCompanion Function({
      Value<String> sourceId,
      Value<String> novelId,
      Value<String> chapterId,
      Value<String> targetId,
      Value<int> rowid,
    });

class $PrefetchChoicesFilterComposer
    extends Composer<_$UserDatabase, PrefetchChoices> {
  $PrefetchChoicesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );
}

class $PrefetchChoicesOrderingComposer
    extends Composer<_$UserDatabase, PrefetchChoices> {
  $PrefetchChoicesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $PrefetchChoicesAnnotationComposer
    extends Composer<_$UserDatabase, PrefetchChoices> {
  $PrefetchChoicesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get novelId =>
      $composableBuilder(column: $table.novelId, builder: (column) => column);

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);
}

class $PrefetchChoicesTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          PrefetchChoices,
          PrefetchChoice,
          $PrefetchChoicesFilterComposer,
          $PrefetchChoicesOrderingComposer,
          $PrefetchChoicesAnnotationComposer,
          $PrefetchChoicesCreateCompanionBuilder,
          $PrefetchChoicesUpdateCompanionBuilder,
          (
            PrefetchChoice,
            BaseReferences<_$UserDatabase, PrefetchChoices, PrefetchChoice>,
          ),
          PrefetchChoice,
          PrefetchHooks Function()
        > {
  $PrefetchChoicesTableManager(_$UserDatabase db, PrefetchChoices table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PrefetchChoicesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PrefetchChoicesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PrefetchChoicesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<String> novelId = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PrefetchChoicesCompanion(
                sourceId: sourceId,
                novelId: novelId,
                chapterId: chapterId,
                targetId: targetId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required String novelId,
                required String chapterId,
                required String targetId,
                Value<int> rowid = const Value.absent(),
              }) => PrefetchChoicesCompanion.insert(
                sourceId: sourceId,
                novelId: novelId,
                chapterId: chapterId,
                targetId: targetId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $PrefetchChoicesProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      PrefetchChoices,
      PrefetchChoice,
      $PrefetchChoicesFilterComposer,
      $PrefetchChoicesOrderingComposer,
      $PrefetchChoicesAnnotationComposer,
      $PrefetchChoicesCreateCompanionBuilder,
      $PrefetchChoicesUpdateCompanionBuilder,
      (
        PrefetchChoice,
        BaseReferences<_$UserDatabase, PrefetchChoices, PrefetchChoice>,
      ),
      PrefetchChoice,
      PrefetchHooks Function()
    >;
typedef $PrefetchSettingsCreateCompanionBuilder =
    PrefetchSettingsCompanion Function({
      Value<int> id,
      required int currentEnabled,
      required int nextEnabled,
    });
typedef $PrefetchSettingsUpdateCompanionBuilder =
    PrefetchSettingsCompanion Function({
      Value<int> id,
      Value<int> currentEnabled,
      Value<int> nextEnabled,
    });

class $PrefetchSettingsFilterComposer
    extends Composer<_$UserDatabase, PrefetchSettings> {
  $PrefetchSettingsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentEnabled => $composableBuilder(
    column: $table.currentEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextEnabled => $composableBuilder(
    column: $table.nextEnabled,
    builder: (column) => ColumnFilters(column),
  );
}

class $PrefetchSettingsOrderingComposer
    extends Composer<_$UserDatabase, PrefetchSettings> {
  $PrefetchSettingsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentEnabled => $composableBuilder(
    column: $table.currentEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextEnabled => $composableBuilder(
    column: $table.nextEnabled,
    builder: (column) => ColumnOrderings(column),
  );
}

class $PrefetchSettingsAnnotationComposer
    extends Composer<_$UserDatabase, PrefetchSettings> {
  $PrefetchSettingsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get currentEnabled => $composableBuilder(
    column: $table.currentEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextEnabled => $composableBuilder(
    column: $table.nextEnabled,
    builder: (column) => column,
  );
}

class $PrefetchSettingsTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          PrefetchSettings,
          PrefetchSetting,
          $PrefetchSettingsFilterComposer,
          $PrefetchSettingsOrderingComposer,
          $PrefetchSettingsAnnotationComposer,
          $PrefetchSettingsCreateCompanionBuilder,
          $PrefetchSettingsUpdateCompanionBuilder,
          (
            PrefetchSetting,
            BaseReferences<_$UserDatabase, PrefetchSettings, PrefetchSetting>,
          ),
          PrefetchSetting,
          PrefetchHooks Function()
        > {
  $PrefetchSettingsTableManager(_$UserDatabase db, PrefetchSettings table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PrefetchSettingsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PrefetchSettingsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PrefetchSettingsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> currentEnabled = const Value.absent(),
                Value<int> nextEnabled = const Value.absent(),
              }) => PrefetchSettingsCompanion(
                id: id,
                currentEnabled: currentEnabled,
                nextEnabled: nextEnabled,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int currentEnabled,
                required int nextEnabled,
              }) => PrefetchSettingsCompanion.insert(
                id: id,
                currentEnabled: currentEnabled,
                nextEnabled: nextEnabled,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $PrefetchSettingsProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      PrefetchSettings,
      PrefetchSetting,
      $PrefetchSettingsFilterComposer,
      $PrefetchSettingsOrderingComposer,
      $PrefetchSettingsAnnotationComposer,
      $PrefetchSettingsCreateCompanionBuilder,
      $PrefetchSettingsUpdateCompanionBuilder,
      (
        PrefetchSetting,
        BaseReferences<_$UserDatabase, PrefetchSettings, PrefetchSetting>,
      ),
      PrefetchSetting,
      PrefetchHooks Function()
    >;
typedef $LocalBooksCreateCompanionBuilder =
    LocalBooksCompanion Function({
      required String digest,
      required String format,
      required String title,
      required int importedAt,
      required String manifestHash,
      Value<int> rowid,
    });
typedef $LocalBooksUpdateCompanionBuilder =
    LocalBooksCompanion Function({
      Value<String> digest,
      Value<String> format,
      Value<String> title,
      Value<int> importedAt,
      Value<String> manifestHash,
      Value<int> rowid,
    });

class $LocalBooksFilterComposer extends Composer<_$UserDatabase, LocalBooks> {
  $LocalBooksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestHash => $composableBuilder(
    column: $table.manifestHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $LocalBooksOrderingComposer extends Composer<_$UserDatabase, LocalBooks> {
  $LocalBooksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get digest => $composableBuilder(
    column: $table.digest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestHash => $composableBuilder(
    column: $table.manifestHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $LocalBooksAnnotationComposer
    extends Composer<_$UserDatabase, LocalBooks> {
  $LocalBooksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get digest =>
      $composableBuilder(column: $table.digest, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manifestHash => $composableBuilder(
    column: $table.manifestHash,
    builder: (column) => column,
  );
}

class $LocalBooksTableManager
    extends
        RootTableManager<
          _$UserDatabase,
          LocalBooks,
          LocalBook,
          $LocalBooksFilterComposer,
          $LocalBooksOrderingComposer,
          $LocalBooksAnnotationComposer,
          $LocalBooksCreateCompanionBuilder,
          $LocalBooksUpdateCompanionBuilder,
          (LocalBook, BaseReferences<_$UserDatabase, LocalBooks, LocalBook>),
          LocalBook,
          PrefetchHooks Function()
        > {
  $LocalBooksTableManager(_$UserDatabase db, LocalBooks table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LocalBooksFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LocalBooksOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LocalBooksAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> digest = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> importedAt = const Value.absent(),
                Value<String> manifestHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalBooksCompanion(
                digest: digest,
                format: format,
                title: title,
                importedAt: importedAt,
                manifestHash: manifestHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String digest,
                required String format,
                required String title,
                required int importedAt,
                required String manifestHash,
                Value<int> rowid = const Value.absent(),
              }) => LocalBooksCompanion.insert(
                digest: digest,
                format: format,
                title: title,
                importedAt: importedAt,
                manifestHash: manifestHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $LocalBooksProcessedTableManager =
    ProcessedTableManager<
      _$UserDatabase,
      LocalBooks,
      LocalBook,
      $LocalBooksFilterComposer,
      $LocalBooksOrderingComposer,
      $LocalBooksAnnotationComposer,
      $LocalBooksCreateCompanionBuilder,
      $LocalBooksUpdateCompanionBuilder,
      (LocalBook, BaseReferences<_$UserDatabase, LocalBooks, LocalBook>),
      LocalBook,
      PrefetchHooks Function()
    >;

class $UserDatabaseManager {
  final _$UserDatabase _db;
  $UserDatabaseManager(this._db);
  $BookshelfTableManager get bookshelf =>
      $BookshelfTableManager(_db, _db.bookshelf);
  $ProgressSessionsTableManager get progressSessions =>
      $ProgressSessionsTableManager(_db, _db.progressSessions);
  $ReadingProgressTableManager get readingProgress =>
      $ReadingProgressTableManager(_db, _db.readingProgress);
  $PrefetchChoicesTableManager get prefetchChoices =>
      $PrefetchChoicesTableManager(_db, _db.prefetchChoices);
  $PrefetchSettingsTableManager get prefetchSettings =>
      $PrefetchSettingsTableManager(_db, _db.prefetchSettings);
  $LocalBooksTableManager get localBooks =>
      $LocalBooksTableManager(_db, _db.localBooks);
}
