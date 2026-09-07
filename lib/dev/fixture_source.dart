import 'dart:convert';
import 'dart:typed_data';

import '../domain/contracts/contracts.dart';
import '../domain/models/models.dart';
import 'fixture_controls.dart';
import 'fixture_png.dart';
import 'fixture_scenarios.dart';

final class FixtureNovelSource implements NovelSource, SourceMedia {
  FixtureNovelSource({
    this.scenario = FixtureScenario.shortChapter,
    this.data = const FixtureData(),
    FixtureControls? controls,
  }) : controls = controls ?? FixtureControls() {
    if (scenario == FixtureScenario.slowImage) {
      this.controls.mediaChunkDelay = const Duration(milliseconds: 200);
    }
    if (scenario == FixtureScenario.failingImage) {
      this.controls.mediaStreamFailures = 1;
    }
  }
  final FixtureScenario scenario;
  final FixtureData data;
  final FixtureControls controls;
  int activeBodies = 0;
  @override
  SourceDescriptor get descriptor => SourceDescriptor(
    sourceId: fixtureSourceId,
    displayName: 'Shiori Fixture',
    supportsDiscover: true,
    supportsSearchPaging: true,
  );

  FixtureScenario? _scenario(NovelKey key) {
    if (key.sourceId != fixtureSourceId) return null;
    for (final value in FixtureScenario.values) {
      if (key == fixtureNovelKey(value)) return value;
    }
    return null;
  }

  @override
  Future<Result<List<DiscoverSection>>> discover({
    required CancellationToken cancellation,
  }) async {
    final failure = await controls.before(Operation.discover, cancellation);
    if (failure != null) return Failure(failure);
    return Success([
      DiscoverSection(
        label: '离线场景 / Offline scenarios',
        items: FixtureScenario.values.map(data.summary),
      ),
    ]);
  }

  @override
  Future<Result<SearchPage>> search(
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) async {
    final failure = await controls.before(Operation.search, cancellation);
    if (failure != null) return Failure(failure);
    final normalized = query.trim().toLowerCase();
    final binding = base64Url.encode(utf8.encode(normalized));
    final matches = scenario == FixtureScenario.emptySearch
        ? <NovelSummary>[]
        : FixtureScenario.values
              .map(data.summary)
              .where(
                (book) =>
                    normalized.isEmpty ||
                    book.title.toLowerCase().contains(normalized) ||
                    book.key.novelId.toLowerCase().contains(normalized),
              )
              .toList();
    var offset = 0;
    if (cursor != null) {
      final parts = cursor.opaqueValue.split(':');
      final parsed = parts.length == 3 ? int.tryParse(parts[2]) : null;
      if (cursor.sourceId != fixtureSourceId ||
          parts.length != 3 ||
          parts[0] != 'fixture-v1' ||
          parts[1] != binding ||
          parsed == null ||
          parsed <= 0 ||
          parsed % 4 != 0 ||
          parsed >= matches.length) {
        return fixtureFailure(
          Operation.search,
          FailureKind.parse,
          context: FailureContext.invalidCursor,
        );
      }
      offset = parsed;
      if (scenario == FixtureScenario.repeatedCursor) {
        // Simulates detecting a replay upstream, respecting the public contract.
        return fixtureFailure(
          Operation.search,
          FailureKind.parse,
          context: FailureContext.repeatedPage,
        );
      }
    }
    final end = (offset + 4).clamp(0, matches.length);
    return Success(
      SearchPage(
        sourceId: fixtureSourceId,
        items: matches.sublist(offset, end),
        nextCursor: end < matches.length
            ? SearchCursor(
                sourceId: fixtureSourceId,
                opaqueValue: 'fixture-v1:$binding:$end',
              )
            : null,
      ),
    );
  }

  @override
  Future<Result<NovelDetail>> getNovelDetail(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    final failure = await controls.before(Operation.novelDetail, cancellation);
    if (failure != null) return Failure(failure);
    final selected = _scenario(key);
    return selected == null
        ? fixtureFailure(Operation.novelDetail, FailureKind.notFound)
        : Success(data.detail(selected));
  }

  bool _deleted(FixtureScenario selected) =>
      selected == FixtureScenario.deletedChapter || controls.chapterDeleted;

