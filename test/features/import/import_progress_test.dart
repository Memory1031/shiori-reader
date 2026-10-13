import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/import_source.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/import/import_controller.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/shared/widgets/shiori_task_progress_bar.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'import_flow_test.dart' show MemorySource, fakeParser;

class StreamSource extends MemorySource {
  final streams = <String, StreamController<List<int>>>{};
  StreamController<List<int>> stage(String id) {
    receive(id: id, name: '$id.txt', size: 8);
    return streams[id] = StreamController<List<int>>();
  }

  @override
  Stream<List<int>> read(ImportCandidate candidate) =>
      streams[candidate.id]!.stream;
}

class Session implements LocalImportSession {
  Session(this.key);
  @override
  final NovelKey key;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unused');
}

class Gates {
  Gates(this.token);
  final CancellationToken token;
  final parsing = Completer<void>(), publishing = Completer<void>();
  bool parseEntered = false, publishEntered = false;
}

class GatedStore implements LocalBookStore {
  final gates = <Gates>[], saved = <LocalBookRecord>[];
  Completer<void>? deliveryGate;
  @override
  Future<Result<LocalBookRecord>> importBook({
    required Stream<List<int>> bytes,
    required LocalBookFormat format,
    required LocalBookParser parse,
    bool addToShelf = false,
    required CancellationToken cancellation,
  }) async {
    final gate = Gates(cancellation);
    gates.add(gate);
    final iterator = StreamIterator(bytes);
    try {
      var received = 0;
      while (await Future.any([
        iterator.moveNext(),
        cancellation.whenCancelled.then<bool>(
          (_) => throw const ImportSourceException(ImportProblem.cancelled),
        ),
      ])) {
        received += iterator.current.length;
        if (received >= 8 && deliveryGate != null) {
          await Future.any([deliveryGate!.future, cancellation.whenCancelled]);
        }
      }
      gate.parseEntered = true;
      final content = await parse(
        Session(LocalBookIdentity.book('${gates.length}'.padLeft(64, '0'))),
      );
      gate.publishEntered = true;
      await Future.any([gate.publishing.future, cancellation.whenCancelled]);
      if (cancellation.isCancelled) {
        throw const ImportSourceException(ImportProblem.cancelled);
      }
      final record = LocalBookRecord(
        content: content,
        format: format,
        importedAt: DateTime.utc(2026),
      );
      saved.add(record);
      return Success(record);
    } on ImportSourceException {
      rethrow;
    } catch (_) {
      return Failure(
        AppFailure(
          kind: gate.publishEntered ? FailureKind.database : FailureKind.parse,
          operation: Operation.libraryWrite,
        ),
      );
    } finally {
      await iterator.cancel();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unused');
}

class Harness {
  final source = StreamSource(), store = GatedStore();
  late final controller = ImportController(
    source: source,
    store: store,
    parsers: {
      LocalBookFormat.txt: (session) async {
        final gate = store.gates.last;
        await Future.any([gate.parsing.future, gate.token.whenCancelled]);
        return fakeParser(session);
      },
    },
  );
}

const screenshots = bool.fromEnvironment('IMPORT_PROGRESS_SCREENSHOTS');
bool fontsLoaded = false;
Future<void> mount(
  WidgetTester tester,
  Harness h,
  GlobalKey capture, {
  String lang = 'en',
  Brightness brightness = Brightness.light,
  AppAccent accent = AppAccent.teal,
  double width = 390,
  double scale = 1,
  bool reduced = false,
}) async {
  tester.view
    ..physicalSize = Size(width, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (screenshots && !fontsLoaded) {
    final font = Platform.environment['SHIORI_IMPORT_FONT'];
    if (font != null) {
      await tester.runAsync(() async {
        await (FontLoader('ImportPreview')..addFont(
              Future.value(
                ByteData.sublistView(await File(font).readAsBytes()),
              ),
            ))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      fontsLoaded = true;
    }
  }
  final theme = appTheme(brightness, accent: accent);
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: fontsLoaded
            ? theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'ImportPreview'),
                primaryTextTheme: theme.primaryTextTheme.apply(
                  fontFamily: 'ImportPreview',
                ),
              )
            : theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: ImportOverlay(controller: h.controller, child: child!),
        ),
        home: const Scaffold(body: Center(child: Text('Shiori'))),
      ),
    ),
  );
  await tester.pump();
}

