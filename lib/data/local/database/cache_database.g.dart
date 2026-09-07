// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class NovelCache extends Table with TableInfo<NovelCache, NovelCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NovelCache(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _codecVersionMeta = const VerificationMeta(
    'codecVersion',
  );
  late final GeneratedColumn<int> codecVersion = GeneratedColumn<int>(
    'codec_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (codec_version >= 1)',
  );
  static const VerificationMeta _parserVersionMeta = const VerificationMeta(
    'parserVersion',
  );
  late final GeneratedColumn<int> parserVersion = GeneratedColumn<int>(
    'parser_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (parser_version >= 1)',
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lastAccessAtMeta = const VerificationMeta(
    'lastAccessAt',
  );
  late final GeneratedColumn<int> lastAccessAt = GeneratedColumn<int>(
    'last_access_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (byte_size >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    novelId,
    payload,
    codecVersion,
    parserVersion,
    fetchedAt,
    expiresAt,
    lastAccessAt,
    byteSize,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelCacheData> instance, {
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
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('codec_version')) {
      context.handle(
        _codecVersionMeta,
        codecVersion.isAcceptableOrUnknown(
          data['codec_version']!,
          _codecVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_codecVersionMeta);
    }
    if (data.containsKey('parser_version')) {
      context.handle(
        _parserVersionMeta,
        parserVersion.isAcceptableOrUnknown(
          data['parser_version']!,
          _parserVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parserVersionMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('last_access_at')) {
      context.handle(
        _lastAccessAtMeta,
        lastAccessAt.isAcceptableOrUnknown(
          data['last_access_at']!,
          _lastAccessAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessAtMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, novelId};
  @override
  NovelCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelCacheData(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      novelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}novel_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      codecVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}codec_version'],
      )!,
      parserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_version'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      ),
      lastAccessAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_access_at'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
    );
  }

  @override
  NovelCache createAlias(String alias) {
    return NovelCache(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(source_id, novel_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class NovelCacheData extends DataClass implements Insertable<NovelCacheData> {
  final String sourceId;
  final String novelId;
  final String payload;
  final int codecVersion;
  final int parserVersion;
  final int fetchedAt;
  final int? expiresAt;
  final int lastAccessAt;
  final int byteSize;
  const NovelCacheData({
    required this.sourceId,
    required this.novelId,
    required this.payload,
    required this.codecVersion,
    required this.parserVersion,
    required this.fetchedAt,
    this.expiresAt,
    required this.lastAccessAt,
    required this.byteSize,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['novel_id'] = Variable<String>(novelId);
    map['payload'] = Variable<String>(payload);
    map['codec_version'] = Variable<int>(codecVersion);
    map['parser_version'] = Variable<int>(parserVersion);
    map['fetched_at'] = Variable<int>(fetchedAt);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(expiresAt);
    }
    map['last_access_at'] = Variable<int>(lastAccessAt);
    map['byte_size'] = Variable<int>(byteSize);
    return map;
  }

  NovelCacheCompanion toCompanion(bool nullToAbsent) {
    return NovelCacheCompanion(
      sourceId: Value(sourceId),
      novelId: Value(novelId),
      payload: Value(payload),
      codecVersion: Value(codecVersion),
      parserVersion: Value(parserVersion),
      fetchedAt: Value(fetchedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      lastAccessAt: Value(lastAccessAt),
      byteSize: Value(byteSize),
    );
  }

  factory NovelCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelCacheData(
      sourceId: serializer.fromJson<String>(json['source_id']),
      novelId: serializer.fromJson<String>(json['novel_id']),
      payload: serializer.fromJson<String>(json['payload']),
      codecVersion: serializer.fromJson<int>(json['codec_version']),
      parserVersion: serializer.fromJson<int>(json['parser_version']),
      fetchedAt: serializer.fromJson<int>(json['fetched_at']),
      expiresAt: serializer.fromJson<int?>(json['expires_at']),
      lastAccessAt: serializer.fromJson<int>(json['last_access_at']),
      byteSize: serializer.fromJson<int>(json['byte_size']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_id': serializer.toJson<String>(sourceId),
      'novel_id': serializer.toJson<String>(novelId),
      'payload': serializer.toJson<String>(payload),
      'codec_version': serializer.toJson<int>(codecVersion),
      'parser_version': serializer.toJson<int>(parserVersion),
      'fetched_at': serializer.toJson<int>(fetchedAt),
      'expires_at': serializer.toJson<int?>(expiresAt),
      'last_access_at': serializer.toJson<int>(lastAccessAt),
      'byte_size': serializer.toJson<int>(byteSize),
    };
  }

  NovelCacheData copyWith({
    String? sourceId,
    String? novelId,
    String? payload,
    int? codecVersion,
    int? parserVersion,
    int? fetchedAt,
    Value<int?> expiresAt = const Value.absent(),
    int? lastAccessAt,
    int? byteSize,
  }) => NovelCacheData(
    sourceId: sourceId ?? this.sourceId,
    novelId: novelId ?? this.novelId,
    payload: payload ?? this.payload,
    codecVersion: codecVersion ?? this.codecVersion,
    parserVersion: parserVersion ?? this.parserVersion,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    lastAccessAt: lastAccessAt ?? this.lastAccessAt,
    byteSize: byteSize ?? this.byteSize,
  );
  NovelCacheData copyWithCompanion(NovelCacheCompanion data) {
    return NovelCacheData(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      novelId: data.novelId.present ? data.novelId.value : this.novelId,
      payload: data.payload.present ? data.payload.value : this.payload,
      codecVersion: data.codecVersion.present
          ? data.codecVersion.value
          : this.codecVersion,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      lastAccessAt: data.lastAccessAt.present
          ? data.lastAccessAt.value
          : this.lastAccessAt,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelCacheData(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('payload: $payload, ')
          ..write('codecVersion: $codecVersion, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('byteSize: $byteSize')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    novelId,
    payload,
    codecVersion,
    parserVersion,
    fetchedAt,
    expiresAt,
    lastAccessAt,
    byteSize,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelCacheData &&
          other.sourceId == this.sourceId &&
          other.novelId == this.novelId &&
          other.payload == this.payload &&
          other.codecVersion == this.codecVersion &&
          other.parserVersion == this.parserVersion &&
          other.fetchedAt == this.fetchedAt &&
          other.expiresAt == this.expiresAt &&
          other.lastAccessAt == this.lastAccessAt &&
          other.byteSize == this.byteSize);
}

class NovelCacheCompanion extends UpdateCompanion<NovelCacheData> {
  final Value<String> sourceId;
  final Value<String> novelId;
  final Value<String> payload;
  final Value<int> codecVersion;
  final Value<int> parserVersion;
  final Value<int> fetchedAt;
  final Value<int?> expiresAt;
  final Value<int> lastAccessAt;
  final Value<int> byteSize;
  final Value<int> rowid;
  const NovelCacheCompanion({
    this.sourceId = const Value.absent(),
    this.novelId = const Value.absent(),
    this.payload = const Value.absent(),
    this.codecVersion = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.lastAccessAt = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelCacheCompanion.insert({
    required String sourceId,
    required String novelId,
    required String payload,
    required int codecVersion,
    required int parserVersion,
    required int fetchedAt,
    this.expiresAt = const Value.absent(),
    required int lastAccessAt,
    required int byteSize,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       novelId = Value(novelId),
       payload = Value(payload),
       codecVersion = Value(codecVersion),
       parserVersion = Value(parserVersion),
       fetchedAt = Value(fetchedAt),
       lastAccessAt = Value(lastAccessAt),
       byteSize = Value(byteSize);
  static Insertable<NovelCacheData> custom({
    Expression<String>? sourceId,
    Expression<String>? novelId,
    Expression<String>? payload,
    Expression<int>? codecVersion,
    Expression<int>? parserVersion,
    Expression<int>? fetchedAt,
    Expression<int>? expiresAt,
    Expression<int>? lastAccessAt,
    Expression<int>? byteSize,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (novelId != null) 'novel_id': novelId,
      if (payload != null) 'payload': payload,
      if (codecVersion != null) 'codec_version': codecVersion,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (lastAccessAt != null) 'last_access_at': lastAccessAt,
      if (byteSize != null) 'byte_size': byteSize,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelCacheCompanion copyWith({
    Value<String>? sourceId,
    Value<String>? novelId,
    Value<String>? payload,
    Value<int>? codecVersion,
    Value<int>? parserVersion,
    Value<int>? fetchedAt,
    Value<int?>? expiresAt,
    Value<int>? lastAccessAt,
    Value<int>? byteSize,
    Value<int>? rowid,
  }) {
    return NovelCacheCompanion(
      sourceId: sourceId ?? this.sourceId,
      novelId: novelId ?? this.novelId,
      payload: payload ?? this.payload,
      codecVersion: codecVersion ?? this.codecVersion,
      parserVersion: parserVersion ?? this.parserVersion,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastAccessAt: lastAccessAt ?? this.lastAccessAt,
      byteSize: byteSize ?? this.byteSize,
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
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (codecVersion.present) {
      map['codec_version'] = Variable<int>(codecVersion.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (lastAccessAt.present) {
      map['last_access_at'] = Variable<int>(lastAccessAt.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelCacheCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('payload: $payload, ')
          ..write('codecVersion: $codecVersion, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('byteSize: $byteSize, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class CatalogCache extends Table
    with TableInfo<CatalogCache, CatalogCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CatalogCache(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _codecVersionMeta = const VerificationMeta(
    'codecVersion',
  );
  late final GeneratedColumn<int> codecVersion = GeneratedColumn<int>(
    'codec_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (codec_version >= 1)',
  );
  static const VerificationMeta _parserVersionMeta = const VerificationMeta(
    'parserVersion',
  );
  late final GeneratedColumn<int> parserVersion = GeneratedColumn<int>(
    'parser_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (parser_version >= 1)',
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lastAccessAtMeta = const VerificationMeta(
    'lastAccessAt',
  );
  late final GeneratedColumn<int> lastAccessAt = GeneratedColumn<int>(
    'last_access_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (byte_size >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    novelId,
    payload,
    codecVersion,
    parserVersion,
    fetchedAt,
    expiresAt,
    lastAccessAt,
    byteSize,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogCacheData> instance, {
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
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('codec_version')) {
      context.handle(
        _codecVersionMeta,
        codecVersion.isAcceptableOrUnknown(
          data['codec_version']!,
          _codecVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_codecVersionMeta);
    }
    if (data.containsKey('parser_version')) {
      context.handle(
        _parserVersionMeta,
        parserVersion.isAcceptableOrUnknown(
          data['parser_version']!,
          _parserVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parserVersionMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('last_access_at')) {
      context.handle(
        _lastAccessAtMeta,
        lastAccessAt.isAcceptableOrUnknown(
          data['last_access_at']!,
          _lastAccessAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessAtMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, novelId};
  @override
  CatalogCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogCacheData(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      novelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}novel_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      codecVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}codec_version'],
      )!,
      parserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_version'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      ),
      lastAccessAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_access_at'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
    );
  }

  @override
  CatalogCache createAlias(String alias) {
    return CatalogCache(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(source_id, novel_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class CatalogCacheData extends DataClass
    implements Insertable<CatalogCacheData> {
  final String sourceId;
  final String novelId;
  final String payload;
  final int codecVersion;
  final int parserVersion;
  final int fetchedAt;
  final int? expiresAt;
  final int lastAccessAt;
  final int byteSize;
  const CatalogCacheData({
    required this.sourceId,
    required this.novelId,
    required this.payload,
    required this.codecVersion,
    required this.parserVersion,
    required this.fetchedAt,
    this.expiresAt,
    required this.lastAccessAt,
    required this.byteSize,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['novel_id'] = Variable<String>(novelId);
    map['payload'] = Variable<String>(payload);
    map['codec_version'] = Variable<int>(codecVersion);
    map['parser_version'] = Variable<int>(parserVersion);
    map['fetched_at'] = Variable<int>(fetchedAt);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(expiresAt);
    }
    map['last_access_at'] = Variable<int>(lastAccessAt);
    map['byte_size'] = Variable<int>(byteSize);
    return map;
  }

  CatalogCacheCompanion toCompanion(bool nullToAbsent) {
    return CatalogCacheCompanion(
      sourceId: Value(sourceId),
      novelId: Value(novelId),
      payload: Value(payload),
      codecVersion: Value(codecVersion),
      parserVersion: Value(parserVersion),
      fetchedAt: Value(fetchedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      lastAccessAt: Value(lastAccessAt),
      byteSize: Value(byteSize),
    );
  }

  factory CatalogCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogCacheData(
      sourceId: serializer.fromJson<String>(json['source_id']),
      novelId: serializer.fromJson<String>(json['novel_id']),
      payload: serializer.fromJson<String>(json['payload']),
      codecVersion: serializer.fromJson<int>(json['codec_version']),
      parserVersion: serializer.fromJson<int>(json['parser_version']),
      fetchedAt: serializer.fromJson<int>(json['fetched_at']),
      expiresAt: serializer.fromJson<int?>(json['expires_at']),
      lastAccessAt: serializer.fromJson<int>(json['last_access_at']),
      byteSize: serializer.fromJson<int>(json['byte_size']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_id': serializer.toJson<String>(sourceId),
      'novel_id': serializer.toJson<String>(novelId),
      'payload': serializer.toJson<String>(payload),
      'codec_version': serializer.toJson<int>(codecVersion),
      'parser_version': serializer.toJson<int>(parserVersion),
      'fetched_at': serializer.toJson<int>(fetchedAt),
      'expires_at': serializer.toJson<int?>(expiresAt),
      'last_access_at': serializer.toJson<int>(lastAccessAt),
      'byte_size': serializer.toJson<int>(byteSize),
    };
  }

  CatalogCacheData copyWith({
    String? sourceId,
    String? novelId,
    String? payload,
    int? codecVersion,
    int? parserVersion,
    int? fetchedAt,
    Value<int?> expiresAt = const Value.absent(),
    int? lastAccessAt,
    int? byteSize,
  }) => CatalogCacheData(
    sourceId: sourceId ?? this.sourceId,
    novelId: novelId ?? this.novelId,
    payload: payload ?? this.payload,
    codecVersion: codecVersion ?? this.codecVersion,
    parserVersion: parserVersion ?? this.parserVersion,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    lastAccessAt: lastAccessAt ?? this.lastAccessAt,
    byteSize: byteSize ?? this.byteSize,
  );
  CatalogCacheData copyWithCompanion(CatalogCacheCompanion data) {
    return CatalogCacheData(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      novelId: data.novelId.present ? data.novelId.value : this.novelId,
      payload: data.payload.present ? data.payload.value : this.payload,
      codecVersion: data.codecVersion.present
          ? data.codecVersion.value
          : this.codecVersion,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      lastAccessAt: data.lastAccessAt.present
          ? data.lastAccessAt.value
          : this.lastAccessAt,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogCacheData(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('payload: $payload, ')
          ..write('codecVersion: $codecVersion, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('byteSize: $byteSize')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    novelId,
    payload,
    codecVersion,
    parserVersion,
    fetchedAt,
    expiresAt,
    lastAccessAt,
    byteSize,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogCacheData &&
          other.sourceId == this.sourceId &&
          other.novelId == this.novelId &&
          other.payload == this.payload &&
          other.codecVersion == this.codecVersion &&
          other.parserVersion == this.parserVersion &&
          other.fetchedAt == this.fetchedAt &&
          other.expiresAt == this.expiresAt &&
          other.lastAccessAt == this.lastAccessAt &&
          other.byteSize == this.byteSize);
}

class CatalogCacheCompanion extends UpdateCompanion<CatalogCacheData> {
  final Value<String> sourceId;
  final Value<String> novelId;
  final Value<String> payload;
  final Value<int> codecVersion;
  final Value<int> parserVersion;
  final Value<int> fetchedAt;
  final Value<int?> expiresAt;
  final Value<int> lastAccessAt;
  final Value<int> byteSize;
  final Value<int> rowid;
  const CatalogCacheCompanion({
    this.sourceId = const Value.absent(),
    this.novelId = const Value.absent(),
    this.payload = const Value.absent(),
    this.codecVersion = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.lastAccessAt = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogCacheCompanion.insert({
    required String sourceId,
    required String novelId,
    required String payload,
    required int codecVersion,
    required int parserVersion,
    required int fetchedAt,
    this.expiresAt = const Value.absent(),
    required int lastAccessAt,
    required int byteSize,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       novelId = Value(novelId),
       payload = Value(payload),
       codecVersion = Value(codecVersion),
       parserVersion = Value(parserVersion),
       fetchedAt = Value(fetchedAt),
       lastAccessAt = Value(lastAccessAt),
       byteSize = Value(byteSize);
  static Insertable<CatalogCacheData> custom({
    Expression<String>? sourceId,
    Expression<String>? novelId,
    Expression<String>? payload,
    Expression<int>? codecVersion,
    Expression<int>? parserVersion,
    Expression<int>? fetchedAt,
    Expression<int>? expiresAt,
    Expression<int>? lastAccessAt,
    Expression<int>? byteSize,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (novelId != null) 'novel_id': novelId,
      if (payload != null) 'payload': payload,
      if (codecVersion != null) 'codec_version': codecVersion,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (lastAccessAt != null) 'last_access_at': lastAccessAt,
      if (byteSize != null) 'byte_size': byteSize,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogCacheCompanion copyWith({
    Value<String>? sourceId,
    Value<String>? novelId,
    Value<String>? payload,
    Value<int>? codecVersion,
    Value<int>? parserVersion,
    Value<int>? fetchedAt,
    Value<int?>? expiresAt,
    Value<int>? lastAccessAt,
    Value<int>? byteSize,
    Value<int>? rowid,
  }) {
    return CatalogCacheCompanion(
      sourceId: sourceId ?? this.sourceId,
      novelId: novelId ?? this.novelId,
      payload: payload ?? this.payload,
      codecVersion: codecVersion ?? this.codecVersion,
      parserVersion: parserVersion ?? this.parserVersion,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastAccessAt: lastAccessAt ?? this.lastAccessAt,
      byteSize: byteSize ?? this.byteSize,
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
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (codecVersion.present) {
      map['codec_version'] = Variable<int>(codecVersion.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (lastAccessAt.present) {
      map['last_access_at'] = Variable<int>(lastAccessAt.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogCacheCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('payload: $payload, ')
          ..write('codecVersion: $codecVersion, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('byteSize: $byteSize, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ChapterCache extends Table
    with TableInfo<ChapterCache, ChapterCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ChapterCache(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _codecVersionMeta = const VerificationMeta(
    'codecVersion',
  );
  late final GeneratedColumn<int> codecVersion = GeneratedColumn<int>(
    'codec_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (codec_version >= 1)',
  );
  static const VerificationMeta _parserVersionMeta = const VerificationMeta(
    'parserVersion',
  );
  late final GeneratedColumn<int> parserVersion = GeneratedColumn<int>(
    'parser_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (parser_version >= 1)',
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lastAccessAtMeta = const VerificationMeta(
    'lastAccessAt',
  );
  late final GeneratedColumn<int> lastAccessAt = GeneratedColumn<int>(
    'last_access_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (byte_size >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    novelId,
    chapterId,
    payload,
    codecVersion,
    parserVersion,
    fetchedAt,
    expiresAt,
    lastAccessAt,
    byteSize,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapter_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChapterCacheData> instance, {
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
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('codec_version')) {
      context.handle(
        _codecVersionMeta,
        codecVersion.isAcceptableOrUnknown(
          data['codec_version']!,
          _codecVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_codecVersionMeta);
    }
    if (data.containsKey('parser_version')) {
      context.handle(
        _parserVersionMeta,
        parserVersion.isAcceptableOrUnknown(
          data['parser_version']!,
          _parserVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parserVersionMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('last_access_at')) {
      context.handle(
        _lastAccessAtMeta,
        lastAccessAt.isAcceptableOrUnknown(
          data['last_access_at']!,
          _lastAccessAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessAtMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, novelId, chapterId};
  @override
  ChapterCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChapterCacheData(
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
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      codecVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}codec_version'],
      )!,
      parserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_version'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      ),
      lastAccessAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_access_at'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
    );
  }

  @override
  ChapterCache createAlias(String alias) {
    return ChapterCache(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(source_id, novel_id, chapter_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ChapterCacheData extends DataClass
    implements Insertable<ChapterCacheData> {
  final String sourceId;
  final String novelId;
  final String chapterId;
  final String payload;
  final int codecVersion;
  final int parserVersion;
  final int fetchedAt;
  final int? expiresAt;
  final int lastAccessAt;
  final int byteSize;
  const ChapterCacheData({
    required this.sourceId,
    required this.novelId,
    required this.chapterId,
    required this.payload,
    required this.codecVersion,
    required this.parserVersion,
    required this.fetchedAt,
    this.expiresAt,
    required this.lastAccessAt,
    required this.byteSize,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['novel_id'] = Variable<String>(novelId);
    map['chapter_id'] = Variable<String>(chapterId);
    map['payload'] = Variable<String>(payload);
    map['codec_version'] = Variable<int>(codecVersion);
    map['parser_version'] = Variable<int>(parserVersion);
    map['fetched_at'] = Variable<int>(fetchedAt);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(expiresAt);
    }
    map['last_access_at'] = Variable<int>(lastAccessAt);
    map['byte_size'] = Variable<int>(byteSize);
    return map;
  }

  ChapterCacheCompanion toCompanion(bool nullToAbsent) {
    return ChapterCacheCompanion(
      sourceId: Value(sourceId),
      novelId: Value(novelId),
      chapterId: Value(chapterId),
      payload: Value(payload),
      codecVersion: Value(codecVersion),
      parserVersion: Value(parserVersion),
      fetchedAt: Value(fetchedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      lastAccessAt: Value(lastAccessAt),
      byteSize: Value(byteSize),
    );
  }

  factory ChapterCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChapterCacheData(
      sourceId: serializer.fromJson<String>(json['source_id']),
      novelId: serializer.fromJson<String>(json['novel_id']),
      chapterId: serializer.fromJson<String>(json['chapter_id']),
      payload: serializer.fromJson<String>(json['payload']),
      codecVersion: serializer.fromJson<int>(json['codec_version']),
      parserVersion: serializer.fromJson<int>(json['parser_version']),
      fetchedAt: serializer.fromJson<int>(json['fetched_at']),
      expiresAt: serializer.fromJson<int?>(json['expires_at']),
      lastAccessAt: serializer.fromJson<int>(json['last_access_at']),
      byteSize: serializer.fromJson<int>(json['byte_size']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source_id': serializer.toJson<String>(sourceId),
      'novel_id': serializer.toJson<String>(novelId),
      'chapter_id': serializer.toJson<String>(chapterId),
      'payload': serializer.toJson<String>(payload),
      'codec_version': serializer.toJson<int>(codecVersion),
      'parser_version': serializer.toJson<int>(parserVersion),
      'fetched_at': serializer.toJson<int>(fetchedAt),
      'expires_at': serializer.toJson<int?>(expiresAt),
      'last_access_at': serializer.toJson<int>(lastAccessAt),
      'byte_size': serializer.toJson<int>(byteSize),
    };
  }

  ChapterCacheData copyWith({
    String? sourceId,
    String? novelId,
    String? chapterId,
    String? payload,
    int? codecVersion,
    int? parserVersion,
    int? fetchedAt,
    Value<int?> expiresAt = const Value.absent(),
    int? lastAccessAt,
    int? byteSize,
  }) => ChapterCacheData(
    sourceId: sourceId ?? this.sourceId,
    novelId: novelId ?? this.novelId,
    chapterId: chapterId ?? this.chapterId,
    payload: payload ?? this.payload,
    codecVersion: codecVersion ?? this.codecVersion,
    parserVersion: parserVersion ?? this.parserVersion,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    lastAccessAt: lastAccessAt ?? this.lastAccessAt,
    byteSize: byteSize ?? this.byteSize,
  );
  ChapterCacheData copyWithCompanion(ChapterCacheCompanion data) {
    return ChapterCacheData(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      novelId: data.novelId.present ? data.novelId.value : this.novelId,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      payload: data.payload.present ? data.payload.value : this.payload,
      codecVersion: data.codecVersion.present
          ? data.codecVersion.value
          : this.codecVersion,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      lastAccessAt: data.lastAccessAt.present
          ? data.lastAccessAt.value
          : this.lastAccessAt,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChapterCacheData(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('chapterId: $chapterId, ')
          ..write('payload: $payload, ')
          ..write('codecVersion: $codecVersion, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('byteSize: $byteSize')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    novelId,
    chapterId,
    payload,
    codecVersion,
    parserVersion,
    fetchedAt,
    expiresAt,
    lastAccessAt,
    byteSize,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChapterCacheData &&
          other.sourceId == this.sourceId &&
          other.novelId == this.novelId &&
          other.chapterId == this.chapterId &&
          other.payload == this.payload &&
          other.codecVersion == this.codecVersion &&
          other.parserVersion == this.parserVersion &&
          other.fetchedAt == this.fetchedAt &&
          other.expiresAt == this.expiresAt &&
          other.lastAccessAt == this.lastAccessAt &&
          other.byteSize == this.byteSize);
}

class ChapterCacheCompanion extends UpdateCompanion<ChapterCacheData> {
  final Value<String> sourceId;
  final Value<String> novelId;
  final Value<String> chapterId;
  final Value<String> payload;
  final Value<int> codecVersion;
  final Value<int> parserVersion;
  final Value<int> fetchedAt;
  final Value<int?> expiresAt;
  final Value<int> lastAccessAt;
  final Value<int> byteSize;
  final Value<int> rowid;
  const ChapterCacheCompanion({
    this.sourceId = const Value.absent(),
    this.novelId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.payload = const Value.absent(),
    this.codecVersion = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.lastAccessAt = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChapterCacheCompanion.insert({
    required String sourceId,
    required String novelId,
    required String chapterId,
    required String payload,
    required int codecVersion,
    required int parserVersion,
    required int fetchedAt,
    this.expiresAt = const Value.absent(),
    required int lastAccessAt,
    required int byteSize,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       novelId = Value(novelId),
       chapterId = Value(chapterId),
       payload = Value(payload),
       codecVersion = Value(codecVersion),
       parserVersion = Value(parserVersion),
       fetchedAt = Value(fetchedAt),
       lastAccessAt = Value(lastAccessAt),
       byteSize = Value(byteSize);
  static Insertable<ChapterCacheData> custom({
    Expression<String>? sourceId,
    Expression<String>? novelId,
    Expression<String>? chapterId,
    Expression<String>? payload,
    Expression<int>? codecVersion,
    Expression<int>? parserVersion,
    Expression<int>? fetchedAt,
    Expression<int>? expiresAt,
    Expression<int>? lastAccessAt,
    Expression<int>? byteSize,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (novelId != null) 'novel_id': novelId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (payload != null) 'payload': payload,
      if (codecVersion != null) 'codec_version': codecVersion,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (lastAccessAt != null) 'last_access_at': lastAccessAt,
      if (byteSize != null) 'byte_size': byteSize,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChapterCacheCompanion copyWith({
    Value<String>? sourceId,
    Value<String>? novelId,
    Value<String>? chapterId,
    Value<String>? payload,
    Value<int>? codecVersion,
    Value<int>? parserVersion,
    Value<int>? fetchedAt,
    Value<int?>? expiresAt,
    Value<int>? lastAccessAt,
    Value<int>? byteSize,
    Value<int>? rowid,
  }) {
    return ChapterCacheCompanion(
      sourceId: sourceId ?? this.sourceId,
      novelId: novelId ?? this.novelId,
      chapterId: chapterId ?? this.chapterId,
      payload: payload ?? this.payload,
      codecVersion: codecVersion ?? this.codecVersion,
      parserVersion: parserVersion ?? this.parserVersion,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastAccessAt: lastAccessAt ?? this.lastAccessAt,
      byteSize: byteSize ?? this.byteSize,
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
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (codecVersion.present) {
      map['codec_version'] = Variable<int>(codecVersion.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (lastAccessAt.present) {
      map['last_access_at'] = Variable<int>(lastAccessAt.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChapterCacheCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('chapterId: $chapterId, ')
          ..write('payload: $payload, ')
          ..write('codecVersion: $codecVersion, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('byteSize: $byteSize, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ImageCache extends Table with TableInfo<ImageCache, ImageCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ImageCache(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _refJsonMeta = const VerificationMeta(
    'refJson',
  );
  late final GeneratedColumn<String> refJson = GeneratedColumn<String>(
    'ref_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  late final GeneratedColumn<String> checksum = GeneratedColumn<String>(
    'checksum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (byte_size > 0)',
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lastAccessAtMeta = const VerificationMeta(
    'lastAccessAt',
  );
  late final GeneratedColumn<int> lastAccessAt = GeneratedColumn<int>(
    'last_access_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    cacheKey,
    refJson,
    fileName,
    checksum,
    byteSize,
    format,
    fetchedAt,
    lastAccessAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'image_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImageCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('ref_json')) {
      context.handle(
        _refJsonMeta,
        refJson.isAcceptableOrUnknown(data['ref_json']!, _refJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_refJsonMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    } else if (isInserting) {
      context.missing(_checksumMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('last_access_at')) {
      context.handle(
        _lastAccessAtMeta,
        lastAccessAt.isAcceptableOrUnknown(
          data['last_access_at']!,
          _lastAccessAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  ImageCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImageCacheData(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      refJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_json'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      lastAccessAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_access_at'],
      )!,
    );
  }

  @override
  ImageCache createAlias(String alias) {
    return ImageCache(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class ImageCacheData extends DataClass implements Insertable<ImageCacheData> {
  final String cacheKey;
  final String refJson;
  final String fileName;
  final String checksum;
  final int byteSize;
  final String format;
  final int fetchedAt;
  final int lastAccessAt;
  const ImageCacheData({
    required this.cacheKey,
    required this.refJson,
    required this.fileName,
    required this.checksum,
    required this.byteSize,
    required this.format,
    required this.fetchedAt,
    required this.lastAccessAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['ref_json'] = Variable<String>(refJson);
    map['file_name'] = Variable<String>(fileName);
    map['checksum'] = Variable<String>(checksum);
    map['byte_size'] = Variable<int>(byteSize);
    map['format'] = Variable<String>(format);
    map['fetched_at'] = Variable<int>(fetchedAt);
    map['last_access_at'] = Variable<int>(lastAccessAt);
    return map;
  }

  ImageCacheCompanion toCompanion(bool nullToAbsent) {
    return ImageCacheCompanion(
      cacheKey: Value(cacheKey),
      refJson: Value(refJson),
      fileName: Value(fileName),
      checksum: Value(checksum),
      byteSize: Value(byteSize),
      format: Value(format),
      fetchedAt: Value(fetchedAt),
      lastAccessAt: Value(lastAccessAt),
    );
  }

  factory ImageCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImageCacheData(
      cacheKey: serializer.fromJson<String>(json['cache_key']),
      refJson: serializer.fromJson<String>(json['ref_json']),
      fileName: serializer.fromJson<String>(json['file_name']),
      checksum: serializer.fromJson<String>(json['checksum']),
      byteSize: serializer.fromJson<int>(json['byte_size']),
      format: serializer.fromJson<String>(json['format']),
      fetchedAt: serializer.fromJson<int>(json['fetched_at']),
      lastAccessAt: serializer.fromJson<int>(json['last_access_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cache_key': serializer.toJson<String>(cacheKey),
      'ref_json': serializer.toJson<String>(refJson),
      'file_name': serializer.toJson<String>(fileName),
      'checksum': serializer.toJson<String>(checksum),
      'byte_size': serializer.toJson<int>(byteSize),
      'format': serializer.toJson<String>(format),
      'fetched_at': serializer.toJson<int>(fetchedAt),
      'last_access_at': serializer.toJson<int>(lastAccessAt),
    };
  }

  ImageCacheData copyWith({
    String? cacheKey,
    String? refJson,
    String? fileName,
    String? checksum,
    int? byteSize,
    String? format,
    int? fetchedAt,
    int? lastAccessAt,
  }) => ImageCacheData(
    cacheKey: cacheKey ?? this.cacheKey,
    refJson: refJson ?? this.refJson,
    fileName: fileName ?? this.fileName,
    checksum: checksum ?? this.checksum,
    byteSize: byteSize ?? this.byteSize,
    format: format ?? this.format,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    lastAccessAt: lastAccessAt ?? this.lastAccessAt,
  );
  ImageCacheData copyWithCompanion(ImageCacheCompanion data) {
    return ImageCacheData(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      refJson: data.refJson.present ? data.refJson.value : this.refJson,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      format: data.format.present ? data.format.value : this.format,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      lastAccessAt: data.lastAccessAt.present
          ? data.lastAccessAt.value
          : this.lastAccessAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImageCacheData(')
          ..write('cacheKey: $cacheKey, ')
          ..write('refJson: $refJson, ')
          ..write('fileName: $fileName, ')
          ..write('checksum: $checksum, ')
          ..write('byteSize: $byteSize, ')
          ..write('format: $format, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('lastAccessAt: $lastAccessAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    cacheKey,
    refJson,
    fileName,
    checksum,
    byteSize,
    format,
    fetchedAt,
    lastAccessAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImageCacheData &&
          other.cacheKey == this.cacheKey &&
          other.refJson == this.refJson &&
          other.fileName == this.fileName &&
          other.checksum == this.checksum &&
          other.byteSize == this.byteSize &&
          other.format == this.format &&
          other.fetchedAt == this.fetchedAt &&
          other.lastAccessAt == this.lastAccessAt);
}

class ImageCacheCompanion extends UpdateCompanion<ImageCacheData> {
  final Value<String> cacheKey;
  final Value<String> refJson;
  final Value<String> fileName;
  final Value<String> checksum;
  final Value<int> byteSize;
  final Value<String> format;
  final Value<int> fetchedAt;
  final Value<int> lastAccessAt;
  final Value<int> rowid;
  const ImageCacheCompanion({
    this.cacheKey = const Value.absent(),
    this.refJson = const Value.absent(),
    this.fileName = const Value.absent(),
    this.checksum = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.format = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.lastAccessAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImageCacheCompanion.insert({
    required String cacheKey,
    required String refJson,
    required String fileName,
    required String checksum,
    required int byteSize,
    required String format,
    required int fetchedAt,
    required int lastAccessAt,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       refJson = Value(refJson),
       fileName = Value(fileName),
       checksum = Value(checksum),
       byteSize = Value(byteSize),
       format = Value(format),
       fetchedAt = Value(fetchedAt),
       lastAccessAt = Value(lastAccessAt);
  static Insertable<ImageCacheData> custom({
    Expression<String>? cacheKey,
    Expression<String>? refJson,
    Expression<String>? fileName,
    Expression<String>? checksum,
    Expression<int>? byteSize,
    Expression<String>? format,
    Expression<int>? fetchedAt,
    Expression<int>? lastAccessAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (refJson != null) 'ref_json': refJson,
      if (fileName != null) 'file_name': fileName,
      if (checksum != null) 'checksum': checksum,
      if (byteSize != null) 'byte_size': byteSize,
      if (format != null) 'format': format,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (lastAccessAt != null) 'last_access_at': lastAccessAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImageCacheCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? refJson,
    Value<String>? fileName,
    Value<String>? checksum,
    Value<int>? byteSize,
    Value<String>? format,
    Value<int>? fetchedAt,
    Value<int>? lastAccessAt,
    Value<int>? rowid,
  }) {
    return ImageCacheCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      refJson: refJson ?? this.refJson,
      fileName: fileName ?? this.fileName,
      checksum: checksum ?? this.checksum,
      byteSize: byteSize ?? this.byteSize,
      format: format ?? this.format,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      lastAccessAt: lastAccessAt ?? this.lastAccessAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (refJson.present) {
      map['ref_json'] = Variable<String>(refJson.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<String>(checksum.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (lastAccessAt.present) {
      map['last_access_at'] = Variable<int>(lastAccessAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImageCacheCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('refJson: $refJson, ')
          ..write('fileName: $fileName, ')
          ..write('checksum: $checksum, ')
          ..write('byteSize: $byteSize, ')
          ..write('format: $format, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('lastAccessAt: $lastAccessAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ImageOwners extends Table with TableInfo<ImageOwners, ImageOwner> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ImageOwners(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
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
  @override
  List<GeneratedColumn> get $columns => [cacheKey, sourceId, novelId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'image_owners';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImageOwner> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey, sourceId, novelId};
  @override
  ImageOwner map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImageOwner(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      novelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}novel_id'],
      )!,
    );
  }

  @override
  ImageOwners createAlias(String alias) {
    return ImageOwners(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(cache_key, source_id, novel_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ImageOwner extends DataClass implements Insertable<ImageOwner> {
  final String cacheKey;
  final String sourceId;
  final String novelId;
  const ImageOwner({
    required this.cacheKey,
    required this.sourceId,
    required this.novelId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['source_id'] = Variable<String>(sourceId);
    map['novel_id'] = Variable<String>(novelId);
    return map;
  }

  ImageOwnersCompanion toCompanion(bool nullToAbsent) {
    return ImageOwnersCompanion(
      cacheKey: Value(cacheKey),
      sourceId: Value(sourceId),
      novelId: Value(novelId),
    );
  }

  factory ImageOwner.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImageOwner(
      cacheKey: serializer.fromJson<String>(json['cache_key']),
      sourceId: serializer.fromJson<String>(json['source_id']),
      novelId: serializer.fromJson<String>(json['novel_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cache_key': serializer.toJson<String>(cacheKey),
      'source_id': serializer.toJson<String>(sourceId),
      'novel_id': serializer.toJson<String>(novelId),
    };
  }

  ImageOwner copyWith({String? cacheKey, String? sourceId, String? novelId}) =>
      ImageOwner(
        cacheKey: cacheKey ?? this.cacheKey,
        sourceId: sourceId ?? this.sourceId,
        novelId: novelId ?? this.novelId,
      );
  ImageOwner copyWithCompanion(ImageOwnersCompanion data) {
    return ImageOwner(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      novelId: data.novelId.present ? data.novelId.value : this.novelId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImageOwner(')
          ..write('cacheKey: $cacheKey, ')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(cacheKey, sourceId, novelId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImageOwner &&
          other.cacheKey == this.cacheKey &&
          other.sourceId == this.sourceId &&
          other.novelId == this.novelId);
}

class ImageOwnersCompanion extends UpdateCompanion<ImageOwner> {
  final Value<String> cacheKey;
  final Value<String> sourceId;
  final Value<String> novelId;
  final Value<int> rowid;
  const ImageOwnersCompanion({
    this.cacheKey = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.novelId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImageOwnersCompanion.insert({
    required String cacheKey,
    required String sourceId,
    required String novelId,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       sourceId = Value(sourceId),
       novelId = Value(novelId);
  static Insertable<ImageOwner> custom({
    Expression<String>? cacheKey,
    Expression<String>? sourceId,
    Expression<String>? novelId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (sourceId != null) 'source_id': sourceId,
      if (novelId != null) 'novel_id': novelId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImageOwnersCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? sourceId,
    Value<String>? novelId,
    Value<int>? rowid,
  }) {
    return ImageOwnersCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      sourceId: sourceId ?? this.sourceId,
      novelId: novelId ?? this.novelId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (novelId.present) {
      map['novel_id'] = Variable<String>(novelId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImageOwnersCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('sourceId: $sourceId, ')
          ..write('novelId: $novelId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final NovelCache novelCache = NovelCache(this);
  late final Index novelAccess = Index(
    'novel_access',
    'CREATE INDEX novel_access ON novel_cache (last_access_at)',
  );
  late final CatalogCache catalogCache = CatalogCache(this);
  late final Index catalogAccess = Index(
    'catalog_access',
    'CREATE INDEX catalog_access ON catalog_cache (last_access_at)',
  );
  late final ChapterCache chapterCache = ChapterCache(this);
  late final Index chapterAccess = Index(
    'chapter_access',
    'CREATE INDEX chapter_access ON chapter_cache (last_access_at)',
  );
  late final ImageCache imageCache = ImageCache(this);
  late final Index imageAccess = Index(
    'image_access',
    'CREATE INDEX image_access ON image_cache (last_access_at)',
  );
  late final ImageOwners imageOwners = ImageOwners(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    novelCache,
    novelAccess,
    catalogCache,
    catalogAccess,
    chapterCache,
    chapterAccess,
    imageCache,
    imageAccess,
    imageOwners,
  ];
}

typedef $NovelCacheCreateCompanionBuilder =
    NovelCacheCompanion Function({
      required String sourceId,
      required String novelId,
      required String payload,
      required int codecVersion,
      required int parserVersion,
      required int fetchedAt,
      Value<int?> expiresAt,
      required int lastAccessAt,
      required int byteSize,
      Value<int> rowid,
    });
typedef $NovelCacheUpdateCompanionBuilder =
    NovelCacheCompanion Function({
      Value<String> sourceId,
      Value<String> novelId,
      Value<String> payload,
      Value<int> codecVersion,
      Value<int> parserVersion,
      Value<int> fetchedAt,
      Value<int?> expiresAt,
      Value<int> lastAccessAt,
      Value<int> byteSize,
      Value<int> rowid,
    });

class $NovelCacheFilterComposer extends Composer<_$CacheDatabase, NovelCache> {
  $NovelCacheFilterComposer({
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

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );
}

class $NovelCacheOrderingComposer
    extends Composer<_$CacheDatabase, NovelCache> {
  $NovelCacheOrderingComposer({
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

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );
}

class $NovelCacheAnnotationComposer
    extends Composer<_$CacheDatabase, NovelCache> {
  $NovelCacheAnnotationComposer({
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

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);
}

class $NovelCacheTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          NovelCache,
          NovelCacheData,
          $NovelCacheFilterComposer,
          $NovelCacheOrderingComposer,
          $NovelCacheAnnotationComposer,
          $NovelCacheCreateCompanionBuilder,
          $NovelCacheUpdateCompanionBuilder,
          (
            NovelCacheData,
            BaseReferences<_$CacheDatabase, NovelCache, NovelCacheData>,
          ),
          NovelCacheData,
          PrefetchHooks Function()
        > {
  $NovelCacheTableManager(_$CacheDatabase db, NovelCache table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $NovelCacheFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $NovelCacheOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $NovelCacheAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<String> novelId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> codecVersion = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int?> expiresAt = const Value.absent(),
                Value<int> lastAccessAt = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelCacheCompanion(
                sourceId: sourceId,
                novelId: novelId,
                payload: payload,
                codecVersion: codecVersion,
                parserVersion: parserVersion,
                fetchedAt: fetchedAt,
                expiresAt: expiresAt,
                lastAccessAt: lastAccessAt,
                byteSize: byteSize,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required String novelId,
                required String payload,
                required int codecVersion,
                required int parserVersion,
                required int fetchedAt,
                Value<int?> expiresAt = const Value.absent(),
                required int lastAccessAt,
                required int byteSize,
                Value<int> rowid = const Value.absent(),
              }) => NovelCacheCompanion.insert(
                sourceId: sourceId,
                novelId: novelId,
                payload: payload,
                codecVersion: codecVersion,
                parserVersion: parserVersion,
                fetchedAt: fetchedAt,
                expiresAt: expiresAt,
                lastAccessAt: lastAccessAt,
                byteSize: byteSize,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $NovelCacheProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      NovelCache,
      NovelCacheData,
      $NovelCacheFilterComposer,
      $NovelCacheOrderingComposer,
      $NovelCacheAnnotationComposer,
      $NovelCacheCreateCompanionBuilder,
      $NovelCacheUpdateCompanionBuilder,
      (
        NovelCacheData,
        BaseReferences<_$CacheDatabase, NovelCache, NovelCacheData>,
      ),
      NovelCacheData,
      PrefetchHooks Function()
    >;
typedef $CatalogCacheCreateCompanionBuilder =
    CatalogCacheCompanion Function({
      required String sourceId,
      required String novelId,
      required String payload,
      required int codecVersion,
      required int parserVersion,
      required int fetchedAt,
      Value<int?> expiresAt,
      required int lastAccessAt,
      required int byteSize,
      Value<int> rowid,
    });
typedef $CatalogCacheUpdateCompanionBuilder =
    CatalogCacheCompanion Function({
      Value<String> sourceId,
      Value<String> novelId,
      Value<String> payload,
      Value<int> codecVersion,
      Value<int> parserVersion,
      Value<int> fetchedAt,
      Value<int?> expiresAt,
      Value<int> lastAccessAt,
      Value<int> byteSize,
      Value<int> rowid,
    });

class $CatalogCacheFilterComposer
    extends Composer<_$CacheDatabase, CatalogCache> {
  $CatalogCacheFilterComposer({
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

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );
}

class $CatalogCacheOrderingComposer
    extends Composer<_$CacheDatabase, CatalogCache> {
  $CatalogCacheOrderingComposer({
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

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );
}

class $CatalogCacheAnnotationComposer
    extends Composer<_$CacheDatabase, CatalogCache> {
  $CatalogCacheAnnotationComposer({
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

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);
}

class $CatalogCacheTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          CatalogCache,
          CatalogCacheData,
          $CatalogCacheFilterComposer,
          $CatalogCacheOrderingComposer,
          $CatalogCacheAnnotationComposer,
          $CatalogCacheCreateCompanionBuilder,
          $CatalogCacheUpdateCompanionBuilder,
          (
            CatalogCacheData,
            BaseReferences<_$CacheDatabase, CatalogCache, CatalogCacheData>,
          ),
          CatalogCacheData,
          PrefetchHooks Function()
        > {
  $CatalogCacheTableManager(_$CacheDatabase db, CatalogCache table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $CatalogCacheFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $CatalogCacheOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $CatalogCacheAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<String> novelId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> codecVersion = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int?> expiresAt = const Value.absent(),
                Value<int> lastAccessAt = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogCacheCompanion(
                sourceId: sourceId,
                novelId: novelId,
                payload: payload,
                codecVersion: codecVersion,
                parserVersion: parserVersion,
                fetchedAt: fetchedAt,
                expiresAt: expiresAt,
                lastAccessAt: lastAccessAt,
                byteSize: byteSize,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required String novelId,
                required String payload,
                required int codecVersion,
                required int parserVersion,
                required int fetchedAt,
                Value<int?> expiresAt = const Value.absent(),
                required int lastAccessAt,
                required int byteSize,
                Value<int> rowid = const Value.absent(),
              }) => CatalogCacheCompanion.insert(
                sourceId: sourceId,
                novelId: novelId,
                payload: payload,
                codecVersion: codecVersion,
                parserVersion: parserVersion,
                fetchedAt: fetchedAt,
                expiresAt: expiresAt,
                lastAccessAt: lastAccessAt,
                byteSize: byteSize,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $CatalogCacheProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      CatalogCache,
      CatalogCacheData,
      $CatalogCacheFilterComposer,
      $CatalogCacheOrderingComposer,
      $CatalogCacheAnnotationComposer,
      $CatalogCacheCreateCompanionBuilder,
      $CatalogCacheUpdateCompanionBuilder,
      (
        CatalogCacheData,
        BaseReferences<_$CacheDatabase, CatalogCache, CatalogCacheData>,
      ),
      CatalogCacheData,
      PrefetchHooks Function()
    >;
typedef $ChapterCacheCreateCompanionBuilder =
    ChapterCacheCompanion Function({
      required String sourceId,
      required String novelId,
      required String chapterId,
      required String payload,
      required int codecVersion,
      required int parserVersion,
      required int fetchedAt,
      Value<int?> expiresAt,
      required int lastAccessAt,
      required int byteSize,
      Value<int> rowid,
    });
typedef $ChapterCacheUpdateCompanionBuilder =
    ChapterCacheCompanion Function({
      Value<String> sourceId,
      Value<String> novelId,
      Value<String> chapterId,
      Value<String> payload,
      Value<int> codecVersion,
      Value<int> parserVersion,
      Value<int> fetchedAt,
      Value<int?> expiresAt,
      Value<int> lastAccessAt,
      Value<int> byteSize,
      Value<int> rowid,
    });

class $ChapterCacheFilterComposer
    extends Composer<_$CacheDatabase, ChapterCache> {
  $ChapterCacheFilterComposer({
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

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );
}

class $ChapterCacheOrderingComposer
    extends Composer<_$CacheDatabase, ChapterCache> {
  $ChapterCacheOrderingComposer({
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

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ChapterCacheAnnotationComposer
    extends Composer<_$CacheDatabase, ChapterCache> {
  $ChapterCacheAnnotationComposer({
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

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get codecVersion => $composableBuilder(
    column: $table.codecVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);
}

class $ChapterCacheTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          ChapterCache,
          ChapterCacheData,
          $ChapterCacheFilterComposer,
          $ChapterCacheOrderingComposer,
          $ChapterCacheAnnotationComposer,
          $ChapterCacheCreateCompanionBuilder,
          $ChapterCacheUpdateCompanionBuilder,
          (
            ChapterCacheData,
            BaseReferences<_$CacheDatabase, ChapterCache, ChapterCacheData>,
          ),
          ChapterCacheData,
          PrefetchHooks Function()
        > {
  $ChapterCacheTableManager(_$CacheDatabase db, ChapterCache table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ChapterCacheFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ChapterCacheOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ChapterCacheAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<String> novelId = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> codecVersion = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int?> expiresAt = const Value.absent(),
                Value<int> lastAccessAt = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChapterCacheCompanion(
                sourceId: sourceId,
                novelId: novelId,
                chapterId: chapterId,
                payload: payload,
                codecVersion: codecVersion,
                parserVersion: parserVersion,
                fetchedAt: fetchedAt,
                expiresAt: expiresAt,
                lastAccessAt: lastAccessAt,
                byteSize: byteSize,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required String novelId,
                required String chapterId,
                required String payload,
                required int codecVersion,
                required int parserVersion,
                required int fetchedAt,
                Value<int?> expiresAt = const Value.absent(),
                required int lastAccessAt,
                required int byteSize,
                Value<int> rowid = const Value.absent(),
              }) => ChapterCacheCompanion.insert(
                sourceId: sourceId,
                novelId: novelId,
                chapterId: chapterId,
                payload: payload,
                codecVersion: codecVersion,
                parserVersion: parserVersion,
                fetchedAt: fetchedAt,
                expiresAt: expiresAt,
                lastAccessAt: lastAccessAt,
                byteSize: byteSize,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ChapterCacheProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      ChapterCache,
      ChapterCacheData,
      $ChapterCacheFilterComposer,
      $ChapterCacheOrderingComposer,
      $ChapterCacheAnnotationComposer,
      $ChapterCacheCreateCompanionBuilder,
      $ChapterCacheUpdateCompanionBuilder,
      (
        ChapterCacheData,
        BaseReferences<_$CacheDatabase, ChapterCache, ChapterCacheData>,
      ),
      ChapterCacheData,
      PrefetchHooks Function()
    >;
typedef $ImageCacheCreateCompanionBuilder =
    ImageCacheCompanion Function({
      required String cacheKey,
      required String refJson,
      required String fileName,
      required String checksum,
      required int byteSize,
      required String format,
      required int fetchedAt,
      required int lastAccessAt,
      Value<int> rowid,
    });
typedef $ImageCacheUpdateCompanionBuilder =
    ImageCacheCompanion Function({
      Value<String> cacheKey,
      Value<String> refJson,
      Value<String> fileName,
      Value<String> checksum,
      Value<int> byteSize,
      Value<String> format,
      Value<int> fetchedAt,
      Value<int> lastAccessAt,
      Value<int> rowid,
    });

class $ImageCacheFilterComposer extends Composer<_$CacheDatabase, ImageCache> {
  $ImageCacheFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refJson => $composableBuilder(
    column: $table.refJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $ImageCacheOrderingComposer
    extends Composer<_$CacheDatabase, ImageCache> {
  $ImageCacheOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refJson => $composableBuilder(
    column: $table.refJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ImageCacheAnnotationComposer
    extends Composer<_$CacheDatabase, ImageCache> {
  $ImageCacheAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get refJson =>
      $composableBuilder(column: $table.refJson, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get lastAccessAt => $composableBuilder(
    column: $table.lastAccessAt,
    builder: (column) => column,
  );
}

class $ImageCacheTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          ImageCache,
          ImageCacheData,
          $ImageCacheFilterComposer,
          $ImageCacheOrderingComposer,
          $ImageCacheAnnotationComposer,
          $ImageCacheCreateCompanionBuilder,
          $ImageCacheUpdateCompanionBuilder,
          (
            ImageCacheData,
            BaseReferences<_$CacheDatabase, ImageCache, ImageCacheData>,
          ),
          ImageCacheData,
          PrefetchHooks Function()
        > {
  $ImageCacheTableManager(_$CacheDatabase db, ImageCache table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ImageCacheFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ImageCacheOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ImageCacheAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> refJson = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> checksum = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int> lastAccessAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImageCacheCompanion(
                cacheKey: cacheKey,
                refJson: refJson,
                fileName: fileName,
                checksum: checksum,
                byteSize: byteSize,
                format: format,
                fetchedAt: fetchedAt,
                lastAccessAt: lastAccessAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String refJson,
                required String fileName,
                required String checksum,
                required int byteSize,
                required String format,
                required int fetchedAt,
                required int lastAccessAt,
                Value<int> rowid = const Value.absent(),
              }) => ImageCacheCompanion.insert(
                cacheKey: cacheKey,
                refJson: refJson,
                fileName: fileName,
                checksum: checksum,
                byteSize: byteSize,
                format: format,
                fetchedAt: fetchedAt,
                lastAccessAt: lastAccessAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ImageCacheProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      ImageCache,
      ImageCacheData,
      $ImageCacheFilterComposer,
      $ImageCacheOrderingComposer,
      $ImageCacheAnnotationComposer,
      $ImageCacheCreateCompanionBuilder,
      $ImageCacheUpdateCompanionBuilder,
      (
        ImageCacheData,
        BaseReferences<_$CacheDatabase, ImageCache, ImageCacheData>,
      ),
      ImageCacheData,
      PrefetchHooks Function()
    >;
typedef $ImageOwnersCreateCompanionBuilder =
    ImageOwnersCompanion Function({
      required String cacheKey,
      required String sourceId,
      required String novelId,
      Value<int> rowid,
    });
typedef $ImageOwnersUpdateCompanionBuilder =
    ImageOwnersCompanion Function({
      Value<String> cacheKey,
      Value<String> sourceId,
      Value<String> novelId,
      Value<int> rowid,
    });

class $ImageOwnersFilterComposer
    extends Composer<_$CacheDatabase, ImageOwners> {
  $ImageOwnersFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnFilters(column),
  );
}

class $ImageOwnersOrderingComposer
    extends Composer<_$CacheDatabase, ImageOwners> {
  $ImageOwnersOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get novelId => $composableBuilder(
    column: $table.novelId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ImageOwnersAnnotationComposer
    extends Composer<_$CacheDatabase, ImageOwners> {
  $ImageOwnersAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get novelId =>
      $composableBuilder(column: $table.novelId, builder: (column) => column);
}

class $ImageOwnersTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          ImageOwners,
          ImageOwner,
          $ImageOwnersFilterComposer,
          $ImageOwnersOrderingComposer,
          $ImageOwnersAnnotationComposer,
          $ImageOwnersCreateCompanionBuilder,
          $ImageOwnersUpdateCompanionBuilder,
          (
            ImageOwner,
            BaseReferences<_$CacheDatabase, ImageOwners, ImageOwner>,
          ),
          ImageOwner,
          PrefetchHooks Function()
        > {
  $ImageOwnersTableManager(_$CacheDatabase db, ImageOwners table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ImageOwnersFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ImageOwnersOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ImageOwnersAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> novelId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImageOwnersCompanion(
                cacheKey: cacheKey,
                sourceId: sourceId,
                novelId: novelId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String sourceId,
                required String novelId,
                Value<int> rowid = const Value.absent(),
              }) => ImageOwnersCompanion.insert(
                cacheKey: cacheKey,
                sourceId: sourceId,
                novelId: novelId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ImageOwnersProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      ImageOwners,
      ImageOwner,
      $ImageOwnersFilterComposer,
      $ImageOwnersOrderingComposer,
      $ImageOwnersAnnotationComposer,
      $ImageOwnersCreateCompanionBuilder,
      $ImageOwnersUpdateCompanionBuilder,
      (ImageOwner, BaseReferences<_$CacheDatabase, ImageOwners, ImageOwner>),
      ImageOwner,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $NovelCacheTableManager get novelCache =>
      $NovelCacheTableManager(_db, _db.novelCache);
  $CatalogCacheTableManager get catalogCache =>
      $CatalogCacheTableManager(_db, _db.catalogCache);
  $ChapterCacheTableManager get chapterCache =>
      $ChapterCacheTableManager(_db, _db.chapterCache);
  $ImageCacheTableManager get imageCache =>
      $ImageCacheTableManager(_db, _db.imageCache);
  $ImageOwnersTableManager get imageOwners =>
      $ImageOwnersTableManager(_db, _db.imageOwners);
}
