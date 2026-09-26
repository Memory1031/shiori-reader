import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/local_books/local_reparse_controller.dart';

class GatedReparse implements LocalBookReparse {
  final calls =
      <
        ({
          NovelKey key,
          TxtEncoding? encoding,
          CancellationToken token,
          ChooseTxtEncoding choose,
          Completer<Result<LocalReparseResult>> result,
        })
      >[];
  @override
  Future<Result<LocalReparseResult>> reparseBook(
    NovelKey key, {
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
    required CancellationToken cancellation,
  }) {
    final result = Completer<Result<LocalReparseResult>>();
    calls.add((
      key: key,
      encoding: encoding,
      token: cancellation,
      choose: chooseEncoding,
      result: result,
    ));
    return result.future;
  }

  @override
  Stream<NovelKey> get invalidations => const Stream.empty();
  @override
  Stream<NovelKey> get changes => const Stream.empty();
}

final targets = List.generate(
  3,
  (i) => LocalReparseTarget(
    LocalBookIdentity.book('${i + 1}' * 64),
    'Book $i',
    LocalBookFormat.txt,
  ),
);
final success = Success(
  LocalReparseResult(approximate: true, cleanupPending: true),
);
final failure = Failure<LocalReparseResult>(
  AppFailure(kind: FailureKind.parse, operation: Operation.libraryWrite),
);
Future<TxtEncoding?> choose(
  LocalReparseTarget book,
  TxtEncodingPreview preview,
) async => TxtEncoding.utf8;
void main() {
  test(
    'single success and override, double start rejected, empty no-op',
    () async {
      final service = GatedReparse();
      final controller = LocalReparseController(service);
      await controller.run([], batch: true, chooseEncoding: choose);
      expect(controller.phase, LocalReparsePhase.idle);
      final done = controller.run(
        [targets.first],
        batch: false,
        chooseEncoding: choose,
        encoding: TxtEncoding.gb18030,
      );
      await controller.run(targets, batch: true, chooseEncoding: choose);
      expect(service.calls, hasLength(1));
      expect(service.calls.single.encoding, TxtEncoding.gb18030);
      service.calls.single.result.complete(success);
      await done;
      expect(controller.succeeded, 1);
      expect(controller.approximate, 1);
      expect(controller.cleanupPending, isTrue);
      expect(controller.busy, isFalse);
      expect(controller.active, isNull);
      controller.dispose();
    },
  );
  test('batch snapshot, serial failure continues and aggregates', () async {
    final service = GatedReparse(), input = targets.toList();
    final c = LocalReparseController(service);
    final done = c.run(
      input,
      batch: true,
      chooseEncoding: choose,
      encoding: TxtEncoding.gb18030,
    );
    input.clear();
    expect(service.calls, hasLength(1));
    service.calls[0].result.complete(success);
    await Future<void>.value();
    await Future<void>.value();
    expect(service.calls, hasLength(2));
    service.calls[1].result.complete(failure);
    await Future<void>.value();
    await Future<void>.value();
    expect(service.calls, hasLength(3));
    service.calls[2].result.complete(success);
    await done;
    expect(c.succeeded, 2);
    expect(c.failed, 1);
    expect(c.unprocessed, 0);
    expect(c.failures.single.$1, targets[1].title);
    expect(c.approximate, 2);
    expect(c.cleanupPending, isTrue);
    expect(service.calls.map((e) => e.encoding), [null, null, null]);
    c.dispose();
  });
  test(
    'stop waits for unwind; committed late success remains; no remaining start',
    () async {
      final service = GatedReparse();
      final controller = LocalReparseController(service);
      final done = controller.run(targets, batch: true, chooseEncoding: choose);
      service.calls[0].result.complete(success);
      await Future<void>.value();
      await Future<void>.value();
      controller.cancel();
      expect(controller.phase, LocalReparsePhase.cancelling);
      expect(service.calls.last.token.isCancelled, isTrue);
      await controller.run(targets, batch: true, chooseEncoding: choose);
      expect(service.calls, hasLength(2));
      expect(controller.busy, isTrue);
      service.calls[1].result.complete(success);
      await done;
      expect(controller.succeeded, 2);
      expect(controller.unprocessed, 1);
      expect(controller.busy, isFalse);
      controller.dispose();
    },
  );
  test(
    'chooser is per book, null cancels and exception retains cancellation mapping',
    () async {
      final service = GatedReparse(), chosen = <NovelKey>[];
      final c = LocalReparseController(service);
      final done = c.run(
        targets,
        batch: true,
        chooseEncoding: (book, preview) async {
          chosen.add(book.key);
          return book == targets.first ? TxtEncoding.utf8 : null;
        },
      );
      final preview = TxtEncodingPreview({TxtEncoding.utf8: 'sample'});
      expect(await service.calls[0].choose(preview), TxtEncoding.utf8);
      service.calls[0].result.complete(success);
      await Future<void>.value();
      await Future<void>.value();
      await expectLater(
        service.calls[1].choose(preview),
        throwsA(isA<LocalParseException>()),
      );
      expect(service.calls[1].token.isCancelled, isTrue);
      service.calls[1].result.completeError(StateError('cancelled chooser'));
      await done;
      expect(chosen, [targets[0].key, targets[1].key]);
      expect(c.failed, 0);
      expect(c.unprocessed, 2);
      c.dispose();
    },
  );
  test('exception mapping and explicit failure', () async {
    final service = GatedReparse(), c = LocalReparseController(GatedReparse());
    c.dispose();
    final controller = LocalReparseController(service);
    var done = controller.run(
      [targets.first],
      batch: false,
      chooseEncoding: choose,
    );
    service.calls[0].result.completeError(StateError('service'));
    await done;
    expect(controller.failure!.kind, FailureKind.database);
    done = controller.run(
      [targets.first],
      batch: false,
      chooseEncoding: choose,
    );
    service.calls[1].result.complete(failure);
    await done;
    expect(controller.failure!.kind, FailureKind.parse);
    controller.dispose();
  });
  test(
    'dispose cancels, late result does not notify or invoke next chooser',
    () async {
      final service = GatedReparse();
      final c = LocalReparseController(service);
      var updates = 0;
      c.addListener(() => updates++);
      final done = c.run(
        targets,
        batch: true,
        chooseEncoding: (_, _) => throw StateError('dead owner'),
      );
      c.dispose();
      final before = updates;
      expect(service.calls[0].token.isCancelled, isTrue);
      await expectLater(
        service.calls[0].choose(TxtEncodingPreview({})),
        throwsA(isA<LocalParseException>()),
      );
      service.calls[0].result.complete(success);
      await done;
      expect(updates, before);
      expect(service.calls, hasLength(1));
    },
  );
}
