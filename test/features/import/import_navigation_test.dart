import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/import_source.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'import_flow_test.dart' show PreviewDecoder;
import 'import_progress_test.dart'
    show Harness, cleanup, tick, strings, readFile, mount, shot;

Future<void> mountNavigation(
  WidgetTester tester,
  Harness h,
  void Function() underlyingBack,
) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: h.navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => ImportOverlay(
        controller: h.controller,
        navigatorKey: h.navigatorKey,
        child: child!,
      ),
      home: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (_, _) => underlyingBack(),
        child: const Scaffold(body: Text('Underlying reader')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Object?> gesture(WidgetTester tester, String method) async {
  final result = Completer<Object?>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture'
            ? <String, Object?>{
                'touchOffset': <double>[0, 200],
                'progress': 0.0,
                'swipeEdge': 0,
              }
            : null,
      ),
    ),
    (data) =>
        result.complete(const StandardMethodCodec().decodeEnvelope(data!)),
  );
  return result.future;
}

void main() {
  for (final view in [
    (lang: 'zh', width: 390.0, brightness: Brightness.light),
    (lang: 'en', width: 320.0, brightness: Brightness.dark),
  ]) {
    testWidgets('${view.lang} TXT import only shows previews when needed', (
      tester,
    ) async {
      final h = Harness(
        decoder: PreviewDecoder(
          {'Book.txt'},
          {
            TxtEncoding.utf16le: '窗边的灯亮着。\n夜色渐深。',
            TxtEncoding.utf16be: '捤笔梕唣庬绘。\n龠韞腜暙。',
          },
        ),
      );
      final capture = GlobalKey();
      cleanup(tester, h);
      final input = h.source.stage('Book');
      await h.controller.start();
      h.controller.open();
      await mount(
        tester,
        h,
        capture,
        lang: view.lang,
        width: view.width,
        brightness: view.brightness,
        scale: view.lang == 'en' ? 1.8 : 1,
      );
      await tester.pumpAndSettle();
      final l = strings(tester);
      expect(find.byType(DropdownButton<TxtEncoding?>), findsNothing);
      await shot(tester, capture, 'txt-ready-${view.lang}');
      await tester.tap(find.text(l.importStart));
      await tick(tester);
      await readFile(tester, input);
      expect(find.text(l.importEncodingHint), findsOneWidget);
      expect(find.text('窗边的灯亮着。\n夜色渐深。'), findsOneWidget);
      expect(find.text('UTF-16 LE'), findsNothing);
      await shot(tester, capture, 'txt-preview-${view.lang}');
      final choice = find.byKey(const ValueKey(TxtEncoding.utf16le));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tick(tester);
      h.store.gates.single.publishing.complete();
      await tick(tester);
      expect(h.source.acked, ['Book']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'system back closes confirmation then import without reaching the reader',
    (tester) async {
      final h = Harness();
      cleanup(tester, h);
      h.source.stage('Book');
      await h.controller.start();
      h.controller.open();
      var backs = 0;
      await mountNavigation(tester, h, () => backs++);
      final l = strings(tester);
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(l.importDiscardTitle), findsNothing);
      expect(find.text('Book.txt'), findsOneWidget);
      expect(h.controller.panelOpen, isTrue);
      expect(h.source.acked, isEmpty);
      expect(backs, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.controller.interactionOpen, isFalse);
      expect(h.source.acked, isEmpty);
      expect(backs, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(backs, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final stage in ['receiving', 'importing', 'discarding']) {
    testWidgets(
      '$stage consumes system back and preserves task ownership',
      (tester) async {
        final h = Harness();
        cleanup(tester, h);
        final input = h.source.stage('Book');
        await h.controller.start();
        h.controller.open();
        var backs = 0;
        await mountNavigation(tester, h, () => backs++);
        if (stage == 'receiving') {
          h.source.events.add(const ImportSourceEvent(copiedBytes: 0));
        } else if (stage == 'importing') {
          unawaited(h.controller.submit());
          await tick(tester);
          await readFile(tester, input);
        } else {
          h.source.ackGate = Completer<void>();
          unawaited(h.controller.discard());
        }
        await tick(tester);
        expect(h.controller.busy, isTrue);
        await tester.binding.handlePopRoute();
        await tick(tester);
        expect(backs, 0);
        expect(h.controller.interactionOpen, isTrue);
        expect(h.source.acked, isEmpty);
        if (stage == 'receiving') {
          h.source.events.add(const ImportSourceEvent(completed: true));
          await tick(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'predictive back cancel is inert and commit cancels only confirmation',
    (tester) async {
      final h = Harness();
      cleanup(tester, h);
      h.source.stage('Book');
      await h.controller.start();
      h.controller.open();
      var backs = 0;
      await mountNavigation(tester, h, () => backs++);
      final l = strings(tester);
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      expect(await gesture(tester, 'startBackGesture'), isFalse);
      await gesture(tester, 'cancelBackGesture');
      await tick(tester);
      expect(find.text(l.importDiscardTitle), findsOneWidget);
      expect(await gesture(tester, 'startBackGesture'), isFalse);
      await gesture(tester, 'commitBackGesture');
      await tick(tester);
      expect(find.text(l.importDiscardTitle), findsNothing);
      expect(h.controller.panelOpen, isTrue);
      expect(h.source.acked, isEmpty);
      expect(backs, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
