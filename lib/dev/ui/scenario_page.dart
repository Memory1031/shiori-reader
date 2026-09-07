import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../app/routes.dart';
import '../../data/media/memory_image_repository.dart';
import 'viewport_experiment.dart';
import '../../features/reader/reader_screen.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/state_views.dart';
import '../fixtures.dart';
import 'dev_app.dart' show scenarioLabel;

/// A bounded data inspector, not a Reader implementation. Each route owns a
/// fresh environment; callers and media consumers retain explicit ownership.
class DevScenarioPage extends StatefulWidget {
  const DevScenarioPage({
    super.key,
    required this.scenario,
    this.createEnvironment,
    this.settings,
    this.library,
  });
  final FixtureScenario scenario;
  final SettingsStore? settings;
  final LibraryRepository? library;
  final FixtureEnvironment Function(FixtureScenario)? createEnvironment;
  @override
  State<DevScenarioPage> createState() => _DevScenarioPageState();
}

class _DevScenarioPageState extends State<DevScenarioPage> {
  late final FixtureEnvironment _env;
  late final MemoryImageRepository _readerImages;
  late NovelKey _novel;
  late ChapterKey _chapter;
  final _query = TextEditingController();
  CancellationSource? _request;
  int _generation = 0;
  bool _loading = false;
  AppFailure? _failure;
  Object? _report;
  ChapterContent? _content;
  List<NovelSummary> _books = [];
  List<Chapter> _chapters = [];
  List<ImageBlock> _images = [];
  SearchCursor? _cursor;
  String _submittedQuery = '';
  Future<void> Function()? _retry;

  @override
  void initState() {
    super.initState();
    _env =
        widget.createEnvironment?.call(widget.scenario) ??
        FixtureEnvironment(scenario: widget.scenario);
    _readerImages = MemoryImageRepository(
      resolve: (id) => id == fixtureSourceId ? _env.source : null,
    );
    _novel = fixtureNovelKey(widget.scenario);
    _chapter = fixtureChapterKey(widget.scenario);
    unawaited(_loadChapter());
  }

  @override
  void dispose() {
    _request?.cancel();
    _query.dispose();
    _readerImages.close();
    unawaited(_env.close());
    super.dispose();
  }

