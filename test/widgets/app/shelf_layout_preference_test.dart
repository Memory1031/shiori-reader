import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/app_controller.dart';
import 'package:shiori/app/appearance_panel.dart';
import 'package:shiori/app/launch_view.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/bookshelf_view.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/state_views.dart';

import 'appearance_test.dart' show AppStore;

class ShelfStore extends AppStore {
  Completer<Result<AppSettings>>? reading;
  int loads = 0;
  @override
  Future<Result<AppSettings>> load({required CancellationToken cancellation}) {
    loads++;
    return reading?.future ?? super.load(cancellation: cancellation);
  }
}

class Harness {
  Harness(this.tester, this.store);
  final WidgetTester tester;
  final ShelfStore store;
  final env = FixtureEnvironment();
  final boundary = GlobalKey();
  final homeModes = <bool>[];
  late AppController controller;
  BookshelfView get shelf => tester.widget(find.byType(BookshelfView));
  bool get grid => shelf.layout!.value;
  AppLocalizations get l =>
      AppLocalizations.of(tester.element(find.byType(ReadingHome)));
  Widget app({String lang = 'en', double scale = 1}) => ShioriApp(
    locale: Locale(lang),
    createController: () => controller = AppController(settingsStore: store),
    overlayBuilder: (context, child) => RepaintBoundary(
      key: boundary,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    ),
    homeBuilder: (context, app) {
      homeModes.add(app.settings.shelfGrid);
      return ReadingHome(
        repository: env.novels,
        library: env.library,
        sources: const [],
        initialShelfGrid: app.settings.shelfGrid,
        onShelfGridChanged: app.setShelfGrid,
        onAppearance: () => showAppAppearance(context, app),
      );
    },
  );
  Future<void> pump({
    Size size = const Size(390, 850),
    String lang = 'en',
    double scale = 1,
    bool settle = true,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final scenario in [
      FixtureScenario.shortChapter,
      FixtureScenario.longChapter,
      FixtureScenario.multiVolume,
    ]) {
      await env.library.putBookshelf(
        BookshelfEntry(
          snapshot: env.source.data.summary(scenario),
          addedAt: DateTime.utc(2026),
        ),
        cancellation: CancellationSource().token,
      );
    }
    await tester.pumpWidget(app(lang: lang, scale: scale));
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> choose(bool value) async {
    await tester.tap(find.byTooltip(value ? l.shelfGrid : l.shelfList));
    await tester.pump();
  }

  Future<void> retire() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  Future<void> shot(String name) async {
    final dir = Platform.environment['SHIORI_SHELF_SCREENSHOTS'];
    if (dir == null) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> close() async {
    await retire();
    await env.close();
    expect(tester.takeException(), isNull);
  }
}

const platforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.windows,
});
void main() {
  for (final initial in [true, false]) {
    testWidgets(
      'deferred settings load shows no shelf before first $initial layout',
      (tester) async {
        final store = ShelfStore()..reading = Completer<Result<AppSettings>>();
        final h = Harness(tester, store);
        await h.pump(settle: false);
        expect(find.byType(LaunchView), findsOneWidget);
        expect(find.byType(ReadingHome), findsNothing);
        expect(find.byType(BookshelfView), findsNothing);
        expect(h.homeModes, isEmpty);
        await tester.pump(const Duration(seconds: 2));
        expect(h.homeModes, isEmpty);
        store.reading!.complete(Success(AppSettings(shelfGrid: initial)));
        await tester.pump();
        expect(find.byType(BookshelfView), findsOneWidget);
        expect(h.grid, initial);
        expect(h.homeModes, everyElement(initial));
        if (!initial) expect(find.byType(SliverGrid), findsNothing);
        await tester.pumpAndSettle();
        expect(h.grid, initial);
        expect(h.homeModes, everyElement(initial));
        expect(store.writes, isEmpty);
        await h.close();
      },
      variant: platforms,
    );
  }

  testWidgets(
    'whole-app restart retains selected layout, appearance and book order',
    (tester) async {
      final store = ShelfStore()
        ..value = AppSettings(
          themeMode: AppThemeMode.dark,
          accent: AppAccent.warmBrown,
        );
      final h = Harness(tester, store);
      await h.pump(size: const Size(1000, 900));
      expect(h.grid, isTrue);
      expect(store.writes, isEmpty);
      final sorted = h.shelf.controller.sorted
          .map((entry) => entry.snapshot.key)
          .toList();
      await h.choose(false);
      expect(h.grid, isFalse);
      expect(await h.controller.saveForExit(), isTrue);
      expect(store.value.shelfGrid, isFalse);
      expect(store.value.themeMode, AppThemeMode.dark);
      expect(store.value.accent, AppAccent.warmBrown);
      final controller = h.controller,
          home = tester.state(find.byType(ReadingHome));
      await h.retire();
      expect(controller.isClosed, isTrue);
      h.homeModes.clear();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(h.controller, isNot(same(controller)));
      expect(tester.state(find.byType(ReadingHome)), isNot(same(home)));
      expect(h.homeModes, everyElement(false));
      expect(h.grid, isFalse);
      expect(
        h.shelf.controller.sorted.map((entry) => entry.snapshot.key),
        sorted,
      );
      final writes = store.writes.length;
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(store.writes.length, writes);
      await h.choose(true);
      expect(h.grid, isTrue);
      expect(await h.controller.saveForExit(), isTrue);
      await h.retire();
      h.homeModes.clear();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(h.homeModes, everyElement(true));
      expect(h.grid, isTrue);
      expect(store.value.themeMode, AppThemeMode.dark);
      expect(store.value.accent, AppAccent.warmBrown);
      await h.close();
    },
    variant: platforms,
  );

  testWidgets(
    'read failure uses grid without writing defaults; load retry synchronizes without feedback',
    (tester) async {
      final store = ShelfStore()..reading = Completer<Result<AppSettings>>();
      final h = Harness(tester, store);
      await h.pump(settle: false);
      store.reading!.complete(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.settingsRead,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.grid, isTrue);
      expect(find.byType(FailureView), findsOneWidget);
      expect(store.writes, isEmpty);
      store.reading = null;
      store.value = AppSettings(shelfGrid: false);
      await h.controller.retrySettings();
      await tester.pumpAndSettle();
      expect(h.grid, isFalse);
      expect(store.writes, isEmpty);
      expect(find.byType(FailureView), findsNothing);
      await h.close();
    },
    variant: platforms,
  );

  testWidgets(
    'pending save does not roll back layout; failure preserves choice and existing retry saves latest',
    (tester) async {
      final store = ShelfStore()..pending = Completer<Result<void>>();
      final h = Harness(tester, store);
      await h.pump(size: const Size(1000, 900));
      await h.choose(false);
      expect(h.grid, isFalse);
      await h.choose(true);
      await h.choose(false);
      h.controller.setAppearance(AppThemeMode.dark);
      h.controller.setAccent(AppAccent.softPink);
      await tester.pump();
      expect(h.grid, isFalse);
      expect(store.writes, hasLength(1));
      store.pending!.complete(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.settingsWrite,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.grid, isFalse);
      expect(find.byType(FailureView), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      store.pending = null;
      tester.widget<ReadingHome>(find.byType(ReadingHome)).onAppearance!();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, h.l.retryAction));
      await tester.pumpAndSettle();
      expect(
        store.value,
        AppSettings(
          themeMode: AppThemeMode.dark,
          accent: AppAccent.softPink,
          shelfGrid: false,
        ),
      );
      expect(find.byType(FailureView), findsNothing);
      expect(store.writes, hasLength(2));
      await h.close();
    },
    variant: platforms,
  );

  testWidgets(
    'unchanged parent input cannot undo a local choice; changed external input syncs silently',
    (tester) async {
      final env = FixtureEnvironment();
      final changes = <bool>[];
      Widget app(bool grid) => ShioriApp(
        homeBuilder: (_, app) => ReadingHome(
          repository: env.novels,
          library: env.library,
          sources: const [],
          initialShelfGrid: grid,
          onShelfGridChanged: changes.add,
        ),
      );
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      BookshelfView shelf() => tester.widget(find.byType(BookshelfView));
      final layout = shelf().layout!;
      layout.value = false;
      await tester.pumpAndSettle();
      expect(changes, [false]);
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(shelf().layout!.value, isFalse);
      expect(changes, [false]);
      await tester.pumpWidget(app(false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(shelf().layout, same(layout));
      expect(layout.value, isTrue);
      expect(changes, [false]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await env.close();
    },
  );

  for (final scene in [
    (
      TargetPlatform.android,
      'zh',
      const Size(390, 850),
      1.0,
      AppThemeMode.light,
    ),
    (TargetPlatform.iOS, 'en', const Size(320, 850), 1.5, AppThemeMode.dark),
    (
      TargetPlatform.windows,
      'zh',
      const Size(900, 900),
      1.5,
      AppThemeMode.dark,
    ),
    (
      TargetPlatform.windows,
      'en',
      const Size(1600, 900),
      1.0,
      AppThemeMode.light,
    ),
  ]) {
    testWidgets(
      'render first restored list and grid ${scene.$1}/${scene.$2}',
      (tester) async {
        final font = Platform.environment['SHIORI_SHELF_FONT'];
        if (font != null) {
          await tester.runAsync(() async {
            final data = ByteData.sublistView(await File(font).readAsBytes());
            for (final family in [
              'Roboto',
              'MicrosoftYaHeiUI',
              'Microsoft YaHei UI',
              'CupertinoSystemText',
              'CupertinoSystemDisplay',
            ]) {
              await (FontLoader(family)..addFont(Future.value(data))).load();
            }
            await (FontLoader('MaterialIcons')..addFont(
                  File(
                    '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                  ).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
          });
        }
        final store = ShelfStore()
          ..value = AppSettings(shelfGrid: false, themeMode: scene.$5);
        final h = Harness(tester, store);
        await h.pump(size: scene.$3, lang: scene.$2, scale: scene.$4);
        final prefix = '${scene.$1.name}-${scene.$2}';
        expect(h.grid, isFalse);
        expect(h.homeModes, everyElement(false));
        await h.shot('$prefix-restored-list');
        await h.choose(true);
        await tester.pumpAndSettle();
        await h.shot('$prefix-chosen-grid');
        expect(await h.controller.saveForExit(), isTrue);
        await h.retire();
        h.homeModes.clear();
        await tester.pumpWidget(h.app(lang: scene.$2, scale: scene.$4));
        await tester.pumpAndSettle();
        expect(h.homeModes, everyElement(true));
        await h.shot('$prefix-restored-grid');
        await h.close();
      },
      variant: TargetPlatformVariant.only(scene.$1),
    );
  }
}
