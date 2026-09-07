import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

T ok<T>(Result<T> result) => (result as Success<T>).value;
CancellationToken token() => CancellationSource().token;
LocalBookContent fixture(LocalImportSession session, {MediaRef? media}) {
  final chapter = LocalBookIdentity.chapter(session.key, 'txt:0');
  return LocalBookContent(
    detail: NovelDetail(
      summary: NovelSummary(
        key: session.key,
        title: 'Same title',
        cover: media,
      ),
    ),
    catalog: Catalog(
      novelKey: session.key,
      volumes: [
        Volume(
          groupId: 'body',
          chapters: [
            Chapter(
              key: chapter,
              title: 'One',
              ordinal: 0,
              volumeGroupId: 'body',
            ),
          ],
        ),
      ],
    ),
    chapters: [
      ChapterContent(
        key: chapter,
        title: 'One',
        blocks: [
          ParagraphBlock(text: 'Original offline text'),
          if (media != null) ImageBlock(media: media),
        ],
      ),
    ],
  );
}

void main() {
  late Directory temp;
  late AppPaths paths;
  late UserDatabase db;
  late ManagedLocalBooks store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shiori-local-test-');
    paths = AppPaths(
      support: Directory('${temp.path}/a'),
      temporary: temp,
      environment: StorageEnvironment.development,
    );
    await paths.prepare();
    db = UserDatabase(NativeDatabase(paths.userDatabase));
    store = ok(await ManagedLocalBooks.open(paths, db));
  });
  tearDown(() async {
    await store.close();
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<Result<LocalBookRecord>> add(
    String text, {
    LocalBookParser? parse,
    CancellationToken? cancellation,
  }) => store.importBook(
    bytes: Stream.value(utf8.encode(text)),
    format: LocalBookFormat.txt,
    parse: parse ?? (s) async => fixture(s),
    cancellation: cancellation ?? token(),
  );

  test(
    'duplicate bytes skip parser; same title different bytes keep distinct identity',
    () async {
      final first = ok(await add('a'));
      final duplicate = ok(
        await add('a', parse: (_) => throw StateError('Must not parse twice')),
      );
      final second = ok(await add('b'));
      expect(
        first.content.detail.summary.key,
        duplicate.content.detail.summary.key,
      );
      expect(first.importedAt, duplicate.importedAt);
      expect(
        first.content.detail.summary.key,
        isNot(second.content.detail.summary.key),
      );
      expect(
        await db.customSelect('SELECT * FROM local_books').get(),
        hasLength(2),
      );
      expect(await paths.localImportStaging.list().toList(), isEmpty);
    },
  );

  test(
    'SQL transaction failure rolls back published directory and can retry',
    () async {
      await db.customStatement(
        "CREATE TRIGGER fail_import BEFORE INSERT ON local_books BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      expect(await add('a'), isA<Failure<LocalBookRecord>>());
      expect(await paths.localBooks.list().toList(), isEmpty);
      expect(await paths.localImportStaging.list().toList(), isEmpty);
      await db.customStatement('DROP TRIGGER fail_import');
      expect(await add('a'), isA<Success<LocalBookRecord>>());
    },
  );

  test('parser and media IO failures do not publish a half book', () async {
    expect(
      await add('a', parse: (_) => throw const FormatException('broken')),
      isA<Failure<LocalBookRecord>>(),
    );
    expect(
      await add(
        'b',
        parse: (s) async {
          await s.writeMedia(
            Stream.error(const FileSystemException('disk full')),
          );
          return fixture(s);
        },
      ),
      isA<Failure<LocalBookRecord>>(),
    );
    expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
    expect(await paths.localBooks.list().toList(), isEmpty);
    expect(await paths.localImportStaging.list().toList(), isEmpty);
  });

  test(
    'cancellation interrupts stalled input and cancellation before publish rolls back',
    () async {
      final source = CancellationSource();
      final listening = Completer<void>();
      final input = StreamController<List<int>>(onListen: listening.complete);
      final result = store.importBook(
        bytes: input.stream,
        format: LocalBookFormat.txt,
        parse: (s) async => fixture(s),
        cancellation: source.token,
      );
      await listening.future;
      source.cancel();
      expect((await result).isCancelled, isTrue);
      await input.close();
      final later = CancellationSource();
      expect(
        (await add(
          'a',
          cancellation: later.token,
          parse: (s) async {
            later.cancel();
            return fixture(s);
          },
        )).isCancelled,
        isTrue,
      );
      expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
    },
  );

  test(
    'restart recovers staged and renamed but uncommitted imports, preserves committed data',
    () async {
      final saved = ok(await add('a'));
      final orphan = sha256.convert([99]).toString();
      await Directory('${paths.localBooks.path}/$orphan').create();
      await Directory(
        '${paths.localImportStaging.path}/import-interrupted',
      ).create();
      await store.close();
      await db.close();
      db = UserDatabase(NativeDatabase(paths.userDatabase));
      store = ok(await ManagedLocalBooks.open(paths, db));
      expect(
        ok(
          await store.read(
            saved.content.detail.summary.key,
            cancellation: token(),
          ),
        )!.content.chapters,
        saved.content.chapters,
      );
      expect(await paths.localBooks.list().toList(), hasLength(1));
      expect(await paths.localImportStaging.list().toList(), isEmpty);
    },
  );

  test(
    'root relocation preserves chapter/block keys and media bytes',
    () async {
      final saved = ok(
        await add(
          'a',
          parse: (s) async {
            expect(
              await s.openOriginal().expand((b) => b).toList(),
              utf8.encode('a'),
            );
            return fixture(
              s,
              media: await s.writeMedia(Stream.value([1, 2, 3])),
            );
          },
        ),
      );
      await store.close();
      await db.close();
      await Directory('${temp.path}/a').rename('${temp.path}/b');
      paths = AppPaths(
        support: Directory('${temp.path}/b'),
        temporary: temp,
        environment: StorageEnvironment.development,
      );
      db = UserDatabase(NativeDatabase(paths.userDatabase));
      store = ok(await ManagedLocalBooks.open(paths, db));
      final reopened = ok(
        await store.read(
          saved.content.detail.summary.key,
          cancellation: token(),
        ),
      )!;
      expect(reopened.content.chapters, saved.content.chapters);
      expect(
        ok(
          await store.readMedia(
            reopened.content.detail.summary.cover!,
            cancellation: token(),
          ),
        ),
        [1, 2, 3],
      );
    },
  );

  test('disposable clear and bookshelf removal preserve owned files', () async {
    final saved = ok(await add('a'));
    await db.customStatement(
      "INSERT INTO bookshelf VALUES('local',?,'fixture',1,1)",
      [saved.content.detail.summary.key.novelId],
    );
    await db.customStatement('DELETE FROM bookshelf');
    await paths.disposable.delete(recursive: true);
    expect(
      ok(
        await store.read(
          saved.content.detail.summary.key,
          cancellation: token(),
        ),
      ),
      isNotNull,
    );
    expect(
      await File(
        '${paths.localBooks.path}/${saved.content.detail.summary.key.novelId}/original',
      ).readAsString(),
      'a',
    );
  });

  test(
    'unmanaged references and traversal are rejected; corrupt media never delivered',
    () async {
      expect(
        await add(
          'bad',
          parse: (s) async => fixture(
            s,
            media: MediaRef(
              sourceId: LocalBookIdentity.sourceId,
              mediaId: '../outside',
            ),
          ),
        ),
        isA<Failure<LocalBookRecord>>(),
      );
      final saved = ok(
        await add(
          'a',
          parse: (s) async =>
              fixture(s, media: await s.writeMedia(Stream.value([1, 2, 3]))),
        ),
      );
      final ref = saved.content.detail.summary.cover!;
      await File('${paths.localBooks.path}/${ref.mediaId}').writeAsBytes([9]);
      expect(await store.readMedia(ref, cancellation: token()), isA<Failure>());
      expect(
        await store.readMedia(
          MediaRef(sourceId: LocalBookIdentity.sourceId, mediaId: '../outside'),
          cancellation: token(),
        ),
        isA<Failure>(),
      );
    },
  );

  test('v2 migration retains shelf and prefetch settings', () async {
    await store.close();
    await db.close();
    final sql = File(
      'lib/data/local/database/users.drift',
    ).readAsStringSync().split('CREATE TABLE local_books').first;
    final old = UserDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(sql);
          raw.execute("INSERT INTO bookshelf VALUES('s','n','keep',1,1)");
          raw.execute('INSERT INTO prefetch_settings VALUES(1,1,0)');
          raw.execute('PRAGMA user_version=2');
        },
      ),
    );
    try {
      expect(
        await old.customSelect('SELECT * FROM local_books').get(),
        isEmpty,
      );
      expect(
        (await old
                .customSelect('SELECT summary_json FROM bookshelf')
                .getSingle())
            .data['summary_json'],
        'keep',
      );
      expect(
        (await old
                .customSelect('SELECT next_enabled FROM prefetch_settings')
                .getSingle())
            .data['next_enabled'],
        0,
      );
    } finally {
      await old.close();
    }
  });

  test('oversized media rolls back and never exceeds its byte limit', () async {
    final chunk = List<int>.filled(1024 * 1024, 0);
    final result = await add(
      'large',
      parse: (s) async {
        await s.writeMedia(
          Stream.fromIterable(List.generate(33, (_) => chunk)),
        );
        return fixture(s);
      },
    );
    expect((result as Failure).failure.kind, FailureKind.tooLarge);
    expect(await paths.localImportStaging.list().toList(), isEmpty);
    expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
  });
}