  Future<void> _run<T>(
    Future<Result<T>> Function(CancellationToken) work,
    void Function(T) accept,
    Future<void> Function() retry,
  ) async {
    _request?.cancel();
    final request = _request = CancellationSource();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
      _report = null;
      _content = null;
      _books = [];
      _chapters = [];
      _images = [];
      _cursor = null;
      _retry = retry;
    });
    final result = await work(request.token);
    if (!mounted || generation != _generation || request.token.isCancelled) {
      return;
    }
    setState(() {
      _loading = false;
      switch (result) {
        case Success(:final value):
          accept(value);
        case Failure(:final failure):
          _failure = failure;
      }
    });
  }

  Future<void> _loadChapter() => _run(
    (token) => _env.novels.loadChapter(
      _chapter,
      mode: ReadMode.refresh,
      cancellation: token,
    ),
    (loaded) {
      final content = loaded.value;
      _content = content;
      final text = content.blocks.whereType<ParagraphBlock>();
      _images = content.blocks.whereType<ImageBlock>().toList();
      _report = {
        'chapter': content.title,
        'contentRevision': content.contentRevision,
        'blocks': content.blocks.length,
        'characters': text.fold<int>(0, (n, p) => n + p.text.runes.length),
        'images': _images.length,
        'preview': text.isEmpty
            ? ''
            : String.fromCharCodes(text.first.text.runes.take(160)),
      };
    },
    _loadChapter,
  );
  Future<void> _detail() => _run(
    (token) => _env.novels.loadDetail(
      _novel,
      mode: ReadMode.refresh,
      cancellation: token,
    ),
    (loaded) {
      _report = {
        'title': loaded.value.summary.title,
        'synopsis': loaded.value.synopsis,
      };
    },
    _detail,
  );
  Future<void> _catalog() => _run(
    (token) => _env.novels.loadCatalog(
      _novel,
      mode: ReadMode.refresh,
      cancellation: token,
    ),
    (loaded) {
      _chapters = loaded.value.flatChapters.toList();
      _report = {
        'volumes': [
          for (final v in loaded.value.volumes)
            {
              'title': v.title,
              'synthetic': v.isSynthetic,
              'chapters': v.chapters.length,
            },
        ],
        'catalogRevision': loaded.value.revision,
      };
    },
    _catalog,
  );
  Future<void> _search({bool next = false}) {
    final cursor = next ? _cursor : null;
    if (!next) _submittedQuery = _query.text;
    return _run(
      (token) => _env.novels.search(
        fixtureSourceId,
        _submittedQuery,
        cursor: cursor,
        cancellation: token,
      ),
      (page) {
        _books = page.items;
        _cursor = page.nextCursor;
        _report = {'results': page.items.length};
      },
      () => _search(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AppScaffold(
      title: scenarioLabel(context, widget.scenario),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(strings.featurePending),
          TextField(
            controller: _query,
            decoration: InputDecoration(labelText: strings.searchTitle),
            onSubmitted: (_) => _search(),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _search(),
                child: Text(strings.searchTitle),
              ),
              OutlinedButton(
                onPressed: _detail,
                child: Text(strings.novelDetailsTitle),
              ),
              OutlinedButton(
                onPressed: _catalog,
                child: Text(strings.catalogTitle),
              ),
              OutlinedButton(
                onPressed: _loadChapter,
                child: Text(strings.readerTitle),
              ),
              FilledButton(
                onPressed: () => AppRoutes(
                  reader: (_, key) => ReaderScreen(
                    chapter: key,
                    repository: _env.novels,
                    images: _readerImages,
                    settings: widget.settings ?? _env.settings,
                    library: widget.library ?? _env.library,
                  ),
                ).open(context, ReaderDestination(_chapter)),
                child: Text(strings.openReaderAction),
              ),
              if (_content case final content?)
                FilledButton(
                  onPressed: () => AppRoutes(
                    reader: (_, key) => ViewportExperiment(
                      content: content,
                      images: _env.images,
                    ),
                  ).open(context, ReaderDestination(content.key)),
                  child: Text(strings.readerExperimentAction),
                ),
              if (widget.scenario == FixtureScenario.revisedContent)
                DropdownButton<int>(
                  value: _env.source.controls.revision,
                  items: [
                    for (final revision in [0, 1])
                      DropdownMenuItem(
                        value: revision,
                        child: Text('revision=$revision'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _env.source.controls.revision = value;
                    unawaited(_loadChapter());
                  },
                ),
            ],
          ),
          if (_loading) const LoadingView(),
          if (_failure case final failure?)
            FailureView(
              failure: failure,
              onRetry: _retry,
              onBack: () => Navigator.of(context).maybePop(),
            ),
          if (_report != null)
            SelectableText(const JsonEncoder.withIndent('  ').convert(_report)),
          for (final book in _books)
            ListTile(
              title: Text(book.title),
              onTap: () {
                _novel = book.key;
                unawaited(_catalog());
              },
            ),
          if (_cursor != null)
            TextButton(
              onPressed: () => _search(next: true),
              child: Text(strings.loadMoreAction),
            ),
          for (final chapter in _chapters)
            ListTile(
              title: Text(chapter.title),
              onTap: () {
                _chapter = chapter.key;
                unawaited(_loadChapter());
              },
            ),
          for (final image in _images)
            DevImagePreview(
              key: ValueKey((image.media, _generation)),
              repository: _env.images,
              ref: image.media,
            ),
        ],
      ),
    );
  }
}

class DevImagePreview extends StatefulWidget {
  const DevImagePreview({
    super.key,
    required this.repository,
    required this.ref,
  });
  final ImageRepository repository;
  final MediaRef ref;
  @override
  State<DevImagePreview> createState() => _DevImagePreviewState();
}

class _DevImagePreviewState extends State<DevImagePreview> {
  CancellationSource? _request;
  MediaLease? _lease;
  AppFailure? _failure;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _request?.cancel();
    unawaited(_lease?.close());
    super.dispose();
  }

  Future<void> _load() async {
    _request?.cancel();
    final request = _request = CancellationSource();
    await _lease?.close();
    _lease = null;
    if (!mounted) return;
    setState(() {
      _failure = null;
    });
    final result = await widget.repository.load(
      widget.ref,
      mode: ReadMode.refresh,
      cancellation: request.token,
    );
    if (!mounted || request.token.isCancelled) {
      if (result case Success(:final value)) await value.value.close();
      return;
    }
    setState(() {
      switch (result) {
        case Success(:final value):
          _lease = value.value;
        case Failure(:final failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failure case final failure?) {
      return FailureView(failure: failure, onRetry: _load);
    }
    final data = _lease?.data;
    if (data == null) return const SizedBox(height: 180, child: LoadingView());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Image.memory(
        (data as MemoryMedia).bytes,
        height: 180,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => FailureView(
          failure: AppFailure(
            kind: FailureKind.parse,
            operation: Operation.media,
            retryPolicy: RetryPolicy.manual,
          ),
          onRetry: _load,
        ),
      ),
    );
  }
}
