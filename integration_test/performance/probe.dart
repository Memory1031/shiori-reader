// Explicit profile entry. Only the dedicated test003 directory is touched.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show FrameTiming, FramePhase;
import 'package:shiori/shared/source_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/app/production_app.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/local/record_codec.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/media/persistent_image_repository.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/reader_viewport.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

final started = Stopwatch()..start();
late Directory output;
final report = <String, Object?>{};
Future<void> save() =>
    File('${output.path}/report.json').writeAsString(jsonEncode(report));
void check(bool ok, String reason) {
  if (!ok) throw StateError(reason);
}

T value<T>(Result<T> result) => (result as Success<T>).value;
final token = CancellationSource().token;

Future<void> main() async {
  started
      .start(); // Force initialization at entry, not at the first metric read.
  WidgetsFlutterBinding.ensureInitialized();
  output = Directory(
    '${(await getApplicationSupportDirectory()).path}/test003',
  );
  await output.create(recursive: true);
  final paths = AppPaths(
    support: output,
    temporary: output,
    environment: StorageEnvironment.development,
  );
  if (!await File('${output.path}/seeded').exists()) {
    final db = value(await LocalDatabases.open(paths));
    await db.users.transaction(() async {
      for (var i = 0; i < 500; i++) {
        final summary = NovelSummary(
          key: NovelKey(sourceId: SourceId('perf'), novelId: '$i'),
          title: '性能书架 $i',
        );
        await db.users.customStatement(
          'INSERT INTO bookshelf VALUES(?,?,?,?,?)',
          ['perf', '$i', RecordCodec.summary(summary), 1, 1],
        );
      }
    });
    await db.close();
    await File('${output.path}/seeded').writeAsString('500');
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('TEST003 SEEDED'))),
      ),
    );
    return;
  }
  final suite = await File('${output.path}/run_suite').exists();
  if (suite) {
    runApp(
      ShioriApp(
        routes: AppRoutes(home: (_) => _Suite(paths: paths)),
      ),
    );
  } else {
    runApp(ProductionApp(resolvePaths: () async => paths));
    Timer? poll;
    poll = Timer.periodic(const Duration(milliseconds: 10), (_) async {
      BookshelfView? shelf;
      void visit(Element e) {
        if (e.widget is BookshelfView) shelf = e.widget as BookshelfView;
        e.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
      if (shelf?.controller.shelfReady == true &&
          shelf!.controller.sorted.length == 500) {
        poll!.cancel();
        await WidgetsBinding.instance.endOfFrame;
        report['coldMainToInteractiveMs'] = started.elapsedMilliseconds;
        report['shelfItems'] = 500;
        report['refreshHz'] =
            ui.PlatformDispatcher.instance.views.first.display.refreshRate;
        report['status'] = 'COLD_PASS';
        await save();
        debugPrint('TEST003 COLD ${jsonEncode(report)}');
      }
    });
  }
}

class _Suite extends StatefulWidget {
  const _Suite({required this.paths});
  final AppPaths paths;
  @override
  State<_Suite> createState() => _SuiteState();
}

class _SuiteState extends State<_Suite> with TickerProviderStateMixin {
  Widget child = const Center(child: Text('TEST003 PREPARING'));
  final root = GlobalKey();
  final timings = <FrameTiming>[];
  final samples = <Map<String, Object?>>[];
  final memory = <Map<String, Object?>>[];
  final source = _Images();
  final settings = FixtureSettingsStore();
  final owner = CacheCoordinator();
  LocalDatabases? db;
  DefaultNovelRepository? novels;
  PersistentImageRepository? images;
  _Library? library;
  _Vm? vm;
  Timer? rssTimer;
  int peak = 0;
  @override
  void initState() {
    super.initState();
    unawaited(run());
  }

  void collect(List<FrameTiming> frames) => timings.addAll(frames);
  void walk(void Function(Element) visit) {
    void recurse(Element e) {
      visit(e);
      e.visitChildren(recurse);
    }

    (root.currentContext! as Element).visitChildren(recurse);
  }

  ReaderViewportController? get viewport {
    ReaderViewportController? found;
    walk((e) {
      if (e.widget case ReaderViewport(:final controller)) found = controller;
    });
    return found;
  }

  Future<void> settle([int milliseconds = 350]) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> until(bool Function() ready, String name) async {
    for (var i = 0; i < 100; i++) {
      if (ready()) return;
      await settle(50);
    }
    throw StateError('timeout $name');
  }

