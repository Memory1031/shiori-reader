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

class $UserDatabaseManager {
  final _$UserDatabase _db;
  $UserDatabaseManager(this._db);
  $BookshelfTableManager get bookshelf =>
      $BookshelfTableManager(_db, _db.bookshelf);
  $ProgressSessionsTableManager get progressSessions =>
      $ProgressSessionsTableManager(_db, _db.progressSessions);
  $ReadingProgressTableManager get readingProgress =>
      $ReadingProgressTableManager(_db, _db.readingProgress);
}
