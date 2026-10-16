import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';

import 'link_return_test.dart' as f;
import 'local_search_test.dart' as s;

class _BookUse implements LocalBookUse {
  bool released = false;
  @override
  Future<void> release({bool? progressSaved}) async => released = true;
}

class _GatedRepository extends s.ReaderSearchRepository {
  _GatedRepository(super.store);
  ChapterKey? target;
  int reads = 0;
  final formalEntered = Completer<void>(), gate = Completer<void>();
  CancellationToken? loading;
  final uses = <_BookUse>[];
  int get activeUses => uses.where((u) => !u.released).length;

  @override
  Future<LocalBookUse?> acquireBookUse(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    final use = _BookUse();
    uses.add(use);
    return use;
  }

  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (key == target && ++reads == 2) {
      loading = cancellation;
      formalEntered.complete();
      await gate.future;
    }
    return super.loadChapter(key, mode: mode, cancellation: cancellation);
  }
}

void main() {
  testWidgets(
    'animated auxiliary search keeps its source until the main target confirms',
    (t) async {
      final r = await f.mount(
        t,
        repositoryFactory: _GatedRepository.new,
        pageTurn: PageTurnStyle.slide,
      );
      final repository = r.repository as _GatedRepository;
      addTearDown(() {
        if (!repository.gate.isCompleted) repository.gate.complete();
      });
      final a = r.position(t);
      await r.link(t, 'Auxiliary');
      unawaited(r.view(t).viewportController!.next());
      await t.pumpAndSettle();
      final source = r.view(t).session, position = r.position(t);
      final state = s.search(r, t);
      await s.open(t);
      await s.submit(t, state, 'later');
      final hit = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == r.key('c'));
      repository.target = r.key('c');
      await s.select(t, state, hit);
      expect(repository.formalEntered.isCompleted, isTrue);
      expect(r.view(t).session, same(source));
      expect(r.position(t), position);
      repository.gate.complete();
      await t.pumpAndSettle();
      expect(state.navigating, isFalse);
      expect(state.selectedIndex, hit);
      expect(r.view(t).content.key, r.key('c'));
      expect(source!.isClosed, isTrue);
      await r.back(t);
      expect(r.position(t), position);
      expect(r.view(t).session!.library, isNull);
      await r.back(t);
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'auxiliary search retires its old routes after a footnote destination commits',
    (t) async {
      final r = await f.mount(
        t,
        repositoryFactory: s.ReaderSearchRepository.new,
      );
      final a = r.position(t);
      await r.link(t, 'Auxiliary');
      final note = r.position(t);
      await r.link(t, 'B');
      final source = r.view(t).session, position = r.position(t);
      final state = s.search(r, t);
      await s.open(t);
      await s.submit(t, state, 'annotation');
      final hit = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == r.key('notes'));
      await s.select(t, state, hit);
      expect(state.selectedIndex, hit);
      expect(find.byType(ReaderFootnotePanel), findsOneWidget);
      expect(source!.isClosed, isTrue);
      expect(
        find.byType(BookReaderScreen, skipOffstage: false),
        findsNWidgets(2),
      );
      await t.tap(
        find.descendant(
          of: find.byType(ReaderFootnotePanel),
          matching: find.byIcon(Icons.close),
        ),
      );
      await t.pumpAndSettle();
      await r.back(t);
      expect(r.view(t).content.key, r.key('b'));
      expect(r.position(t), position);
      expect(r.view(t).session!.library, isNull);
      await r.back(t);
      expect(r.view(t).content.key, r.key('notes'));
      expect(r.position(t), note);
      await r.back(t);
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'rebuilt auxiliary return rejects a changed final revision',
    (t) async {
      await s.fonts(t);
      final r = await f.mount(
        t,
        repositoryFactory: s.ReaderSearchRepository.new,
      );
      final repository = r.repository as s.ReaderSearchRepository;
      final a = r.position(t);
      await r.link(t, 'Auxiliary');
      unawaited(r.view(t).viewportController!.next());
      await t.pumpAndSettle();
      final auxiliary = r.position(t), chapter = r.view(t).content.key;
      final state = s.search(r, t);
      await s.open(t);
      await s.submit(t, state, 'later');
      final hit = List.generate(
        state.loadedCount,
        (i) => i,
      ).firstWhere((i) => state.hitAt(i)!.chapter == r.key('c'));
      await s.select(t, state, hit);
      final source = r.view(t).session, position = r.position(t);
      repository
        ..changingTarget = chapter
        ..targetLoads = 0
        ..changeAfter = 2;
      await r.back(t);
      expect(
        repository.targetLoads,
        2,
        reason: 'Precheck succeeds; formal read changes',
      );
      expect(r.view(t).session, same(source));
      expect(r.position(t), position);
      expect(r.view(t).content.key, r.key('c'));
      expect(r.view(t).actions.previousLocation, isNotNull);
      expect(state.canReturn.value, isTrue);
      expect(
        find.byType(BookReaderScreen, skipOffstage: false),
        findsOneWidget,
      );
      await f.snapshot(t, r, 'auxiliary-return-rejected-source');
      repository.changingTarget = null;
      await r.back(t);
      expect(r.view(t).content.key, chapter);
      expect(r.position(t), auxiliary);
      expect(r.view(t).session!.library, isNull);
      await r.back(t);
      expect(r.position(t), a);
      expect(r.view(t).actions.previousLocation, isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  for (final cancellation in ['background', 'cancel']) {
    testWidgets(
      'auxiliary search preserves its source on $cancellation during formal loading',
      (t) async {
        await s.fonts(t);
        final r = await f.mount(t, repositoryFactory: _GatedRepository.new);
        final repository = r.repository as _GatedRepository;
        addTearDown(() {
          if (!repository.gate.isCompleted) repository.gate.complete();
        });
        final a = r.position(t);
        await r.link(t, 'Auxiliary');
        unawaited(r.view(t).viewportController!.next());
        await t.pumpAndSettle();
        final source = r.view(t).session, position = r.position(t);
        expect(position.blockIndex, greaterThan(0));
        await f.snapshot(t, r, 'auxiliary-search-$cancellation-source');
        final state = s.search(r, t);
        await s.open(t);
        await s.submit(t, state, 'later');
        final hit = List.generate(
          state.loadedCount,
          (i) => i,
        ).firstWhere((i) => state.hitAt(i)!.chapter == r.key('c'));
        final activeUses = repository.activeUses;
        repository.target = r.key('c');
        await s.select(t, state, hit);
        expect(repository.formalEntered.isCompleted, isTrue);
        expect(repository.reads, 2, reason: 'The precheck has already passed');
        expect(state.navigating, isTrue);
        if (cancellation == 'background') {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await t.pump();
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        } else {
          await state.suspend();
        }
        await t.pumpAndSettle();
        expect(state.navigating, isFalse);
        expect(repository.loading!.isCancelled, isTrue);
        expect(r.view(t).session, same(source));
        expect(r.position(t), position);
        expect(source!.isClosed, isFalse);
        expect(state.selectedIndex, isNull);
        expect(state.canReturn.value, isFalse);
        expect(
          find.byType(BookReaderScreen, skipOffstage: false),
          findsNWidgets(2),
        );
        repository.gate.complete();
        await t.pumpAndSettle();
        expect(repository.activeUses, activeUses);
        expect(r.view(t).session, same(source));
        expect(r.position(t), position);
        expect(r.view(t).actions.previousLocation, isNotNull);
        await f.snapshot(
          t,
          r,
          'auxiliary-search-$cancellation-after-late-load',
        );
        await r.back(t);
        expect(r.position(t), a);
        expect(r.view(t).actions.previousLocation, isNull);
        expect(t.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.windows}),
    );
  }
}
