// Offline native desktop probe. Uses a fresh temporary storage root only.
// flutter run -d windows --release -t integration_test/desktop/reader_smoke.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/import/desktop_import_source.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/import/import_controller.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/continue_reading.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import '../../test/data/local/support/epub_fixtures.dart';
import '../../test/data/local/support/mixed_epub_fixture.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

T value<T>(Result<T> result) => (result as Success<T>).value;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await Directory.systemTemp.createTemp('shiori-desktop-reader-');
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    FlutterError.presentError(details);
  };
  Timer(const Duration(minutes: 3), () {
    stdout.writeln('DESKTOP_READER_TIMEOUT');
    exit(2);
  });
  runApp(
    ShioriApp(
      routes: AppRoutes(
        home: (_) => _Probe(root: root, errors: errors),
      ),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.root, required this.errors});
  final Directory root;
  final List<String> errors;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  Widget _child = const SizedBox();
  final _root = GlobalKey();
  final _fixture = FixtureEnvironment(scenario: FixtureScenario.longChapter);
  final _settings = FixtureSettingsStore();
  final _token = CancellationSource().token;
  late final AppPaths _paths;
  LocalDatabases? _database;
  late LocalReadingRepository _novels;
  late LocalImageRepository _images;
  late LocalLibraryRepository _library;
  final _passed = <String>[];
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  List<T> _widgets<T extends Widget>() {
    final result = <T>[];
    void visit(Element element) {
      if (element.widget is T) result.add(element.widget as T);
      element.visitChildren(visit);
    }

    (_root.currentContext! as Element).visitChildren(visit);
    return result;
  }

  ReaderContentView get _reader => _widgets<ReaderContentView>().single;
  PagedReaderController get _pages => _reader.viewportController!;

  Future<void> _frame([int milliseconds = 40]) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    check(widget.errors.isEmpty, 'Flutter error: ${widget.errors}');
  }

  Future<void> _until(bool Function() ready, String reason) async {
    for (var i = 0; i < 200; i++) {
      if (ready()) return;
      await _frame();
    }
    throw StateError('Timeout: $reason');
  }

  Future<void> _show(Widget child) async {
    setState(
      () => _child = KeyedSubtree(key: ValueKey(_generation++), child: child),
    );
    await _frame();
    if (child is SizedBox) return;
    await _until(() {
      final readers = _widgets<ReaderContentView>();
      return readers.length == 1 &&
          readers.single.session?.restoreStatus == ReaderRestoreStatus.ready &&
          readers.single.viewportController?.capture() != null &&
          !readers.single.viewportController!.isRestoring;
    }, 'reader ready');
  }

  Future<void> _openDatabase() async {
    _database = value(await LocalDatabases.open(_paths));
    _novels = LocalReadingRepository(
      local: _database!.localBooks,
      online: _fixture.novels,
    );
    _images = LocalImageRepository(
      local: _database!.localBooks,
      online: _fixture.images,
    );
    _library = LocalLibraryRepository(_database!.users);
  }

  Future<List<LocalBookRecord>> _importBooks() async {
    final body = List.generate(
      120,
      (i) => '第 $i 段。${'离线桌面阅读，检查翻页和恢复位置。' * 12}',
    ).join('\n');
    final txt = File(p.join(widget.root.path, 'desktop.txt'));
    await txt.writeAsString('\ufeff第一章 星空\n$body\n第二章 日出\n$body');
    final rich = epubFiles();
    rich['OPS/text/a.xhtml'] = utf8.encode('''<html><body><h1>图文混排</h1>
<p><a href="#target">跳到目标</a>，行内图片<img style="width:1em;height:1em" src="../images/星 空.png"/>与<strong>粗体</strong>、<em>斜体</em>。</p>
${List.generate(100, (i) => '<p>段落 $i ${'混排正文与翻页检查。' * 24}</p>').join()}
<h2 id="target">锚点目标</h2><p>最后一段。</p></body></html>''');
    final epub = File(p.join(widget.root.path, 'rich.epub'));
    await epub.writeAsBytes(zipFiles(rich));
    final fixed = File(p.join(widget.root.path, 'fixed.epub'));
    await fixed.writeAsBytes(zipFiles(mixedEpub()));
    final imports = ImportController(
      source: DesktopImportSource(
        inbox: _paths.importInbox,
        selectFiles: () async => [
          XFile(txt.path),
          XFile(epub.path),
          XFile(fixed.path),
        ],
      ),
      store: _database!.localBooks,
      decoder: const BookDecoder(),
      addToShelf: true,
    );
    try {
      await imports.start();
      await imports.pick();
      await imports.submit();
      check(
        imports.succeededCount == 3,
        'TXT/EPUB import: ${imports.problem}; '
        '${imports.items.map((item) => '${item.candidate.name}: ${item.problem}').join(', ')}',
      );
      return imports.items.map((item) => item.result!).toList();
    } finally {
      await imports.shutdown();
      imports.dispose();
    }
  }

  Future<void> _read(ChapterKey chapter) => _show(
    BookReaderScreen(
      chapter: chapter,
      repository: _novels,
      library: _library,
      images: _images,
      settings: _settings,
    ),
  );

  Future<void> _exercise(ChapterKey chapter, String name) async {
    await _read(chapter);
    final start = _pages.capture()!;
    await _pages.next();
    await _frame();
    final second = _pages.capture()!;
    check(second.chapterFraction > start.chapterFraction, '$name forward page');
    await _pages.previous();
    await _frame();
    check(
      _pages.capture()!.blockKey == start.blockKey &&
          (_pages.capture()!.blockFraction - start.blockFraction).abs() < .001,
      '$name reverse page',
    );
    await _pages.next();
    await _pages.next();
    await _frame();
    await _reader.session!.flushProgress();
    final saved = value(
      await _library.getProgress(chapter.novelKey, cancellation: _token),
    )!;
    check(saved.position.chapterFraction > 0, '$name persisted progress');
    await _show(const SizedBox());
    await _frame(150);
    await _database!.close();
    _database = null;
    await _openDatabase();
    await _show(
      ContinueReadingScreen(
        novel: chapter.novelKey,
        repository: _novels,
        library: _library,
        images: _images,
        settings: _settings,
      ),
    );
    final restored = _pages.capture()!;
    check(
      _reader.content.key == saved.chapterKey &&
          restored.blockKey == saved.position.blockKey &&
          (restored.blockFraction - saved.position.blockFraction).abs() < .001,
      '$name reopen/continue',
    );
    await _reader.session!.flushProgress();
    await _show(const SizedBox());
    _passed.add(
      '$name: forward/reverse, persisted semantic position, reopen/continue',
    );
  }

  Future<void> _run() async {
    try {
      _paths = AppPaths(
        support: widget.root,
        temporary: widget.root,
        environment: StorageEnvironment.development,
      );
      await _settings.save(
        ReaderSettings(controlsHintSeen: true),
        cancellation: _token,
      );
      await _openDatabase();
      final books = await _importBooks();
      await _exercise(books[0].content.chapters.first.key, 'TXT');
      final rich = books[1].content;
      check(
        rich.chapters.first.blocks.whereType<ParagraphBlock>().any(
          (block) => block.inlineImages.isNotEmpty,
        ),
        'inline image fixture',
      );
      await _exercise(rich.chapters.first.key, 'EPUB rich reflow');
      await _read(rich.chapters.first.key);
      final link = _reader.session!.contentLinks.firstWhere(
        (link) => link.label == '跳到目标',
      );
      _reader.actions.contentLink!(link);
      await _until(
        () =>
            !_pages.isRestoring &&
            _pages.capture()?.blockKey == link.targetBlockKey,
        'EPUB anchor link',
      );
      check(_pages.capture()!.chapterFraction > .8, 'EPUB link position');
      await _reader.session!.flushProgress();
      await _show(const SizedBox());
      _passed.add(
        'EPUB: inline image parsed and same-chapter link restored to target',
      );
      final fixed = books[2].content;
      await _read(fixed.chapters.first.key);
      check(
        _reader.content.blocks.whereType<ImageBlock>().length == 1,
        'fixed image native renderer',
      );
      await _until(
        () => _widgets<RawImage>().any((image) => image.image != null),
        'fixed image decoded',
      );
      _reader.actions.nextChapter!();
      await _until(
        () =>
            _widgets<ReaderContentView>().length == 1 &&
            _reader.content.key == fixed.chapters[1].key,
        'fixed next chapter',
      );
      _reader.actions.previousChapter!();
      await _until(
        () =>
            _widgets<ReaderContentView>().length == 1 &&
            _reader.content.key == fixed.chapters.first.key &&
            !_pages.isRestoring,
        'fixed previous chapter',
      );
      await _reader.session!.flushProgress();
      await _show(const SizedBox());
      _passed.add('EPUB fixed image: native decode and next/previous chapter');
      await _exercise(
        fixtureChapterKey(FixtureScenario.longChapter),
        'Offline online-source fixture',
      );
      if (!mounted) throw StateError('Probe left before completion');
      final size = MediaQuery.sizeOf(context);
      check(
        size.width >= 1000 && size.height >= 600,
        'desktop viewport: $size',
      );
      stdout.writeln(
        'DESKTOP_READER_PASS ${jsonEncode({
          'viewport': [size.width, size.height],
          'checks': _passed,
        })}',
      );
      await _database!.close();
      _database = null;
      await _fixture.close();
      runApp(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final ownedRoot = widget.root.absolute;
      check(
        ownedRoot.parent.path == Directory.systemTemp.absolute.path &&
            ownedRoot.uri.pathSegments
                .where((part) => part.isNotEmpty)
                .last
                .startsWith('shiori-desktop-reader-'),
        'temporary root ownership',
      );
      await ownedRoot.delete(recursive: true);
      exit(0);
    } catch (error, stack) {
      stderr.writeln('DESKTOP_READER_FAIL $error\n$stack');
      exit(1);
    }
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(key: _root, child: _child);
}