  @override
  Future<Result<Catalog>> getCatalog(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    final failure = await controls.before(Operation.catalog, cancellation);
    if (failure != null) return Failure(failure);
    final selected = _scenario(key);
    return selected == null
        ? fixtureFailure(Operation.catalog, FailureKind.notFound)
        : Success(data.catalog(selected, deleted: _deleted(selected)));
  }

  @override
  Future<Result<ChapterContent>> getChapter(
    ChapterKey key, {
    required CancellationToken cancellation,
  }) async {
    final failure = await controls.before(Operation.chapter, cancellation);
    if (failure != null) return Failure(failure);
    final selected = _scenario(key.novelKey);
    if (selected == null) {
      return fixtureFailure(Operation.chapter, FailureKind.notFound);
    }
    final chapters = data
        .catalog(selected, deleted: _deleted(selected))
        .flatChapters;
    if (!chapters.any((chapter) => chapter.key == key)) {
      return fixtureFailure(Operation.chapter, FailureKind.notFound);
    }
    final index = int.parse(key.chapterId.substring('chapter-'.length));
    return Success(
      data.content(selected, index: index, revision: controls.revision),
    );
  }

  @override
  Future<Result<SourceMediaBody>> openMedia(
    MediaRef ref, {
    required int maxBytes,
    required CancellationToken cancellation,
  }) async {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    final failure = await controls.before(Operation.media, cancellation);
    if (failure != null) return Failure(failure);
    final match = RegExp(r'^checker-([0-9]+)$').firstMatch(ref.mediaId);
    final index = match == null ? null : int.tryParse(match[1]!);
    if (ref.sourceId != fixtureSourceId ||
        index == null ||
        index > 19 ||
        ref.mediaId != 'checker-$index') {
      return fixtureFailure(Operation.media, FailureKind.notFound);
    }
    final (width, height) = data.dimensions(index);
    final bytes = fixturePng(width, height, data.seed + index);
    final failStream = controls.mediaStreamFailures > 0;
    if (failStream) controls.mediaStreamFailures--;
    activeBodies++;
    return Success(
      FixtureMediaBody(
        bytes: bytes,
        info: MediaInfo(
          format: MediaFormat.png,
          byteLength: bytes.length,
          width: scenario == FixtureScenario.unknownImageSize ? null : width,
          height: scenario == FixtureScenario.unknownImageSize ? null : height,
        ),
        maxBytes: maxBytes,
        cancellation: cancellation,
        delay: controls.mediaChunkDelay,
        failStream: failStream,
        onClose: () => activeBodies--,
      ),
    );
  }
}

final class FixtureMediaBody implements SourceMediaBody {
  FixtureMediaBody({
    required Uint8List bytes,
    required this.info,
    required this.maxBytes,
    required this.cancellation,
    required this.delay,
    required this.failStream,
    required this.onClose,
  }) : _bytes = bytes;
  Uint8List? _bytes;
  @override
  final MediaInfo info;
  @override
  final int maxBytes;
  final CancellationToken cancellation;
  final Duration delay;
  final bool failStream;
  final void Function() onClose;
  final _lifetime = CancellationSource();
  bool _listened = false;
  bool get isClosed => _bytes == null;
  @override
  Stream<Result<List<int>>> get chunks {
    if (_listened || isClosed) throw StateError('Body is single-use');
    _listened = true;
    return _read();
  }

  Stream<Result<List<int>>> _read() async* {
    try {
      var offset = 0;
      while (!isClosed && offset < _bytes!.length) {
        await Future.any([
          fixtureDelay(delay, _lifetime.token),
          cancellation.whenCancelled,
        ]);
        if (isClosed || cancellation.isCancelled) {
          yield fixtureCancelled(Operation.media);
          return;
        }
        if (failStream && offset > 0) {
          yield Failure(
            AppFailure(
              kind: FailureKind.network,
              operation: Operation.media,
              retryPolicy: RetryPolicy.manual,
            ),
          );
          return;
        }
        final end = (offset + 1024).clamp(0, _bytes!.length);
        if (end > maxBytes) {
          yield fixtureFailure(Operation.media, FailureKind.tooLarge);
          return;
        }
        yield Success(List<int>.unmodifiable(_bytes!.sublist(offset, end)));
        offset = end;
      }
    } finally {
      await close();
    }
  }

  @override
  Future<void> close() async {
    if (!isClosed) {
      _lifetime.cancel();
      _bytes = null;
      onClose();
    }
  }
}
