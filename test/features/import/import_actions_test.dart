import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/import_source.dart';
import 'import_progress_test.dart'
    show Harness, cleanup, mount, shot, strings, tick, readFile, commit;

void main() {
  for (final count in [1, 3]) {
    testWidgets(
      'Later preserves $count files without starting or acknowledging',
      (tester) async {
        final h = Harness(), capture = GlobalKey();
        cleanup(tester, h);
        for (var i = 0; i < count; i++) {
          h.source.stage('Book$i');
        }
        await h.controller.start();
        h.controller.open();
        await mount(tester, h, capture);
        final l = strings(tester);
        await tester.tap(find.text(l.importLater));
        await tick(tester);
        expect(h.controller.interactionOpen, isFalse);
        expect(h.source.acked, isEmpty);
        expect(h.source.inbox, hasLength(count));
        expect(h.store.gates, isEmpty);
        h.controller.open();
        await tick(tester);
        expect(h.controller.items, hasLength(count));
        expect(find.text('Book0.txt'), findsOneWidget);
        expect(h.store.gates, isEmpty);
      },
    );
  }

  for (final dismiss in ['keep', 'enter', 'escape', 'backdrop']) {
    testWidgets(
      '$dismiss closes only discard confirmation and preserves files',
      (tester) async {
        final h = Harness(), capture = GlobalKey();
        cleanup(tester, h);
        h.source.stage('Book');
        await h.controller.start();
        h.controller.open();
        await mount(tester, h, capture);
        final l = strings(tester);
        await tester.tap(find.text(l.importDiscardFiles));
        await tick(tester);
        expect(find.text(l.importDiscardTitle), findsOneWidget);
        expect(find.text(l.importDiscardMessage), findsOneWidget);
        expect(
          Focus.of(
            tester.element(find.text(l.importKeepFiles)),
          ).hasPrimaryFocus,
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('import-dismiss-barrier')),
          findsOneWidget,
        );
        expect(h.source.acked, isEmpty);
        switch (dismiss) {
          case 'keep':
            await tester.tap(find.text(l.importKeepFiles));
          case 'escape':
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          case 'enter':
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          case 'backdrop':
            await tester.tapAt(const Offset(5, 5));
        }
        await tick(tester);
        expect(find.text(l.importDiscardTitle), findsNothing);
        expect(find.text('Book.txt'), findsOneWidget);
        expect(h.controller.panelOpen, isTrue);
        expect(h.source.acked, isEmpty);
        expect(h.store.gates, isEmpty);
      },
    );
  }

  testWidgets(
    'confirmation consumes only captured receipts and waits for cleanup',
    (tester) async {
      final h = Harness(), capture = GlobalKey();
      cleanup(tester, h);
      h.source.stage('Old');
      await h.controller.start();
      h.controller.open();
      await mount(tester, h, capture);
      final l = strings(tester);
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      h.source.stage('New');
      await h.controller.refresh();
      await tick(tester);
      h.source.ackGate = Completer<void>();
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      expect(h.controller.discarding, isTrue);
      expect(h.source.acked, isEmpty);
      expect(find.text(l.importDiscardFiles), findsNothing);
      expect(find.text(l.importLater), findsNothing);
      h.source.ackGate!.complete();
      await tick(tester);
      expect(h.source.acked, ['Old']);
      expect(h.source.inbox.map((item) => item.id), ['New']);
      expect(h.controller.items.map((item) => item.candidate.id), ['New']);
      expect(h.store.gates, isEmpty);
    },
  );

  testWidgets(
    'partial cleanup failure remains visible and needs new confirmation',
    (tester) async {
      final h = Harness(), capture = GlobalKey();
      cleanup(tester, h);
      h.source.stage('A');
      h.source.stage('B');
      h.source.failAckIds.add('B');
      await h.controller.start();
      h.controller.open();
      await mount(tester, h, capture);
      final l = strings(tester);
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      expect(h.source.acked, ['A']);
      expect(h.source.inbox.map((item) => item.id), ['B']);
      expect(h.controller.problem, ImportProblem.storage);
      expect(find.text(l.importStorage), findsOneWidget);
      await tester.tap(find.text(l.importLater));
      await tick(tester);
      h.controller.open();
      await tick(tester);
      expect(find.text(l.importStorage), findsOneWidget);
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      expect(h.source.acked, ['A']);
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      expect(h.source.acked, ['A', 'B']);
    },
  );

  testWidgets(
    'partial failure offers Later and discard remaining without losing success',
    (tester) async {
      final h = Harness(), capture = GlobalKey();
      cleanup(tester, h);
      final first = h.source.stage('Good');
      h.source.stage('Failed');
      await h.controller.start();
      h.controller.open();
      await mount(tester, h, capture);
      final run = h.controller.submit();
      await tick(tester);
      await readFile(tester, first);
      await commit(tester, h.store.gates.first);
      final bad = h.source.streams['Failed']!;
      bad.addError(const ImportSourceException(ImportProblem.unreadable));
      unawaited(bad.close());
      await tick(tester);
      await run;
      final l = strings(tester);
      expect(h.controller.succeededCount, 1);
      expect(h.controller.failedCount, 1);
      expect(find.text(l.importDiscardRemaining), findsOneWidget);
      await shot(tester, capture, 'import-actions-partial-result');
      await tester.tap(find.text(l.importLater));
      await tick(tester);
      expect(h.source.acked, ['Good']);
      expect(h.store.saved, hasLength(1));
      h.controller.open();
      await tick(tester);
      await tester.tap(find.text(l.importDiscardRemaining));
      await tick(tester);
      expect(find.text(l.importDiscardRemainingTitle), findsOneWidget);
      await tester.tap(find.text(l.importDiscardFiles));
      await tick(tester);
      expect(h.source.inbox, isEmpty);
      expect(h.store.saved, hasLength(1));
    },
  );

  testWidgets(
    'importing has only stop and all completed files have only Done',
    (tester) async {
      final h = Harness(), capture = GlobalKey();
      cleanup(tester, h);
      final input = h.source.stage('Book');
      await h.controller.start();
      h.controller.open();
      await mount(tester, h, capture);
      final l = strings(tester);
      final run = h.controller.submit();
      await tick(tester);
      expect(find.text(l.importLater), findsNothing);
      expect(find.text(l.importDiscardFiles), findsNothing);
      expect(find.text(l.importStop), findsOneWidget);
      await readFile(tester, input);
      await commit(tester, h.store.gates.single);
      await run;
      expect(find.text(l.importDone), findsOneWidget);
      expect(find.text(l.importLater), findsNothing);
      expect(find.text(l.importDiscardFiles), findsNothing);
      expect(find.text(l.importStop), findsNothing);
    },
  );

  for (final view in [
    (lang: 'zh', width: 360.0, brightness: Brightness.light),
    (lang: 'en', width: 360.0, brightness: Brightness.dark),
    (lang: 'zh', width: 1000.0, brightness: Brightness.dark),
    (lang: 'en', width: 1000.0, brightness: Brightness.light),
  ]) {
    testWidgets(
      '${view.lang} ${view.width} actions and confirmation fit large text',
      (tester) async {
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
        final l = strings(tester);
        final prefix = 'import-actions-${view.lang}-${view.width.toInt()}';
        await shot(tester, capture, '$prefix-single');
        h.source.stage('Next');
        await h.controller.refresh();
        await tick(tester);
        await shot(tester, capture, '$prefix-batch');
        await tester.tap(find.text(l.importDiscardFiles));
        await tick(tester);
        await shot(tester, capture, '$prefix-confirmation');
        await tester.ensureVisible(find.text(l.importKeepFiles));
        expect(find.text(l.importKeepFiles).hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.text(l.importDiscardFiles));
        expect(find.text(l.importDiscardFiles).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
