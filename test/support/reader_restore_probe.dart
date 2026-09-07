import 'dart:io';
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
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/reader_viewport.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;
void main() =>
    runApp(ShioriApp(routes: AppRoutes(home: (_) => const _Probe())));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final env = FixtureEnvironment(scenario: FixtureScenario.extremeParagraph);
  final root = GlobalKey();
  LocalLibraryRepository? library;
  bool show = false;
  int epoch = 0;
  double width = 360, height = 480;
  String status = 'READER_RESTORE_RUNNING';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => verify());
  }

  Future<void> frames() async {
    for (var i = 0; i < 8; i++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  ReaderPosition current() {
    ReaderPosition? result;
    void visit(Element element) {
      if (element.widget case PagedReaderViewport(:final controller)) {
        result = controller.capture();
      }
      if (element.widget case ReaderViewport(:final controller)) {
        result = controller.capture();
      }
      element.visitChildElements(visit);
    }

    (root.currentContext! as Element).visitChildElements(visit);
    return result!;
  }

  Future<void> verify() async {
    LocalDatabases? db;
    try {
      // A fresh isolated fixture DB; never inspect or modify the user's history.
      final Directory folder = await (await getTemporaryDirectory()).createTemp(
        'restore-probe-',
      );
      final paths = AppPaths(
        support: folder,
        temporary: folder,
        environment: StorageEnvironment.development,
      );
      final token = CancellationSource().token;
      final content = env.source.data.content(FixtureScenario.extremeParagraph);
      final length = (content.blocks.first as ParagraphBlock).text.runes.length;
      for (final mode in ReaderMode.values) {
        db = value<LocalDatabases>(await LocalDatabases.open(paths));
        library = LocalLibraryRepository(db.users);
        final generation = value(
          await library!.beginProgressSession(
            content.key.novelKey,
            cancellation: token,
          ),
        );
        value(
          await library!.saveProgress(
            ReadingProgress(
              snapshot: env.source.data.summary(
                FixtureScenario.extremeParagraph,
              ),
              chapterKey: content.key,
              chapterOrdinalSnapshot: 0,
              catalogRevision: 'probe',
              completed: false,
              lastReadAt: fixtureEpoch,
              position: ReaderPosition(
                contentRevision: content.contentRevision,
                blockKey: content.blocks.first.blockKey,
                blockIndex: 0,
                blockFraction: .631234,
                chapterFraction: .631234,
              ),
            ),
            stamp: ProgressWriteStamp(generation: generation, sequence: 0),
            cancellation: token,
          ),
        );
        value(
          await env.settings.save(
            ReaderSettings(mode: mode, fontSize: 20),
            cancellation: token,
          ),
        );
        setState(() {
          show = true;
          epoch++;
          width = 360;
          height = 480;
        });
        await frames();
        final before = current();
        if ((before.blockFraction - .631234).abs() * length > 40) {
          throw StateError('initial anchor');
        }
        setState(() => show = false);
        await frames();
        final saved = value(
          await library!.getProgress(content.key.novelKey, cancellation: token),
        )!;
        if (saved.position != before) {
          throw StateError('stable position not persisted');
        }
        await db.close();
        db = value<LocalDatabases>(await LocalDatabases.open(paths));
        library = LocalLibraryRepository(db.users);
        setState(() {
          show = true;
          epoch++;
        });
        await frames();
        final after = current();
        final error = ((after.blockFraction - before.blockFraction) * length)
            .abs();
        if (after.blockKey != before.blockKey || error > 1) {
          throw StateError('same layout $error');
        }
        debugPrint(
          'READER_RESTORE_METRIC ${mode.name} dbReopen codePointError=$error',
        );
        setState(() {
          width = 300;
          height = 280;
        });
        await frames();
        final changed = current();
        final changeError =
            ((changed.blockFraction - after.blockFraction) * length).abs();
        if (changed.blockKey != after.blockKey || changeError > 40) {
          throw StateError('width change $changeError');
        }
        debugPrint(
          'READER_RESTORE_METRIC ${mode.name} width360to300 height480to280 codePointError=$changeError',
        );
        setState(() => show = false);
        await frames();
        await db.close();
        db = null;
      }
      await env.close();
      setState(() => status = 'READER_RESTORE_PASS');
      debugPrint(status);
    } catch (error) {
      setState(() => status = 'READER_RESTORE_FAIL $error');
      debugPrint(status);
    } finally {
      await db?.close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(status)),
    body: Center(
      child: SizedBox(
        key: root,
        width: width,
        height: height,
        child: show
            ? ReaderScreen(
                key: ValueKey(epoch),
                chapter: fixtureChapterKey(FixtureScenario.extremeParagraph),
                repository: env.novels,
                library: library,
                settings: env.settings,
              )
            : const SizedBox(),
      ),
    ),
  );
}
