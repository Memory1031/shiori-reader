import 'dart:convert';
import 'report.dart' show Json, digest;

enum CheckStatus { pass, fail, unknown, notRun }

enum LossFamily { content, structure, visual, interaction }

enum EvidenceLayer {
  sourceModel,
  readerPath,
  widgetGeometry,
  controlRouting,
  browserGeometry,
  nativeWebView,
  audioDecode,
  fontGlyph,
}

enum DecisionKind {
  recommendFix,
  verifyNext,
  defer,
  acceptedPolicy,
  sourceIssue,
  insufficientEvidence,
}

String wireName(Enum value) => value.name.replaceAllMapped(
  RegExp('[A-Z]'),
  (m) => '_${m[0]!.toLowerCase()}',
);
T wireEnum<T extends Enum>(Iterable<T> values, Object? value) =>
    values.firstWhere(
      (e) => wireName(e) == value,
      orElse: () => throw const FormatException('Unknown enum'),
    );
String stringField(Json j, String field, {int limit = 1024}) {
  final value = j[field];
  if (value is! String ||
      value.isEmpty ||
      value.length > limit ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw const FormatException('Invalid string field');
  }
  return value;
}

String hashField(Json j, String field) {
  final value = stringField(j, field, limit: 64);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid digest');
  }
  return value;
}

int intField(Json j, String field, {int max = 100000000}) {
  final value = j[field];
  if (value is! int || value < 0 || value > max) {
    throw const FormatException('Invalid integer field');
  }
  return value;
}

List<Json> objectList(Json j, String field, {int max = 20000}) {
  final value = j[field];
  if (value is! List || value.length > max || value.any((e) => e is! Json)) {
    throw const FormatException('Invalid object list');
  }
  return value.cast<Json>();
}

List<String> stringList(Json j, String field, {int max = 20000}) {
  final value = j[field];
  if (value is! List ||
      value.length > max ||
      value.any((e) => e is! String || e.length > 1024)) {
    throw const FormatException('Invalid string list');
  }
  return value.cast<String>();
}

/// Ranges are explicitly labelled; a missing HTML source span stays absent.
final class AuditRange {
  AuditRange(this.start, this.length, this.unit) {
    if (start < 0 ||
        length < 0 ||
        !{'unicode_code_point', 'utf16', 'utf8_byte'}.contains(unit)) {
      throw const FormatException('Invalid range');
    }
  }
  final int start, length;
  final String unit;
  Json toJson() => {'start': start, 'length': length, 'unit': unit};
  factory AuditRange.fromJson(Json j) => AuditRange(
    intField(j, 'start'),
    intField(j, 'length'),
    stringField(j, 'unit'),
  );
}

final class SourceLocation {
  const SourceLocation(
    this.epubHash,
    this.document,
    this.occurrence,
    this.domPath, {
    this.sourceRange,
  });
  final String epubHash, document, domPath;
  final int
  occurrence; // -1 is an auxiliary/non-spine document, never occurrence 0.
  final AuditRange? sourceRange;
  String get identity =>
      digest(jsonEncode([epubHash, document, occurrence, domPath]));
  Json toJson() => {
    'epubHash': epubHash,
    'document': document,
    'occurrence': occurrence,
    'domPath': domPath,
    'sourceRange': sourceRange?.toJson(),
  };
  factory SourceLocation.fromJson(Json j) {
    final occurrence = j['occurrence'];
    if (occurrence is! int || occurrence < -1 || occurrence > 10000) {
      throw const FormatException('Invalid occurrence');
    }
    final document = stringField(j, 'document');
    if (document.startsWith('/') ||
        document.contains('\\') ||
        document.split('/').any((e) => e == '..') ||
        document.contains(':')) {
      throw const FormatException('Invalid package path');
    }
    return SourceLocation(
      hashField(j, 'epubHash'),
      document,
      occurrence,
      stringField(j, 'domPath'),
      sourceRange: j['sourceRange'] == null
          ? null
          : AuditRange.fromJson(j['sourceRange'] as Json),
    );
  }
}

