import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/local_books/local_books_screen.dart';
import 'package:shiori/features/import/import_controller.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';
import '../../domain/reparse_position_test.dart' as f;
import '../reader/settings_test.dart' show Store;
import '../../features/import/import_flow_test.dart' show MemorySource;

class LocalStore
    implements LocalBookStore, LocalBookManagement, LocalBookReparse {
  LocalStore({int count = 45})
    : books = List.generate(
        count,
        (i) => LocalBookInfo(
          key: i == 0
              ? f.key
              : LocalBookIdentity.book(i.toRadixString(16).padLeft(64, '0')),
          title: i == 0
              ? 'Book'
              : 'Local book $i with a long title for wrapping',
          format: i.isEven ? LocalBookFormat.epub : LocalBookFormat.txt,
          importedAt: DateTime.utc(2025),
        ),
      );
  final List<LocalBookInfo> books;
  final updates = StreamController<Result<List<LocalBookInfo>>>.broadcast();
  final maintenance = StreamController<NovelKey>.broadcast(sync: true);
  final changed = StreamController<NovelKey>.broadcast(sync: true);
  final calls =
      <({NovelKey key, CancellationToken token, TxtEncoding? encoding})>[];
  Completer<Result<LocalReparseResult>>? gate;
  bool prompt = false, cleanup = false;
  int watches = 0, reads = 0, deletes = 0, revision = 0;
  @override
  Stream<NovelKey> get invalidations => maintenance.stream;
  @override
  Stream<NovelKey> get changes => changed.stream;
  @override
  Stream<Result<List<LocalBookInfo>>> watchBooks() async* {
    watches++;
    yield Success(List.of(books));
    yield* updates.stream;
  }

  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    reads++;
    final content = f.book([
      [f.p('Readable revision $revision')],
    ]);
    return Success(
      LocalBookRecord(
        content: content,
        format: LocalBookFormat.epub,
        importedAt: DateTime.utc(2025),
      ),
    );
  }

  @override
  Future<Result<LocalReparseResult>> reparseBook(
    NovelKey key, {
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
    required CancellationToken cancellation,
  }) async {
    calls.add((key: key, token: cancellation, encoding: encoding));
    maintenance.add(key);
    if (prompt) {
      await chooseEncoding(
        TxtEncodingPreview({
          TxtEncoding.utf8: 'Sample',
          TxtEncoding.gb18030: 'Other sample',
        }),
      );
    }
    final result =
        await (gate?.future ??
            Future.value(
              Success(
                LocalReparseResult(approximate: true, cleanupPending: true),
              ),
            ));
    if (result is Success) {
      revision++;
      changed.add(key);
    }
    return result;
  }

  @override
  Future<Result<LocalBookDeletion>> deleteBook(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    deletes++;
    books.removeWhere((b) => b.key == key);
    changed.add(key);
    updates.add(Success(List.of(books)));
    return Success(LocalBookDeletion(cleanupPending: cleanup));
  }

  @override
  Future<void> close() async {
    await updates.close();
    await changed.close();
    await maintenance.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class LocalHarness {
  LocalHarness(this.tester, {LocalStore? store})
    : store = store ?? LocalStore();
  final WidgetTester tester;
  final LocalStore store;
  final library = FixtureLibraryRepository();
  final env = FixtureEnvironment();
  final navigation = HomeNavigation(HomeSection.localBooks);
  final source = MemorySource();
  late final importer = ImportController(source: source, store: store);
  late final repo = LocalReadingRepository(local: store, online: env.novels);
  int reads = 0, details = 0, imports = 0;
  double? bounded;
  double scale = 1;
  bool shell = false;
  bool supportsReparse = true;
  LocalBookStore get screenStore =>
      supportsReparse ? store : PlainLocalStore(store);
  String lang = 'en';
  late final Widget app = ShioriApp(
    locale: Locale(lang),
    overlayBuilder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: ImportOverlay(controller: importer, child: child),
    ),
    routes: shell
        ? const AppRoutes()
        : AppRoutes(
            home: (_) => DesktopLayoutScope(
              width: bounded ?? tester.view.physicalSize.width,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: bounded,
                  child: LocalBooksScreen(
                    store: screenStore,
                    management: store,
                    library: library,
                    onRead: (_) => reads++,
                    onDetails: (_) => details++,
                    onImport: () {
                      imports++;
                      importer.open();
                    },
                  ),
                ),
              ),
            ),
          ),
    homeBuilder: !shell
        ? null
        : (context, app) {
            final home = ReadingHome(
              repository: repo,
              library: library,
              localBooks: screenStore,
              localManagement: store,
              sources: [env.source.descriptor],
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
              navigation: navigation,
              onImport: () {
                imports++;
                importer.open();
              },
            );
            return bounded == null
                ? home
                : Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: bounded, child: home),
                  );
          },
  );
  Future<void> pump({
    double width = 1920,
    double height = 720,
    bool shell = false,
    bool supportsReparse = true,
    double? bounded,
    double scale = 1,
    String lang = 'en',
  }) async {
    this.shell = shell;
    this.supportsReparse = supportsReparse;
    this.bounded = bounded;
    this.scale = scale;
    this.lang = lang;
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  Future<void> resize(double width) async {
    tester.view.physicalSize = Size(width, tester.view.physicalSize.height);
    await tester.pumpAndSettle();
  }

  Finder get page => find.byType(LocalBooksScreen);
  Finder get view =>
      find.descendant(of: page, matching: find.byType(CustomScrollView));
  ScrollableState get scroll => tester.state(
    find.descendant(of: view, matching: find.byType(Scrollable)).first,
  );
  AppLocalizations get l => AppLocalizations.of(tester.element(page));
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    importer.dispose();
    navigation.dispose();
    await tester.runAsync(store.close);
    await tester.runAsync(library.close);
    await tester.runAsync(source.close);
    await tester.runAsync(env.close);
  }
}

/// An importer/store without the optional maintenance capability.
class PlainLocalStore implements LocalBookStore {
  PlainLocalStore(this.inner);
  final LocalStore inner;
  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) => inner.read(key, cancellation: cancellation);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
