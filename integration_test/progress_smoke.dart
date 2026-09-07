// Offline Android lifecycle harness. Uses a dedicated fixture database directory.
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ShioriApp(
      locale: const Locale('en'),
      routes: AppRoutes(home: (_) => const _Probe()),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with WidgetsBindingObserver {
  final _env = FixtureEnvironment(scenario: FixtureScenario.typography);
  final _readerKey = GlobalKey();
  LocalDatabases? _db;
  LocalLibraryRepository? _library;

  String _status = 'PROGRESS001_START';
  bool _checking = false;
  final _key = fixtureChapterKey(FixtureScenario.typography);
  void report(String value) {
    debugPrint(value);
    if (mounted) setState(() => _status = value);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final support = await getApplicationSupportDirectory();
      final paths = AppPaths(
        support: Directory('${support.path}/phase5-lifecycle-probe'),
        temporary: await getTemporaryDirectory(),
        environment: StorageEnvironment.development,
      );
      final opened = await LocalDatabases.open(paths);
      if (opened is! Success<LocalDatabases>) {
        report('PROGRESS001_FAIL database_open');
        return;
      }
      _db = opened.value;
      final library = _library = LocalLibraryRepository(_db!.users);
      final token = CancellationSource().token;
      final saved = await library.getProgress(
        _key.novelKey,
        cancellation: token,
      );
      if (saved is! Success<ReadingProgress?>) {
        report('PROGRESS001_FAIL progress_read');
        return;
      }
      final marker = File('${paths.root.path}/expected-position.json');
      if (await marker.exists()) {
        final expected = jsonDecode(await marker.readAsString());
        if (saved.value == null ||
            jsonEncode(_position(saved.value!.position)) !=
                jsonEncode(expected)) {
          report('PROGRESS001_FAIL cold_restore');
          return;
        }
        report('PROGRESS001_COLD_RESTORE_PASS');
      }
      await library.putBookshelf(
        BookshelfEntry(
          snapshot: _env.source.data.summary(FixtureScenario.typography),
          addedAt: DateTime.now(),
        ),
        cancellation: token,
      );
      if (!mounted) return;
      unawaited(
        Navigator.of(context)
            .push<void>(
              MaterialPageRoute(
                builder: (_) => KeyedSubtree(
                  key: _readerKey,
                  child: BookReaderScreen(
                    chapter: _key,
                    repository: _env.novels,
                    library: library,
                    settings: _env.settings,
                  ),
                ),
              ),
            )
            .then((_) => report('PROGRESS001_BACK_PASS')),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      final view = _readerView(_readerKey);
      if (view?.session == null) {
        report('PROGRESS001_FAIL reader_ready');
        return;
      }
      await view!.session!.flushProgress();
      final current = await library.getProgress(
        _key.novelKey,
        cancellation: token,
      );
      if (current is! Success<ReadingProgress?> || current.value == null) {
        report('PROGRESS001_FAIL missing_commit');
        return;
      }
      await marker.writeAsString(
        jsonEncode(_position(current.value!.position)),
        flush: true,
      );
      report('PROGRESS001_READY committed=true');
    } catch (_) {
      report('PROGRESS001_FAIL runtime');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('PROGRESS001_LIFECYCLE ${state.name}');
    if (state == AppLifecycleState.resumed && _library != null && !_checking) {
      _checking = true;
      _library!
          .getProgress(_key.novelKey, cancellation: CancellationSource().token)
          .then((value) {
            if (value is Success<ReadingProgress?> && value.value != null) {
              debugPrint('PROGRESS001_RESUME_PASS');
            }
            _checking = false;
          });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_env.close());
    unawaited(_db?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Scaffold(),
      Positioned(
        top: 70,
        left: 8,
        right: 8,
        child: IgnorePointer(child: Material(child: Text(_status))),
      ),
    ],
  );
}

List<Object?> _position(ReaderPosition p) => [
  p.contentRevision,
  p.blockKey,
  p.blockIndex,
  p.blockFraction,
  p.chapterFraction,
];

ReaderContentView? _readerView(GlobalKey key) {
  ReaderContentView? view;
  void inspect(Element element) {
    if (element.widget is ReaderContentView) {
      view = element.widget as ReaderContentView;
    }
    element.visitChildren(inspect);
  }

  final context = key.currentContext;
  if (context is Element) inspect(context);
  return view;
}
