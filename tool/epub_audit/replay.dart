import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/record_codec.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_trace.dart';
import 'package:shiori/data/local/epub/epub_diagnostics.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_content_links.dart';
import 'package:shiori/domain/models/models.dart';
import 'loss_model.dart';
import 'report.dart';

const replayCodecVersion = 1;
const maxBundleBytes = 256 * 1024 * 1024;
const maxModelBytes = 32 * 1024 * 1024;

/// macOS system aliases are trusted; arbitrary directory links remain rejected.
String systemAbsolute(String name) {
  final path = p.normalize(p.absolute(name));
  if (Platform.isMacOS) {
    for (final alias in ['/var', '/tmp']) {
      if (p.equals(path, alias) || p.isWithin(alias, path)) {
        return '/private$path';
      }
    }
  }
  return path;
}

Future<String> codeFingerprint(String root, List<String> paths) async {
  final names = <String>[];
  for (final name in paths) {
    final path = p.join(root, name);
    if (await FileSystemEntity.isFile(path)) {
      names.add(name);
    } else if (await Directory(path).exists()) {
      await for (final file in Directory(
        path,
      ).list(recursive: true, followLinks: false)) {
        if (file is File && p.extension(file.path) == '.dart') {
          names.add(p.relative(file.path, from: root).replaceAll('\\', '/'));
        }
      }
    }
  }
  names.sort();
  if (names.isEmpty || names.length > 10000) {
    throw const FormatException('Missing code identity');
  }
  return digest(
    jsonEncode([
      for (final name in names)
        [
          name,
          sha256
              .convert(await File(p.join(root, name)).readAsBytes())
              .toString(),
        ],
    ]),
  );
}

Future<Json> producerIdentity({String? root}) async {
  String actualRoot;
  try {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:shiori/data/local/book_decoder.dart'),
    );
    if (library == null || library.scheme != 'file') {
      throw const FormatException('Producer package identity unavailable');
    }
    actualRoot = p.dirname(
      p.dirname(p.dirname(p.dirname(library.toFilePath()))),
    );
  } on UnsupportedError {
    // Flutter test AOT has no package resolver. Its fixed entry is launched
    // from this repository; read the exact existing package configuration.
    final configFile = File(p.absolute('.dart_tool/package_config.json'));
    final config = await boundedJson(configFile, maxBytes: 1024 * 1024);
    final package = (config['packages'] as List).cast<Json>().singleWhere(
      (e) => e['name'] == 'shiori',
    );
    actualRoot = configFile.uri
        .resolve(package['rootUri'] as String)
        .toFilePath();
  }
  if (root != null && !p.equals(p.absolute(root), p.absolute(actualRoot))) {
    throw const FormatException('Producer code root mismatch');
  }
  final base = actualRoot;
  final parser = await codeFingerprint(base, [
    'lib/data/local/epub',
    'lib/data/local/book_decoder.dart',
  ]);
  final model = await codeFingerprint(base, [
    'lib/domain/models',
    'lib/domain/contracts',
    'lib/domain/content_identity.dart',
  ]);
  final renderer = await codeFingerprint(base, [
    'lib/features/reader',
    'lib/shared/source_image.dart',
    'lib/shared/capabilities.dart',
  ]);
  return {
    'fingerprint': digest(jsonEncode([parser, model, renderer])),
    'parser': parser,
    'model': model,
    'renderer': renderer,
    'parserVersion': BookDecoder.parserVersion,
    'replayCodecVersion': replayCodecVersion,
  };
}

Future<Json> evaluatorIdentity() async => {
  'fingerprint': await codeFingerprint(Directory.current.path, [
    for (final name in [
      'audit',
      'source',
      'report',
      'loss',
      'loss_model',
      'loss_report',
      'plan',
      'replay',
      'image_expectations',
    ])
      'tool/epub_audit/$name.dart',
  ]),
  'rulesVersion': auditRulesVersion,
  'schemaVersion': schemaVersion,
};
Future<Json> probeIdentity() async => {
  'fingerprint': await codeFingerprint(Directory.current.path, [
    'test/tool/epub_loss_native_probe_test.dart',
    'tool/epub_audit/native_probe.dart',
    'tool/epub_audit/browser_probe.dart',
    'tool/epub_audit/workflow.dart',
    'integration_test/epub_loss_webview.dart',
  ]),
  'version': '2.0.5',
};