  Future<void> show(Widget next) async {
    setState(() => child = next);
    await settle();
  }

  ReaderPosition at(ChapterContent c, int index, [double fraction = 0]) =>
      ReaderPosition(
        contentRevision: c.contentRevision,
        blockKey: c.blocks[index].blockKey,
        blockIndex: index,
        blockFraction: fraction,
        chapterFraction: (index + fraction) / c.blocks.length,
      );
  Future<void> reader(ChapterContent content) async {
    await show(
      ReaderScreen(
        key: ValueKey(content.key),
        chapter: content.key,
        repository: novels!,
        settings: settings,
        library: library,
        images: images,
      ),
    );
    await until(() => viewport != null && !viewport!.isRestoring, 'reader');
  }

  Future<void> scroll(Duration duration) async {
    ScrollableState? scrolling;
    walk((e) {
      if (e.widget is! ReaderViewport) return;
      void find(Element node) {
        if (node is StatefulElement && node.state is ScrollableState) {
          scrolling = node.state as ScrollableState;
        }
        node.visitChildren(find);
      }

      e.visitChildren(find);
    });
    check(scrolling != null, 'reader scrollable');
    final drag = scrolling!.position.drag(
      DragStartDetails(globalPosition: Offset(100, 400)),
      () {},
    );
    final animation = AnimationController(vsync: this, duration: duration);
    var previous = 0.0;
    animation.addListener(() {
      final delta = (animation.value - previous) * -6000;
      previous = animation.value;
      drag.update(
        DragUpdateDetails(
          delta: Offset(0, delta),
          primaryDelta: delta,
          globalPosition: const Offset(100, 400),
        ),
      );
    });
    try {
      await animation.forward().orCancel;
    } finally {
      drag.end(DragEndDetails(primaryVelocity: 0));
      animation.dispose();
    }
  }

  double p95(List<double> values) {
    values.sort();
    return values[((values.length - 1) * .95).ceil()];
  }

  Future<void> checkpoint(int cycle) async {
    final allocation = await vm!.call('getAllocationProfile', {
      'isolateId': developer.Service.getIsolateId(Isolate.current),
      'gc': true,
    });
    await settle(150);
    memory.add({
      'cycle': cycle,
      'rss': ProcessInfo.currentRss,
      'peakRss': peak,
      'heap': allocation['memoryUsage'],
      'encodedRetained': images!.network.retainedBytes,
      'activeBodies': source.active,
    });
    report['memory'] = memory;
    await save();
  }

  Future<void> seedChapter(ChapterContent c) async {
    final records = NovelRecordStore(db!.cache);
    value(
      await records.writeCatalog(
        Catalog(
          novelKey: c.key.novelKey,
          volumes: [
            Volume(
              groupId: 'perf',
              title: 'perf',
              chapters: [
                Chapter(
                  key: c.key,
                  title: c.title,
                  ordinal: 0,
                  volumeGroupId: 'perf',
                ),
              ],
            ),
          ],
        ),
        fetchedAt: fixtureEpoch,
        parserVersion: 1,
        cancellation: token,
      ),
    );
    value(
      await records.writeChapter(
        c,
        fetchedAt: fixtureEpoch,
        parserVersion: 1,
        cancellation: token,
      ),
    );
    value(
      await records.writeDetail(
        NovelDetail(
          summary: NovelSummary(key: c.key.novelKey, title: c.title),
        ),
        fetchedAt: fixtureEpoch,
        parserVersion: 1,
        cancellation: token,
      ),
    );
  }