final class SourceFact {
  SourceFact({
    required this.id,
    required this.location,
    required this.kind,
    required this.method,
    required this.effective,
    required this.status,
    required this.shape,
    this.textHash,
    this.range,
    Json details = const {},
    Iterable<String> dependencies = const [],
    Iterable<String> uncertainties = const [],
  }) : details = Map.unmodifiable(details),
       dependencies = List.unmodifiable(dependencies),
       uncertainties = List.unmodifiable(uncertainties);
  final String id, kind, method, shape;
  final SourceLocation location;
  final bool effective;
  final CheckStatus status;
  final String? textHash;
  final AuditRange? range;
  final Json details;
  final List<String> dependencies, uncertainties;
  Json toJson() => {
    'id': id,
    'location': location.toJson(),
    'kind': kind,
    'method': method,
    'effective': effective,
    'status': wireName(status),
    'shape': shape,
    'textHash': textHash,
    'normalizedRange': range?.toJson(),
    'details': details,
    'dependencies': dependencies,
    'uncertainties': uncertainties,
  };
  factory SourceFact.fromJson(Json j) => SourceFact(
    id: hashField(j, 'id'),
    location: SourceLocation.fromJson(j['location'] as Json),
    kind: stringField(j, 'kind'),
    method: stringField(j, 'method'),
    effective: j['effective'] == true,
    status: wireEnum(CheckStatus.values, j['status']),
    shape: hashField(j, 'shape'),
    textHash: j['textHash'] == null ? null : hashField(j, 'textHash'),
    range: j['normalizedRange'] == null
        ? null
        : AuditRange.fromJson(j['normalizedRange'] as Json),
    details: j['details'] as Json,
    dependencies: stringList(j, 'dependencies'),
    uncertainties: stringList(j, 'uncertainties'),
  );
}

final class RepresentationFact {
  RepresentationFact({
    required this.id,
    required this.chapterKey,
    required this.path,
    required this.kind,
    this.blockKey,
    this.range,
    this.textHash,
    Iterable<String> resources = const [],
    Json metadata = const {},
  }) : resources = List.unmodifiable(resources),
       metadata = Map.unmodifiable(metadata);
  final String id, path, kind;
  final Json chapterKey, metadata;
  final String? blockKey, textHash;
  final AuditRange? range;
  final List<String> resources;
  Json toJson() => {
    'id': id,
    'chapterKey': chapterKey,
    'path': path,
    'kind': kind,
    'blockKey': blockKey,
    'range': range?.toJson(),
    'textHash': textHash,
    'resources': resources,
    'metadata': metadata,
  };
  factory RepresentationFact.fromJson(Json j) => RepresentationFact(
    id: hashField(j, 'id'),
    chapterKey: j['chapterKey'] as Json,
    path: stringField(j, 'path'),
    kind: stringField(j, 'kind'),
    blockKey: j['blockKey'] as String?,
    textHash: j['textHash'] as String?,
    range: j['range'] == null ? null : AuditRange.fromJson(j['range'] as Json),
    resources: stringList(j, 'resources'),
    metadata: j['metadata'] as Json,
  );
}

final class Correspondence {
  Correspondence(
    this.sourceId,
    Iterable<String> representationIds,
    this.status,
    this.transformation, {
    this.reason = 'independent_instance_match',
  }) : representationIds = List.unmodifiable(representationIds);
  final String sourceId, transformation, reason;
  final List<String> representationIds;
  final CheckStatus status;
  Json toJson() => {
    'sourceId': sourceId,
    'representationIds': representationIds,
    'status': wireName(status),
    'transformation': transformation,
    'reason': reason,
  };
  factory Correspondence.fromJson(Json j) => Correspondence(
    hashField(j, 'sourceId'),
    stringList(j, 'representationIds'),
    wireEnum(CheckStatus.values, j['status']),
    stringField(j, 'transformation'),
    reason: stringField(j, 'reason'),
  );
}