/// Every file read at replay/verification boundaries must be independently
/// authorized. A report's alias/path is never used as filesystem authority.
Future<File> authorizedFile(
  String name,
  String allowedRoot, {
  required int maxBytes,
}) async {
  final root = Directory(p.absolute(allowedRoot));
  final rootCanonical = await root.resolveSymbolicLinks();
  if (!p.equals(systemAbsolute(root.path), p.normalize(rootCanonical))) {
    throw const FormatException('Linked allowed root');
  }
  final file = File(p.absolute(name));
  if (!p.isWithin(systemAbsolute(root.path), systemAbsolute(file.path))) {
    throw const FormatException('Outside allowed root');
  }
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Not a regular authorized file');
  }
  final canonical = await file.resolveSymbolicLinks();
  if (!p.equals(systemAbsolute(file.path), p.normalize(canonical)) ||
      !p.isWithin(rootCanonical, canonical) ||
      await file.length() > maxBytes) {
    throw const FormatException('Linked or oversized file');
  }
  return file;
}

Future<Json> boundedJson(File file, {int maxBytes = maxModelBytes}) async {
  if (await file.length() > maxBytes) {
    throw const FormatException('JSON budget');
  }
  final value = jsonDecode(await file.readAsString());
  if (value is! Json) throw const FormatException('JSON object required');
  return value;
}

Future<void> atomicJson(
  String name,
  Json value, {
  int maxBytes = maxModelBytes,
}) async {
  final bytes = utf8.encode(jsonEncode(value));
  if (bytes.length > maxBytes) throw const FormatException('JSON budget');
  final temporary = File('$name.partial');
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(name);
}

final class ProducerSnapshot {
  const ProducerSnapshot(this.parser, this.parsed, this.producer);
  final EpubParser parser;
  final ParsedEpub parsed;
  final Json producer;
  String get hash => sha256.convert(parser.bytes).toString();
  Json modelJson() => {
    'replayCodecVersion': replayCodecVersion,
    'epubHash': hash,
    'producer': producer,
    'detail': RecordCodec.detail(parsed.content.detail),
    'catalog': RecordCodec.catalog(parsed.content.catalog),
    'chapters': parsed.content.chapters.map((c) => c.toJson()).toList(),
    'auxiliaryChapters': parsed.content.auxiliaryChapters
        .map((c) => c.toJson())
        .toList(),
    'navigation': parsed.content.navigation.map((e) => e.toJson()).toList(),
    'links': parsed.content.links.map((e) => e.toJson()).toList(),
    'readingOrder': parsed.content.readingOrder
        ?.map((e) => e.toJson())
        .toList(),
    'chapterPaths': [
      for (final e in parser.chapterPaths.entries)
        {'chapterKey': e.key.toJson(), 'path': e.value},
    ],
    'mediaByPath': {
      for (final e in parser.mediaByPath.entries) e.key: e.value.toJson(),
    },
    'presentations': parser.presentations,
    'skippedEmptyPaths': parser.skippedEmptyPaths.toList(),
    'fragments': {
      for (final e in parser.fragments.entries)
        e.key: {
          for (final f in e.value.entries) f.key: [f.value.$1, f.value.$2],
        },
    },
    'trace': parser.trace?.events ?? [],
    'traceTruncated': parser.trace?.truncated ?? false,
    'diagnostics': parsed.diagnostics.codes.map((e) => e.name).toList(),
    'diagnosticsTruncated': parsed.diagnostics.truncated,
  };
}