  Future<void> run() async {
    try {
      await settings.save(
        ReaderSettings(mode: ReaderMode.scroll),
        cancellation: token,
      );
      report['status'] = 'RUNNING';
      report['refreshHz'] =
          ui.PlatformDispatcher.instance.views.first.display.refreshRate;
      await save();
      db = value(await LocalDatabases.open(widget.paths));
      library = _Library(db!.users);
      novels = createNovelRepository(
        sources: SourceRegistry([]),
        now: () => fixtureEpoch,
        cache: db!.cache,
        coordinator: owner,
      );
      await source.prepare();
      images = PersistentImageRepository(
        network: MemoryImageRepository(resolve: (_) => source),
        db: db!.cache,
        paths: widget.paths,
        coordinator: owner,
      );
      vm = await _Vm.open();
      await vm!.call('setVMTimelineFlags', {
        'recordedStreams': ['Dart', 'GC'],
      });
      rssTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final rss = ProcessInfo.currentRss;
        if (rss > peak) peak = rss;
      });
      WidgetsBinding.instance.addTimingsCallback(collect);
      if (!await File('${output.path}/images_only').exists()) {
        final long = const FixtureData().content(FixtureScenario.longChapter);
        await seedChapter(long);
        for (var run = 1; run <= 3; run++) {
          await reader(long);
          viewport!.restore(at(long, 0));
          await settle();
          final beforeBuild = viewport!.buildCount;
          final beforeWrite = library!.writes;
          final contentWidgets = <Widget>{};
          walk((e) {
            if (e.widget is ReaderContentView) contentWidgets.add(e.widget);
          });
          timings.clear();
          await scroll(const Duration(seconds: 10));
          await settle(400);
          final frames = List<FrameTiming>.of(timings);
          check(frames.length > 300, 'insufficient scroll frames');
          check(
            viewport!.capture()!.blockIndex > 20,
            'scroll did not advance content',
          );
          check(library!.writes > beforeWrite, 'progress was not measured');
          final afterWidgets = <Widget>{};
          walk((e) {
            if (e.widget is ReaderContentView) afterWidgets.add(e.widget);
          });
          samples.add({
            'run': run,
            'frames': frames.length,
            'endBlock': viewport!.capture()!.blockIndex,
            'uiP95Ms': p95(
              frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList(),
            ),
            'rasterP95Ms': p95(
              frames
                  .map((f) => f.rasterDuration.inMicroseconds / 1000)
                  .toList(),
            ),
            'built': viewport!.buildCount - beforeBuild,
            'mounted': viewport!.mountedCount,
            'regularWrites': library!.writes - beforeWrite,
            'sameContentWidget':
                contentWidgets.length == 1 &&
                afterWidgets.contains(contentWidgets.single),
            'timingsUs': frames
                .map(
                  (f) => [
                    f.timestampInMicroseconds(FramePhase.vsyncStart),
                    f.buildDuration.inMicroseconds,
                    f.rasterDuration.inMicroseconds,
                  ],
                )
                .toList(),
          });
          report['scroll'] = samples;
          await save();
          await show(const SizedBox());
          report['lifecycleWritesAfterRun$run'] =
              library!.writes -
              beforeWrite -
              (samples.last['regularWrites'] as int);
        }
        final deep = ReaderViewportController();
        await show(
          ReaderViewport(
            content: long,
            controller: deep,
            initialPosition: at(long, 1499),
          ),
        );
        await until(() => !deep.isRestoring, 'deep restore');
        report['deep'] = {
          'block': deep.capture()?.blockIndex,
          'built': deep.buildCount,
          'mounted': deep.mountedCount,
        };
        check(
          deep.capture()?.blockIndex == 1499 && deep.buildCount < 80,
          'deep budget',
        );
        final extreme = const FixtureData().content(
          FixtureScenario.extremeParagraph,
        );
        final paged = PagedReaderController();
        await show(
          PagedReaderViewport(
            content: extreme,
            controller: paged,
            initialPosition: at(extreme, 0, .75),
          ),
        );
        await settle();
        report['extreme'] = {
          'fraction': paged.capture()?.blockFraction,
          'measuredChunks': paged.measuredChunks,
        };
        check(
          (paged.capture()!.blockFraction - .75).abs() < .002,
          'extreme mapping',
        );
        final restored = ReaderViewportController();
        await show(
          ReaderViewport(
            content: extreme,
            controller: restored,
            initialPosition: paged.capture(),
          ),
        );
        await until(() => !restored.isRestoring, 'extreme restore');
        report['extremeVertical'] = {
          'fraction': restored.capture()?.blockFraction,
          'built': restored.buildCount,
        };
        check(
          (restored.capture()!.blockFraction - .75).abs() < .002,
          'extreme vertical',
        );
      }
      if (!await File('${output.path}/scroll_only').exists()) {
        for (var cycle = 1; cycle <= 10; cycle++) {
          final c = ChapterContent(
            key: ChapterKey(
              novelKey: NovelKey(sourceId: SourceId('perf'), novelId: 'images'),
              chapterId: '$cycle',
            ),
            title: 'Images $cycle',
            blocks: [
              for (var i = 0; i < 20; i++)
                ImageBlock(
                  media: MediaRef(
                    sourceId: SourceId('perf'),
                    mediaId: '$cycle-$i',
                  ),
                  width: 1200,
                  height: i == 19 ? 6000 : 1800,
                  alt: 'Synthetic $i',
                ),
            ],
          );
          await seedChapter(c);
          await reader(c);
          var decoded = 0;
          var maxPixels = 0;
          for (var i = 0; i < 20; i++) {
            viewport!.restore(at(c, i));
            await settle(150);
            await until(() {
              var found = false;
              walk((e) {
                if (e.widget case SourceImage(:final media)) {
                  if (media.mediaId != '$cycle-$i') return;
                  void decodedImage(Element node) {
                    if (node.widget case RawImage(:final image?)) {
                      found = true;
                      final pixels = image.width * image.height;
                      if (pixels > maxPixels) maxPixels = pixels;
                    }
                    node.visitChildren(decodedImage);
                  }

                  e.visitChildren(decodedImage);
                }
              });
              return found;
            }, 'image decode');
            decoded++;
          }
          report['images$cycle'] = {
            'visited': decoded,
            'maxMountedPixels': maxPixels,
            'sourceCalls': source.calls,
          };
          check(maxPixels <= 4000000, 'decode pixels');
          await show(const SizedBox());
          await settle(300);
          await checkpoint(cycle);
        }
      }
      report['status'] = 'PASS';
      final trace = await vm!.call('getVMTimeline', {});
      await File(
        '${output.path}/timeline.json',
      ).writeAsString(jsonEncode(trace));
    } catch (e, st) {
      report['status'] = 'FAIL';
      report['error'] = e.toString();
      report['stack'] = st.toString();
    } finally {
      WidgetsBinding.instance.removeTimingsCallback(collect);
      rssTimer?.cancel();
      await show(Center(child: Text('TEST003 ${report['status']}')));
      await images?.close();
      await novels?.close();
      await owner.close();
      await db?.close();
      await vm?.close();
      await save();
      debugPrint('TEST003 ${report['status']}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: KeyedSubtree(key: root, child: child),
    ),
  );
}

