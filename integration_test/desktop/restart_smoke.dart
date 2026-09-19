// Run with run_restart_smoke.ps1. Each phase runs in a separate native process.
// Uses ProductionApp with isolated paths/preferences, never the user's library.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:shiori/app/production_app.dart';
import 'package:shiori/data/cache/local_cache_management.dart';
import 'package:shiori/data/import/desktop_import_source.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/media/persistent_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/shared/source_image.dart';

import '../../test/data/local/support/epub_fixtures.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

T value<T>(Result<T> result) => (result as Success<T>).value;

class _Paths extends AppPaths {
  _Paths(Directory root)
    : id = p.basename(root.path),
      super(
        support: root,
        temporary: root,
        environment: StorageEnvironment.development,
      );
  final String id;
  @override
  String get settingsKey => 'shiori.desktop-restart.$id.reader';
  @override
  String get appSettingsKey => 'shiori.desktop-restart.$id.appearance';
}

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('This probe must stay offline');
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  check(args.length == 2, 'Expected owned root and lifecycle/restart phase');
  final root = Directory(args[0]).absolute;
  final phase = args[1];
  check(
    [
      'plain',
      'webview',
      'webview-cycle',
      'webview-early-close',
      'prepare',
      'restart',
      'killed',
    ].contains(phase),
    'Unknown phase',
  );
  check(
    await File(p.join(root.path, 'restart-probe.owner')).readAsString() ==
        'shiori-desktop-restart',
    'Root must be created by the restart runner',
  );
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    FlutterError.presentError(details);
  };
  final network = _NoNetwork();
  HttpOverrides.global = network;
  final paths = _Paths(root);
  final app = GlobalKey();
  runApp(
    KeyedSubtree(
      key: app,
      child: ProductionApp(resolvePaths: () async => paths),
    ),
  );
  final probe = _Probe(root, phase, paths, app, errors, network);
  final timeout = Timer(const Duration(minutes: 2), () => exit(2));
  try {
    await probe.run();
    timeout.cancel();
    // Remain alive: the runner closes the native window or kills the process.
  } catch (error, stack) {
    await probe.report('failed', {'error': '$error', 'stack': '$stack'});
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

class _Probe {
  _Probe(
    this.root,
    this.phase,
    this.paths,
    this.app,
    this.errors,
    this.network,
  );
  final Directory root;
  final String phase;
  final _Paths paths;
  final GlobalKey app;
  final List<String> errors;
  final _NoNetwork network;
  final token = CancellationSource().token;
  final passed = <String>[];
  File get checkpoint => File(p.join(root.path, 'checkpoint.json'));

  List<T> widgets<T extends Widget>() {
    final result = <T>[];
    void visit(Element e) {
      if (e.widget is T) result.add(e.widget as T);
      e.visitChildren(visit);
    }

    app.currentContext?.visitChildElements(visit);
    return result;
  }

  ReadingHome get home => widgets<ReadingHome>().single;
  ImportOverlay get overlay => widgets<ImportOverlay>().single;
  ReaderContentView get reader => widgets<ReaderContentView>().single;

  Future<void> frame() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    check(errors.isEmpty, 'Flutter errors: $errors');
  }

  Future<void> until(FutureOr<bool> Function() ready, String reason) async {
    for (var i = 0; i < 300; i++) {
      if (await ready()) return;
      await frame();
    }
    throw StateError('Timed out: $reason');
  }

  Future<void> report(String status, Map<String, Object?> details) async {
    final pending = File(p.join(root.path, '$phase.json.tmp'));
    await pending.writeAsString(
      jsonEncode({
        'status': status,
        'pid': pid,
        'phase': phase,
        'checks': passed,
        'networkAttempts': network.attempts,
        ...details,
      }),
      flush: true,
    );
    await pending.rename(p.join(root.path, '$phase.json'));
  }

  Future<void> stageAndImport() async {
    final body = List.generate(
      100,
      (i) => '第 $i 段。${'跨进程重启后，应保留阅读位置与设置。' * 18}',
    );
    final txt = File(p.join(root.path, 'restart.txt'));
    await txt.writeAsString('\ufeff第一章\n${body.join('\n')}');
    final files = epubFiles(toc: false);
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><body><h1>重启验收</h1>'
      '<img src="../images/星 空.png"/>${body.map((s) => '<p>$s</p>').join()}'
      '</body></html>',
    );
    final epub = File(p.join(root.path, 'restart.epub'));
    await epub.writeAsBytes(zipFiles(files));
    // Deterministic file selection; the production controller performs the
    // actual import/parse/publish. No fake database or local-book repository.
    final incoming = DesktopImportSource(
      inbox: paths.importInbox,
      selectFiles: () async => [XFile(txt.path), XFile(epub.path)],
    );
    await incoming.pick();
    await incoming.close();
    await overlay.controller.refresh();
    overlay.controller.open();
    await overlay.controller.submit();
    check(overlay.controller.succeededCount == 2, 'TXT/EPUB import failed');
    await overlay.controller.finish();
    passed.add('Production import: TXT + EPUB');
    // Subsequent reads must use the managed copies, not the import originals.
    await txt.delete();
    await epub.delete();
  }

  Future<void> cacheFixture({required bool seed}) async {
    final cache = home.cache! as LocalCacheManagement;
    final fixture = FixtureNovelSource(scenario: FixtureScenario.twentyImages);
    final chapter = fixture.data.content(FixtureScenario.twentyImages);
    final ref = chapter.blocks.whereType<ImageBlock>().first.media;
    if (seed) {
      final records = NovelRecordStore(
        cache.db,
        coordinator: cache.coordinator,
      );
      value(
        await records.writeChapter(
          chapter,
          fetchedAt: DateTime.now(),
          parserVersion: 1,
          cancellation: token,
        ),
      );
      final writer = PersistentImageRepository(
        network: MemoryImageRepository(resolve: (_) => fixture),
        db: cache.db,
        paths: paths,
        coordinator: cache.coordinator,
      );
      final lease = value(
        await writer.load(ref, mode: ReadMode.cacheFirst, cancellation: token),
      ).value;
      check(lease.persistence == MediaPersistence.persistedLocal, 'Cache seed');
      await lease.close();
      await writer.close();
    }
    final loaded = value(
      await home.repository.loadChapter(
        chapter.key,
        mode: ReadMode.cacheOnly,
        cancellation: token,
      ),
    );
    check(loaded.value.key == chapter.key, 'Cached chapter unavailable');
    final lease = value(
      await home.images!.load(
        ref,
        mode: ReadMode.cacheOnly,
        cancellation: token,
      ),
    ).value;
    final image = await decodeSourceImage(lease.data, 64);
    check(image.image.width > 0, 'Cached image decode');
    image.image.dispose();
    await lease.close();
    passed.add('Production cache-only chapter + decoded cached image');
  }

  Future<ReaderSettingsPanel> settingsPanel() async {
    if (!widgets<TextButton>().any(
      (w) => w.child is Text && (w.child as Text).data == 'Aa',
    )) {
      widgets<CallbackShortcuts>()
          .firstWhere(
            (w) => w.bindings.containsKey(
              const SingleActivator(LogicalKeyboardKey.f2),
            ),
          )
          .bindings[const SingleActivator(LogicalKeyboardKey.f2)]!();
      await frame();
    }
    widgets<TextButton>()
        .firstWhere((w) => w.child is Text && (w.child as Text).data == 'Aa')
        .onPressed!();
    await until(
      () => widgets<ReaderSettingsPanel>().isNotEmpty,
      'settings panel',
    );
    return widgets<ReaderSettingsPanel>().single;
  }

  void closeSettings() {
    widgets<IconButton>()
        .firstWhere(
          (w) => w.icon is Icon && (w.icon as Icon).icon == Icons.close,
        )
        .onPressed!();
  }

  Map<String, Object?> position(ReaderPosition position) => {
    'blockKey': position.blockKey,
    'blockIndex': position.blockIndex,
    'blockFraction': position.blockFraction,
    'chapterFraction': position.chapterFraction,
    'revision': position.contentRevision,
  };

  Future<void> webViewLifecycle() async {
    BuildContext? shelfContext;
    void visit(Element element) {
      if (element.widget is BookshelfView) shelfContext = element;
      element.visitChildren(visit);
    }

    app.currentContext!.visitChildElements(visit);
    final navigator = Navigator.of(shelfContext!);
    final image = base64Encode(epubFiles()['OPS/images/星 空.png']!);
    final cycles = phase == 'webview-cycle' ? 10 : 1;
    final earlyClose = phase == 'webview-early-close';
    final earlyOutcome = File(p.join(root.path, 'early-close-outcome.txt'));
    for (var i = 0; i < cycles; i++) {
      final ready = Completer<void>();
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: EpubLayoutPage(
                html:
                    '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
                    '<body><h1>离线特殊页 $i</h1><p>原生 WebView 关闭验收</p>'
                    '<img src="data:image/png;base64,$image"></body></html>',
                onCenterTap: () {},
                onReady: () {
                  if (earlyClose) {
                    earlyOutcome.writeAsStringSync('ready', flush: true);
                  }
                  if (!ready.isCompleted) ready.complete();
                },
                onFailed: () {
                  if (earlyClose) {
                    earlyOutcome.writeAsStringSync('failed', flush: true);
                    return;
                  }
                  if (!ready.isCompleted) {
                    ready.completeError(StateError('Native WebView failed'));
                  }
                },
              ),
            ),
          ),
        ),
      );
      if (earlyClose) {
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        do {
          WidgetsBinding.instance.scheduleFrame();
          await WidgetsBinding.instance.endOfFrame;
          check(!ready.isCompleted, 'Missed the close-before-ready window');
          check(
            !earlyOutcome.existsSync(),
            'WebView failed before early close',
          );
          check(errors.isEmpty, 'Flutter errors: $errors');
          check(DateTime.now().isBefore(deadline), 'WebView mount timed out');
        } while (widgets<InAppWebView>().isEmpty);
        // The production platform widget has mounted and completed a frame.
        // Do not wait for attachment/load callbacks before requesting closure.
        passed.add(
          'Production InAppWebView mounted for a frame before onReady',
        );
        return;
      }
      await ready.future.timeout(const Duration(seconds: 25));
      await frame();
      if (i + 1 < cycles) {
        navigator.pop();
        await until(
          () => widgets<EpubLayoutPage>().isEmpty,
          'WebView route disposal',
        );
      }
    }
    // Close the native process with the last real WebView still attached.
    passed.add(
      'Loaded $cycles production EpubLayoutPage instances; last view remains live',
    );
  }

  Future<void> run() async {
    await until(
      () =>
          widgets<BookshelfView>().isNotEmpty &&
          widgets<BookshelfView>().single.controller.shelfReady,
      'production home',
    );
    if ([
      'plain',
      'webview',
      'webview-cycle',
      'webview-early-close',
    ].contains(phase)) {
      if (phase != 'plain') await webViewLifecycle();
      check(
        network.attempts == 0 && errors.isEmpty,
        'No network or Flutter errors',
      );
      passed.add('Production startup without library mutations');
      final earlyClose = phase == 'webview-early-close';
      await report(earlyClose ? 'ready-to-close' : 'passed', {
        if (earlyClose) 'webViewMounted': true,
        if (earlyClose) 'readyAtSignal': false,
      });
      return;
    }
    Map<String, dynamic>? expected;
    if (phase == 'prepare') {
      check(
        widgets<BookshelfView>().single.controller.books.isEmpty,
        'Fresh root',
      );
      await stageAndImport();
    } else {
      expected =
          jsonDecode(await checkpoint.readAsString()) as Map<String, dynamic>;
      check(expected['pid'] != pid, 'Must use a new process');
    }
    await until(
      () => widgets<BookshelfView>().single.controller.books.length == 2,
      'shelf restored',
    );
    final books = widgets<BookshelfView>().single.controller.books;
    final book = books.firstWhere((b) => b.snapshot.title == '离线星空').snapshot;
    if (expected != null) {
      check(
        jsonEncode(book.key.toJson()) == jsonEncode(expected['book']),
        'Same imported book',
      );
    }
    passed.add('Production bookshelf: two persisted imported books');
    await cacheFixture(seed: phase == 'prepare');
    final cover = value(
      await home.images!.load(
        book.cover!,
        mode: ReadMode.cacheOnly,
        cancellation: token,
      ),
    ).value;
    final decoded = await decodeSourceImage(cover.data, 64);
    check(decoded.image.width > 0, 'Managed local image');
    decoded.image.dispose();
    await cover.close();
    passed.add('Managed EPUB image decodes without original file');
    // Same callback as clicking the actual bookshelf: ContinueReadingScreen.
    widgets<BookshelfView>().single.onOpen(book.key);
    await until(
      () =>
          widgets<ReaderContentView>().length == 1 &&
          reader.session?.restoreStatus == ReaderRestoreStatus.ready &&
          reader.viewportController?.capture() != null &&
          !reader.viewportController!.isRestoring,
      'ContinueReading restore',
    );
    if (expected != null) {
      final restored = position(reader.viewportController!.capture()!);
      check(
        jsonEncode(restored) == jsonEncode(expected['position']),
        'Semantic position differs: $restored vs ${expected['position']}',
      );
      check(
        jsonEncode(reader.content.key.toJson()) ==
            jsonEncode(expected['chapter']),
        'Chapter restore',
      );
      final panel = await settingsPanel();
      check(
        jsonEncode(panel.preferences.value.toJson()) ==
            jsonEncode(expected['settings']),
        'Settings did not survive process restart',
      );
      closeSettings();
      await frame();
      passed.add(
        'ContinueReading: same chapter, block, fraction and reader settings',
      );
    }
    if (phase != 'killed') {
      final panel = await settingsPanel();
      final target = panel.preferences.value.copyWith(
        fontSize: phase == 'prepare' ? 23 : 25,
        lineHeight: 1.8,
        paragraphSpacing: 24,
        controlsHintSeen: true,
      );
      panel.preferences.update(target);
      closeSettings();
      await until(
        () async =>
            value(await reader.settings!.load(cancellation: token)) == target,
        'preferences platform write',
      );
      await until(
        () => !reader.viewportController!.isRestoring,
        'settings repagination',
      );
      for (var i = 0; i < 4; i++) {
        await reader.viewportController!.next();
        await frame();
      }
      final anchor = reader.viewportController!.capture()!;
      check(anchor.chapterFraction > 0, 'Moved away from book start');
      // Wait for the real reader's normal debounce write. Do not explicitly
      // flush or close the database before the runner kills this process.
      await until(() async {
        final saved = value(
          await home.library.getProgress(book.key, cancellation: token),
        );
        return saved != null &&
            jsonEncode(position(saved.position)) ==
                jsonEncode(position(anchor));
      }, 'automatic progress persistence');
      await checkpoint.writeAsString(
        jsonEncode({
          'pid': pid,
          'book': book.key.toJson(),
          'chapter': reader.content.key.toJson(),
          'settings': target.toJson(),
          'position': position(anchor),
        }),
        flush: true,
      );
      passed.add(
        'Changed settings and progress committed by production write paths',
      );
    }
    check(
      network.attempts == 0 && errors.isEmpty,
      'No network or Flutter errors',
    );
    await report(phase == 'restart' ? 'ready-to-kill' : 'passed', {});
  }
}
