// Manual native acceptance with an owned directory; never opens the user's library.
// Launch with <directory> prepare|resume. Inspect state.json while using native
// focus/minimize controls; quit normally, then resume with the same directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shiori/app/production_app.dart';
import 'package:shiori/data/import/desktop_import_source.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/shared/widgets/reading_statistics_scope.dart';

class _Paths extends AppPaths {
  _Paths(Directory root)
    : id = root.uri.pathSegments.where((s) => s.isNotEmpty).last,
      super(
        support: root,
        temporary: root,
        environment: StorageEnvironment.development,
      );
  final String id;
  @override
  String get settingsKey => 'shiori.statistics-smoke.$id.reader';
  @override
  String get appSettingsKey => 'shiori.statistics-smoke.$id.appearance';
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 2 || !['prepare', 'resume'].contains(args[1])) {
    throw ArgumentError('Expected an owned directory and prepare|resume');
  }
  final root = Directory(args[0]).absolute;
  if (await File('${root.path}/statistics-smoke.owner').readAsString() !=
      'shiori-statistics-smoke') {
    throw ArgumentError('Missing ownership marker');
  }
  final paths = _Paths(root), app = GlobalKey();
  runApp(
    KeyedSubtree(
      key: app,
      child: ProductionApp(resolvePaths: () async => paths),
    ),
  );
  List<T> widgets<T extends Widget>() {
    final found = <T>[];
    void visit(Element element) {
      if (element.widget is T) found.add(element.widget as T);
      element.visitChildren(visit);
    }

    app.currentContext?.visitChildElements(visit);
    return found;
  }

  Future<void> until(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Reader readiness timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  try {
    await until(
      () =>
          widgets<BookshelfView>().isNotEmpty &&
          widgets<BookshelfView>().single.controller.shelfReady,
    );
    if (args[1] == 'prepare') {
      if (widgets<BookshelfView>().single.controller.books.isNotEmpty) {
        throw StateError('Expected a fresh root');
      }
      final text = File('${root.path}/statistics-smoke.txt');
      await text.writeAsString(
        '第一章\n${List.generate(100, (i) => '第 $i 段。${'用于阅读统计原生验收的合成正文。' * 20}').join('\n')}',
      );
      final intake = DesktopImportSource(
        inbox: paths.importInbox,
        selectFiles: () async => [XFile(text.path)],
      );
      await intake.pick();
      await intake.close();
      final imports = widgets<ImportOverlay>().single.controller;
      await imports.refresh();
      imports.open();
      await imports.submit();
      if (imports.succeededCount != 1) {
        throw StateError('Production import failed');
      }
      await imports.finish();
      await text.delete();
    }
    await until(
      () => widgets<BookshelfView>().single.controller.books.length == 1,
    );
    final shelf = widgets<BookshelfView>().single;
    shelf.onOpen(shelf.controller.books.single.snapshot.key);
    await until(
      () =>
          widgets<ReaderContentView>().length == 1 &&
          widgets<ReaderContentView>().single.viewportController?.capture() !=
              null,
    );
    final recorder = widgets<ReadingStatisticsScope>().single.controller;
    var writing = false;
    Timer? reporting;
    Future<void> report() async {
      if (widgets<ReadingStatisticsScope>().isEmpty) {
        reporting?.cancel();
        return;
      }
      if (writing) return;
      writing = true;
      try {
        final now = DateTime.now();
        final result = await recorder.repository.read(
          firstDay: readingDay(now),
          lastDay: readingDay(now),
          today: readingDay(now),
        );
        final snapshot = (result as Success<ReadingStatisticsSnapshot>).value;
        final reader = widgets<ReaderContentView>().lastOrNull;
        final position = reader?.viewportController?.capture();
        final output = File('${root.path}/state.tmp');
        await output.writeAsString(
          jsonEncode({
            'pid': pid,
            'phase': args[1],
            'recording': recorder.recording,
            'foreground': recorder.foreground,
            'focused': recorder.focused,
            'nativeAvailable': recorder.nativeAvailable,
            'failure': '${recorder.failure}',
            'total': snapshot.total,
            'epoch': snapshot.settings.epoch,
            'position': position == null
                ? null
                : {
                    'block': position.blockIndex,
                    'fraction': position.blockFraction,
                  },
          }),
        );
        await output.rename('${root.path}/state.json');
      } finally {
        writing = false;
      }
    }

    await report();
    reporting = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(report()),
    );
  } catch (error, stack) {
    await File('${root.path}/failed.txt').writeAsString('$error\n$stack');
    rethrow;
  }
}