final class LossCandidate {
  LossCandidate({
    required this.id,
    required this.sourceId,
    required this.groupId,
    required this.location,
    required this.family,
    required this.rule,
    required this.reason,
    required this.impact,
    required this.confidence,
    required this.status,
    required this.predictedPath,
    required this.classification,
    Iterable<String> evidenceRefs = const [],
    Iterable<String> uncertainties = const [],
    Iterable<String> methods = const ['native'],
    this.instances = 1,
    this.countAccuracy = 'exact',
  }) : evidenceRefs = List.unmodifiable(evidenceRefs),
       uncertainties = List.unmodifiable(uncertainties),
       methods = List.unmodifiable(methods);
  final String id,
      sourceId,
      groupId,
      rule,
      reason,
      impact,
      confidence,
      predictedPath,
      classification,
      countAccuracy;
  final SourceLocation location;
  final LossFamily family;
  final CheckStatus status;
  final int instances;
  final List<String> evidenceRefs, uncertainties, methods;
  Json toJson() => {
    'id': id,
    'sourceId': sourceId,
    'groupId': groupId,
    'location': location.toJson(),
    'family': wireName(family),
    'rule': rule,
    'reason': reason,
    'impact': impact,
    'confidence': confidence,
    'status': wireName(status),
    'predictedPath': predictedPath,
    'classification': classification,
    'evidenceRefs': evidenceRefs,
    'uncertainties': uncertainties,
    'methods': methods,
    'instances': instances,
    'countAccuracy': countAccuracy,
  };
  factory LossCandidate.fromJson(Json j) => LossCandidate(
    id: hashField(j, 'id'),
    sourceId: hashField(j, 'sourceId'),
    groupId: hashField(j, 'groupId'),
    location: SourceLocation.fromJson(j['location'] as Json),
    family: wireEnum(LossFamily.values, j['family']),
    rule: stringField(j, 'rule'),
    reason: stringField(j, 'reason'),
    impact: stringField(j, 'impact'),
    confidence: stringField(j, 'confidence'),
    status: wireEnum(CheckStatus.values, j['status']),
    predictedPath: stringField(j, 'predictedPath'),
    classification: stringField(j, 'classification'),
    evidenceRefs: stringList(j, 'evidenceRefs'),
    uncertainties: stringList(j, 'uncertainties'),
    methods: stringList(j, 'methods'),
    instances: intField(j, 'instances'),
    countAccuracy: stringField(j, 'countAccuracy'),
  );
}

final class VerificationEvidence {
  VerificationEvidence({
    required this.id,
    required this.candidateId,
    required this.sourceId,
    required this.epubHash,
    required this.producer,
    required this.probe,
    required this.environment,
    required this.configuration,
    required this.provider,
    required this.observedPath,
    required Map<EvidenceLayer, CheckStatus> layers,
    required this.complete,
    Json assertions = const {},
    Iterable<String> artifacts = const [],
    this.reason = 'executed',
  }) : layers = Map.unmodifiable(layers),
       assertions = Map.unmodifiable(assertions),
       artifacts = List.unmodifiable(artifacts);
  final String id,
      candidateId,
      sourceId,
      epubHash,
      producer,
      probe,
      environment,
      configuration,
      provider,
      observedPath,
      reason;
  final bool complete;
  final Map<EvidenceLayer, CheckStatus> layers;
  final Json assertions;
  final List<String> artifacts;
  Json toJson() => {
    'id': id,
    'candidateId': candidateId,
    'sourceId': sourceId,
    'epubHash': epubHash,
    'producer': producer,
    'probe': probe,
    'environment': environment,
    'configuration': configuration,
    'provider': provider,
    'observedPath': observedPath,
    'layers': {
      for (final e in layers.entries) wireName(e.key): wireName(e.value),
    },
    'complete': complete,
    'assertions': assertions,
    'artifacts': artifacts,
    'reason': reason,
  };
  factory VerificationEvidence.fromJson(Json j) => VerificationEvidence(
    id: hashField(j, 'id'),
    candidateId: hashField(j, 'candidateId'),
    sourceId: hashField(j, 'sourceId'),
    epubHash: hashField(j, 'epubHash'),
    producer: hashField(j, 'producer'),
    probe: hashField(j, 'probe'),
    environment: hashField(j, 'environment'),
    configuration: hashField(j, 'configuration'),
    provider: stringField(j, 'provider'),
    observedPath: stringField(j, 'observedPath'),
    layers: {
      for (final e in (j['layers'] as Json).entries)
        wireEnum(EvidenceLayer.values, e.key): wireEnum(
          CheckStatus.values,
          e.value,
        ),
    },
    complete: j['complete'] == true,
    assertions: j['assertions'] as Json,
    artifacts: stringList(j, 'artifacts'),
    reason: stringField(j, 'reason'),
  );
}

final class ReviewDecision {
  ReviewDecision(
    this.candidateId,
    this.kind,
    this.reason,
    Iterable<String> evidence, {
    this.reviewerType = 'rule',
    this.scope = 'single_instance',
    this.producer,
    this.environment,
  }) : evidence = List.unmodifiable(evidence);
  final String candidateId, reason, reviewerType, scope;
  final String? producer, environment;
  final DecisionKind kind;
  final List<String> evidence;
  Json toJson() => {
    'candidateId': candidateId,
    'kind': wireName(kind),
    'reason': reason,
    'evidenceRefs': evidence,
    'reviewerType': reviewerType,
    'scope': scope,
    'producer': producer,
    'environment': environment,
    'invalidatedBy': [
      'source_identity',
      'producer_identity',
      'key_environment',
    ],
  };
}