Future<ProducerSnapshot> produce(
  Uint8List bytes, {
  String? producerRoot,
}) async {
  if (bytes.length > BookDecoder.maxEpubBytes) {
    throw const FormatException('Production payload limit');
  }
  final hash = sha256.convert(bytes).toString();
  final parser = EpubParser(
    bytes,
    LocalBookIdentity.book(hash),
    'private-replay.epub',
    includePresentations: true,
    trace: EpubTraceCollector(),
  );
  return ProducerSnapshot(
    parser,
    parser.parse(),
    await producerIdentity(root: producerRoot),
  );
}

Future<void> writeBundle(ProducerSnapshot snapshot, Directory output) async {
  var bytes = snapshot.parser.bytes.length;
  final model = utf8.encode(jsonEncode(snapshot.modelJson()));
  if (model.length > maxModelBytes) throw const FormatException('Model budget');
  bytes += model.length;
  final entries = <Json>[];
  Future<void> write(String name, List<int> data) async {
    entries.add({
      'file': name,
      'bytes': data.length,
      'sha256': sha256.convert(data).toString(),
    });
    await File(p.join(output.path, name)).writeAsBytes(data, flush: true);
  }

  await write('source.epub', snapshot.parser.bytes);
  await write('model.json', model);
  await Directory(p.join(output.path, 'media')).create();
  for (final e in snapshot.parsed.media.entries) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(e.key) ||
        sha256.convert(e.value).toString() != e.key) {
      throw const FormatException('Media identity mismatch');
    }
    bytes += e.value.length;
    if (bytes > maxBundleBytes) {
      throw const FormatException('Private bundle budget');
    }
    await write('media/${e.key}', e.value);
  }
  await File(p.join(output.path, 'PRIVATE.txt')).writeAsString(
    'Private EPUB replay: original text, media, fonts and authored CSS. Never upload or commit. '
    'Delete only this explicit output directory when no longer needed.\n',
    flush: true,
  );
  // Publication last: an incomplete directory is not a completed snapshot.
  await atomicJson(p.join(output.path, 'bundle.json'), {
    'replayCodecVersion': replayCodecVersion,
    'private': true,
    'epubHash': snapshot.hash,
    'producer': snapshot.producer,
    'files': entries,
    'totalBytes': bytes,
    'budgetBytes': maxBundleBytes,
    'complete': true,
  });
}

