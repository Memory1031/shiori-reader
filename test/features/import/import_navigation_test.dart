import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/import_source.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
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
    (lang: 'zh', width: 360.0, brightness: Brightness.light),
    (lang: 'en', width: 1000.0, brightness: Brightness.dark),
  ]) {
    testWidgets('${view.lang} manual encoding menu is visible and owns back', (
      tester,
    ) async {
      final h = Harness(), capture = GlobalKey();
      cleanup(tester, h);
      h.source.stage('Book');
      await h.controller.start();
      h.controller.open();
      await mount(
        tester,
        h,
        capture,
        lang: view.lang,
        width: view.width,
        brightness: view.brightness,
        scale: 1.6,
      );
      await tester.tap(find.byType(DropdownButton<TxtEncoding?>));
      await tester.pumpAndSettle();
      expect(find.text('GB18030 / GBK').hitTestable(), findsOneWidget);
      await shot(tester, capture, 'review-encoding-${view.lang}-menu');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.controller.panelOpen, isTrue);
      expect(h.controller.encoding, isNull);
      await tester.tap(find.byType(DropdownButton<TxtEncoding?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GB18030 / GBK').hitTestable());
      await tester.pumpAndSettle();
      expect(h.controller.encoding, TxtEncoding.gb18030);
      expect(h.source.acked, isEmpty);
      expect(tester.takeException(), isNull);
      await shot(tester, capture, 'review-encoding-${view.lang}-selected');
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

  testWidgets(
    'manual TXT dropdown opens above import and sends the chosen encoding',
    (tester) async {
      final h = Harness();
      cleanup(tester, h);
      h.source.stage('Book');
      await h.controller.start();
      h.controller.open();
      await mountNavigation(tester, h, () {});
      await tester.tap(find.byType(DropdownButton<TxtEncoding?>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('UTF-16 LE').hitTestable());
      await tester.pumpAndSettle();
      expect(h.controller.encoding, TxtEncoding.utf16le);
      expect(tester.takeException(), isNull);
      expect(find.text('Book.txt'), findsOneWidget);
    },
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