Future<void> shot(WidgetTester tester, GlobalKey capture, String name) async {
  if (!screenshots) return;
  final original = debugDisableShadows;
  try {
    debugDisableShadows = false;
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    repaint(boundary);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final directory = Directory('.tooling/import-progress')
        ..createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
  } finally {
    debugDisableShadows = original;
  }
}

Future<void> tick(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(const Duration(milliseconds: 50));
}

void cleanup(WidgetTester tester, Harness h) {
  addTearDown(() async {
    if (h.source.ackGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await tester.pumpWidget(const SizedBox());
    final stopping = h.controller.shutdown();
    await tick(tester);
    await stopping;
    h.controller.dispose();
    unawaited(h.source.events.close());
  });
}

AppLocalizations strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ImportOverlay)));
LinearProgressIndicator bar(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
Future<void> readFile(
  WidgetTester tester,
  StreamController<List<int>> input,
) async {
  input.add([65, 66, 67, 68]);
  await tick(tester);
  input.add([69, 70, 71, 72]);
  unawaited(input.close());
  await tick(tester);
}

Future<void> commit(WidgetTester tester, Gates gate) async {
  gate.parsing.complete();
  await tick(tester);
  gate.publishing.complete();
  await tick(tester);
}

void main() {
  testWidgets(
    'EOF and delivery, parsing, publication and acknowledgment drive distinct feedback',
    (tester) async {
      final h = Harness(), capture = GlobalKey();
      cleanup(tester, h);
      final input = h.source.stage('Book');
      h.source.ackGate = Completer<void>();
      h.store.deliveryGate = Completer<void>();
      await h.controller.start();
      h.controller.open();
      await mount(tester, h, capture);
      final run = h.controller.submit();
      await tick(tester);
      final l = strings(tester);
      expect(h.controller.workStage, ImportWorkStage.reading);
      expect(bar(tester).value, 0);
      expect(find.text(l.importFileReading), findsOneWidget);
      input.add([65, 66, 67, 68]);
      await tick(tester);
      expect(bar(tester).value, .5);
      await shot(tester, capture, 'phone-single-reading');
      input.add([69, 70, 71, 72]);
      await tick(tester);
      expect(h.controller.copiedBytes, 8);
      expect(bar(tester).value, 1);
      expect(h.controller.workStage, ImportWorkStage.reading);
      unawaited(input.close());
      await tick(tester);
      expect(h.controller.workStage, ImportWorkStage.reading);
      final readingRect = tester.getRect(find.byType(ShioriTaskProgressBar));
      final stopRect = tester.getRect(find.text(l.importStop));
      h.store.deliveryGate!.complete();
      await tick(tester);
      expect(h.controller.workStage, ImportWorkStage.processing);
      expect(bar(tester).value, isNull);
      expect(h.store.gates.single.parseEntered, isTrue);
      await shot(tester, capture, 'phone-single-processing');
      if (screenshots) {
        await mount(tester, h, capture, reduced: true);
        await shot(tester, capture, 'phone-single-reduced-processing');
        await mount(tester, h, capture);
      }
      expect(find.text(l.importBookProcessing), findsOneWidget);
      expect(tester.getRect(find.byType(ShioriTaskProgressBar)), readingRect);
      expect(tester.getRect(find.text(l.importStop)), stopRect);
      h.store.gates.single.parsing.complete();
      await tick(tester);
      expect(h.store.gates.single.publishEntered, isTrue);
      expect(h.store.saved, isEmpty);
      expect(bar(tester).value, isNull);
      expect(find.text(l.importSuccess), findsNothing);
      h.store.gates.single.publishing.complete();
      await tick(tester);
      expect(h.store.saved, hasLength(1));
      expect(h.controller.succeededCount, 1);
      expect(h.controller.busy, isTrue);
      expect(h.controller.workStage, ImportWorkStage.processing);
      expect(bar(tester).value, isNull);
      expect(find.text(l.importDone), findsNothing);
      expect(find.text(l.importSuccess), findsNothing);
      h.source.ackGate!.complete();
      await tick(tester);
      await run;
      expect(h.controller.workStage, isNull);
      expect(h.controller.phase, ImportPhase.succeeded);
      expect(find.text(l.importSuccess), findsOneWidget);
      await shot(tester, capture, 'phone-single-success');
      expect(find.byType(ShioriTaskProgressBar), findsNothing);
    },
  );
  for (final failure in ['read', 'parse', 'publish']) {
    testWidgets('$failure failure cleans progress and retains retry', (
      tester,
    ) async {
      final h = Harness(), capture = GlobalKey();
      cleanup(tester, h);
      final input = h.source.stage('Book');
      await h.controller.start();
      h.controller.open();
      await mount(tester, h, capture);
      final run = h.controller.submit();
      await tick(tester);
      if (failure == 'read') {
        input.addError(const ImportSourceException(ImportProblem.unreadable));
      } else {
        await readFile(tester, input);
        if (failure == 'parse') {
          h.store.gates.single.parsing.completeError(
            const FormatException('Invalid book'),
          );
        } else {
          h.store.gates.single.parsing.complete();
          await tick(tester);
          h.store.gates.single.publishing.completeError(
            StateError('Publish failed'),
          );
        }
      }
      await tick(tester);
      await run;
      expect(h.controller.workStage, isNull);
      expect(h.controller.phase, ImportPhase.failed);
      expect(h.controller.problem, switch (failure) {
        'read' => ImportProblem.unreadable,
        'parse' => ImportProblem.invalidContent,
        _ => ImportProblem.storage,
      });
      if (failure == 'publish') {
        await shot(tester, capture, 'phone-single-failure');
      }
      expect(h.store.saved, isEmpty);
      expect(find.byType(ShioriTaskProgressBar), findsNothing);
      expect(find.text(strings(tester).importSuccess), findsNothing);
      expect(find.text(strings(tester).importRetry), findsOneWidget);
      expect(find.byKey(const ValueKey('import-error')), findsOneWidget);
      final retryInput = h.source.streams['Book'] =
          StreamController<List<int>>();
      final retry = h.controller.submit();
      await tick(tester);
      expect(h.controller.workStage, ImportWorkStage.reading);
      expect(bar(tester).value, 0);
      await readFile(tester, retryInput);
      expect(h.controller.workStage, ImportWorkStage.processing);
      await commit(tester, h.store.gates.last);
      await retry;
      expect(h.controller.phase, ImportPhase.succeeded);
    });
  }
  for (final processing in [false, true]) {
    testWidgets(
      'cancellation while ${processing ? 'processing' : 'reading'} leaves no loading',
      (tester) async {
        final h = Harness(), capture = GlobalKey();
        cleanup(tester, h);
        final input = h.source.stage('Book');
        await h.controller.start();
        h.controller.open();
        await mount(tester, h, capture);
        final run = h.controller.submit();
        await tick(tester);
        if (processing) await readFile(tester, input);
        final stopping = h.controller.cancel();
        if (!processing) {
          unawaited(input.close());
        }
        await tick(tester);
        await stopping;
        await run;
        expect(h.controller.workStage, isNull);
        expect(h.store.saved, isEmpty);
        expect(h.controller.items.single.phase, ImportItemPhase.ready);
        expect(find.byType(ShioriTaskProgressBar), findsNothing);
      },
    );
  }
  testWidgets(
    'batch resets each file and stop preserves a committed predecessor',
    (tester) async {
      final h = Harness(), capture = GlobalKey();
      cleanup(tester, h);
      final first = h.source.stage('First'), second = h.source.stage('Second');
      await h.controller.start();
      h.controller.open();
      await mount(tester, h, capture);
      final run = h.controller.submit();
      await tick(tester);
      expect(
        find.text(strings(tester).importBatchProgress(1, 2)),
        findsOneWidget,
      );
      first.add([65, 66, 67, 68]);
      await tick(tester);
      expect(bar(tester).value, .5);
      final readingRect = tester.getRect(find.byType(ShioriTaskProgressBar));
      first.add([69, 70, 71, 72]);
      unawaited(first.close());
      await tick(tester);
      expect(bar(tester).value, isNull);
      expect(tester.getRect(find.byType(ShioriTaskProgressBar)), readingRect);
      await commit(tester, h.store.gates.first);
      expect(h.controller.succeededCount, 1);
      expect(h.store.saved, hasLength(1));
      expect(h.controller.importingItem!.candidate.id, 'Second');
      expect(h.controller.workStage, ImportWorkStage.reading);
      expect(h.controller.copiedBytes, 0);
      expect(bar(tester).value, 0);
      expect(
        find.text(strings(tester).importBatchProgress(2, 2)),
        findsOneWidget,
      );
      await readFile(tester, second);
      expect(bar(tester).value, isNull);
      final stopping = h.controller.cancel();
      await tick(tester);
      await stopping;
      await run;
      expect(h.store.saved, hasLength(1));
      expect(h.controller.succeededCount, 1);
      expect(h.controller.workStage, isNull);
      expect(h.source.acked, ['First']);
      expect(find.byType(ShioriTaskProgressBar), findsNothing);
    },
  );
  testWidgets('external receiving keeps its existing copy label', (
    tester,
  ) async {
    final h = Harness(), capture = GlobalKey();
    cleanup(tester, h);
    await h.controller.start();
    h.controller.open();
    await mount(tester, h, capture);
    h.source.events.add(const ImportSourceEvent(copiedBytes: 4));
    await tick(tester);
    expect(h.controller.phase, ImportPhase.receiving);
    expect(h.controller.workStage, isNull);
    expect(find.text(strings(tester).importReceiving), findsOneWidget);
    expect(find.text(strings(tester).importFileReading), findsNothing);
  });
  for (final brightness in Brightness.values) {
    for (final accent in AppAccent.values) {
      testWidgets(
        'task bar inherits $brightness $accent and unknown reduced-motion semantics',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final theme = appTheme(brightness, accent: accent);
            Widget app({double? value, bool reduced = false}) => MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: Scaffold(
                  body: ShioriTaskProgressBar(
                    value: value,
                    semanticsLabel: 'Processing book',
                  ),
                ),
              ),
            );
            await tester.pumpWidget(app(value: .5));
            expect(bar(tester).color, theme.colorScheme.primary);
            expect(
              bar(tester).backgroundColor,
              theme.colorScheme.outlineVariant,
            );
            expect(bar(tester).minHeight, 4);
            final height = tester
                .getSize(find.byType(ShioriTaskProgressBar))
                .height;
            await tester.pumpWidget(app());
            expect(bar(tester).value, isNull);
            expect(
              tester.getSize(find.byType(ShioriTaskProgressBar)).height,
              height,
            );
            await tester.pumpWidget(app(reduced: true));
            await tester.pump();
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(tester.hasRunningAnimations, isFalse);
            final data = tester
                .getSemantics(find.byType(ShioriTaskProgressBar))
                .getSemanticsData();
            expect(data.label, 'Processing book');
            expect(data.value, isEmpty);
            expect(
              tester.getSize(find.byType(ShioriTaskProgressBar)).height,
              height,
            );
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
  for (final desktop in [false, true]) {
    for (final lang in ['zh', 'en']) {
      testWidgets(
        'render ${desktop ? 'Windows' : 'phone'} $lang stages and outcomes',
        (tester) async {
          final h = Harness(), capture = GlobalKey();
          cleanup(tester, h);
          final first = h.source.stage('Journey'),
              second = desktop ? null : h.source.stage('Second');
          await h.controller.start();
          h.controller.open();
          await mount(
            tester,
            h,
            capture,
            lang: lang,
            width: desktop ? 1000 : 390,
            scale: 1.4,
            brightness: lang == 'zh' ? Brightness.dark : Brightness.light,
            accent: desktop ? AppAccent.warmBrown : AppAccent.teal,
          );
          final run = h.controller.submit();
          await tick(tester);
          first.add([65, 66, 67, 68]);
          await tick(tester);
          final prefix = '${desktop ? 'windows-single' : 'phone-batch'}-$lang';
          await shot(tester, capture, '$prefix-reading');
          first.add([69, 70, 71, 72]);
          unawaited(first.close());
          await tick(tester);
          expect(bar(tester).value, isNull);
          await shot(tester, capture, '$prefix-processing');
          await commit(tester, h.store.gates.first);
          if (second != null) {
            await readFile(tester, second);
            h.store.gates.last.parsing.completeError(
              const FormatException('Invalid'),
            );
            await tick(tester);
          }
          await run;
          expect(tester.takeException(), isNull);
          await shot(
            tester,
            capture,
            '$prefix-${desktop ? 'success' : 'failure'}',
          );
        },
        variant: TargetPlatformVariant.only(
          desktop ? TargetPlatform.windows : TargetPlatform.android,
        ),
      );
    }
  }
}