class _Library extends LocalLibraryRepository {
  _Library(super.db);
  int writes = 0;
  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress progress, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
  }) async {
    final result = await super.saveProgress(
      progress,
      stamp: stamp,
      cancellation: cancellation,
    );
    if (result is Success<bool> && result.value) writes++;
    return result;
  }
}

class _Images implements SourceMedia {
  final bytes = <Uint8List>[];
  int calls = 0, active = 0;
  Future<void> prepare() async {
    for (var index = 0; index < 20; index++) {
      final height = index == 19 ? 6000 : 1800;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 1200, height.toDouble()),
        Paint()..color = Color.fromARGB(255, 30 + index * 10, 120, 180),
      );
      for (var y = 0; y < height; y += 100) {
        canvas.drawRect(
          Rect.fromLTWH(0, y.toDouble(), 600, 50),
          Paint()..color = Colors.amber,
        );
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(1200, height);
      bytes.add(
        (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List(),
      );
      image.dispose();
      picture.dispose();
    }
  }

  @override
  Future<Result<SourceMediaBody>> openMedia(
    MediaRef ref, {
    required int maxBytes,
    required CancellationToken cancellation,
  }) async {
    calls++;
    active++;
    final index = int.parse(ref.mediaId.split('-').last);
    final tall = index == 19;
    final data = bytes[index];
    return Success(
      FixtureMediaBody(
        bytes: data,
        info: MediaInfo(
          format: MediaFormat.png,
          byteLength: data.length,
          width: 1200,
          height: tall ? 6000 : 1800,
        ),
        maxBytes: maxBytes,
        cancellation: cancellation,
        delay: Duration.zero,
        failStream: false,
        onClose: () => active--,
      ),
    );
  }
}

class _Vm {
  _Vm(this.socket) {
    socket.listen((event) {
      final msg = jsonDecode(event as String) as Map<String, dynamic>;
      final id = msg['id'];
      if (id != null) pending.remove(id)?.complete(msg);
    });
  }
  final WebSocket socket;
  final pending = <String, Completer<Map<String, dynamic>>>{};
  int next = 0;
  static Future<_Vm> open() async {
    final info = await developer.Service.controlWebServer(enable: true);
    final uri = info.serverUri!;
    return _Vm(
      await WebSocket.connect(
        uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
      ),
    );
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = '${next++}';
    final waiter = Completer<Map<String, dynamic>>();
    pending[id] = waiter;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    final response = await waiter.future.timeout(const Duration(seconds: 10));
    if (response['error'] != null) {
      throw StateError('VM $method ${response['error']}');
    }
    return response['result'] as Map<String, dynamic>;
  }

  Future<void> close() async {
    await socket.close();
  }
}