Future<ProducerSnapshot> readBundle(
  String directory,
  String allowedRoot,
) async {
  final dir = p.absolute(directory);
  final manifest = await boundedJson(
    await authorizedFile(
      p.join(dir, 'bundle.json'),
      allowedRoot,
      maxBytes: 1024 * 1024,
    ),
    maxBytes: 1024 * 1024,
  );
  if (manifest['replayCodecVersion'] != replayCodecVersion ||
      manifest['complete'] != true ||
      manifest['private'] != true ||
      intField(manifest, 'totalBytes', max: maxBundleBytes) > maxBundleBytes) {
    throw const FormatException('Unsupported/incomplete replay bundle');
  }
  final hash = hashField(manifest, 'epubHash');
  final rows = objectList(manifest, 'files', max: 10000);
  final names = <String>{};
  final data = <String, Uint8List>{};
  var total = 0;
  for (final row in rows) {
    final name = stringField(row, 'file');
    if (!RegExp(
          r'^(source\.epub|model\.json|media/[a-f0-9]{64})$',
        ).hasMatch(name) ||
        !names.add(name)) {
      throw const FormatException('Unsafe/repeated replay filename');
    }
    final n = intField(row, 'bytes', max: maxBundleBytes);
    total += n;
    if (total > maxBundleBytes) {
      throw const FormatException('Replay byte budget');
    }
    final file = await authorizedFile(
      p.join(dir, name),
      allowedRoot,
      maxBytes: n,
    );
    if (await file.length() != n) {
      throw const FormatException('Replay size mismatch');
    }
    final b = await file.readAsBytes();
    if (sha256.convert(b).toString() != hashField(row, 'sha256') ||
        name.startsWith('media/') && name.substring(6) != row['sha256']) {
      throw const FormatException('Replay checksum mismatch');
    }
    data[name] = b;
  }
  if (total != manifest['totalBytes'] ||
      !data.containsKey('source.epub') ||
      !data.containsKey('model.json') ||
      data['source.epub']!.length > BookDecoder.maxEpubBytes ||
      data['model.json']!.length > maxModelBytes ||
      sha256.convert(data['source.epub']!).toString() != hash) {
    throw const FormatException('Replay source identity mismatch');
  }
  final model = jsonDecode(utf8.decode(data.remove('model.json')!)) as Json;
  if (model['epubHash'] != hash ||
      model['replayCodecVersion'] != replayCodecVersion ||
      jsonEncode(model['producer']) != jsonEncode(manifest['producer'])) {
    throw const FormatException('Replay producer mismatch');
  }
  hashField(model['producer'] as Json, 'fingerprint');
  final diagnostics = EpubDiagnosticCollector();
  for (final code in stringList(model, 'diagnostics', max: 100)) {
    diagnostics.add(EpubDiagnosticCode.values.byName(code));
  }
  if (model['diagnosticsTruncated'] == true) {
    for (var i = 0; i <= 100; i++) {
      diagnostics.add(EpubDiagnosticCode.noUsableImage);
    }
  }
  final trace = EpubTraceCollector();
  for (final event in objectList(model, 'trace', max: 100000)) {
    trace.record(
      stringField(event, 'kind'),
      stringField(event, 'document'),
      location: event['location'] as String?,
      stylesheet: event['stylesheet'] as String?,
      ruleIndex: event['ruleIndex'] as int?,
      declarationIndex: event['declarationIndex'] as int?,
      property: event['property'] as String?,
      value: event['value'] as String?,
      reason: stringField(event, 'reason'),
      data: event['data'] as Json,
    );
  }
  trace.truncated = model['traceTruncated'] == true;
  final parser = EpubParser(
    data.remove('source.epub')!,
    LocalBookIdentity.book(hash),
    'private-replay.epub',
    includePresentations: true,
    trace: trace,
  );
  // Deliberately never parse: old producer output must remain old output.
  final content = LocalBookContent(
    detail: RecordCodec.readDetail(model['detail'] as String),
    catalog: RecordCodec.readCatalog(model['catalog'] as String),
    chapters: objectList(
      model,
      'chapters',
      max: 4096,
    ).map(ChapterContent.fromJson),
    auxiliaryChapters: objectList(
      model,
      'auxiliaryChapters',
      max: 4096,
    ).map(ChapterContent.fromJson),
    navigation: objectList(
      model,
      'navigation',
    ).map(LocalNavigationEntry.fromJson),
    links: objectList(model, 'links').map(LocalContentLink.fromJson),
    readingOrder: model['readingOrder'] == null
        ? null
        : objectList(model, 'readingOrder').map(ChapterKey.fromJson),
  );
  if (content.detail.summary.key != parser.book ||
      content.catalog.novelKey != parser.book) {
    throw const FormatException('Replay book identity mismatch');
  }
  for (final row in objectList(model, 'chapterPaths', max: 8192)) {
    parser.chapterPaths[ChapterKey.fromJson(row['chapterKey'] as Json)] =
        stringField(row, 'path');
  }
  parser.presentations.addAll(
    (model['presentations'] as Json).cast<String, String>(),
  );
  parser.mediaByPath.addAll({
    for (final e in (model['mediaByPath'] as Json).entries)
      e.key: MediaRef.fromJson(e.value as Json),
  });
  parser.skippedEmptyPaths.addAll(stringList(model, 'skippedEmptyPaths'));
  for (final e in (model['fragments'] as Json).entries) {
    parser.fragments[e.key] = {
      for (final f in (e.value as Json).entries)
        f.key: ((f.value as List)[0] as String, (f.value as List)[1] as int),
    };
  }
  for (final c in [...content.chapters, ...content.auxiliaryChapters]) {
    final path = parser.chapterPaths[c.key];
    if (path != null) parser.byPath.putIfAbsent(path, () => c);
  }
  final media = {for (final e in data.entries) e.key.substring(6): e.value};
  parser.media.addAll(media);
  return ProducerSnapshot(
    parser,
    ParsedEpub(content, media, diagnostics.snapshot()),
    model['producer'] as Json,
  );
}
