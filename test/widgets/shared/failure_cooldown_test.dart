import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/state_views.dart';

final start = DateTime.utc(2026, 10, 13);
AppFailure limited(DateTime? deadline) => AppFailure(
  kind: FailureKind.rateLimited,
  operation: Operation.chapter,
  retryPolicy: RetryPolicy.manual,
  retryNotBefore: deadline,
);
const preview = bool.fromEnvironment('COOLDOWN_PREVIEW');
bool fontLoaded = false;
Future<void> render(
  WidgetTester tester,
  Widget child, {
  GlobalKey? capture,
  String lang = 'en',
  Brightness brightness = Brightness.light,
  double width = 390,
}) async {
  tester.view
    ..physicalSize = Size(width, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (preview && !fontLoaded) {
    final path = Platform.environment['SHIORI_PREVIEW_FONT'];
    if (path != null) {
      await tester.runAsync(() async {
        await (FontLoader('CooldownPreview')..addFont(
              Future.value(
                ByteData.sublistView(await File(path).readAsBytes()),
              ),
            ))
            .load();
      });
      fontLoaded = true;
    }
  }
  final theme = appTheme(brightness);
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: fontLoaded
            ? theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'CooldownPreview'),
              )
            : theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
}

Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
  if (!preview) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('.tooling/cooldown')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(png!.buffer.asUint8List());
  });
}

FilledButton button(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  for (final view in [
    (lang: 'zh', width: 360.0, brightness: Brightness.dark),
    (lang: 'en', width: 1000.0, brightness: Brightness.light),
  ]) {
    testWidgets(
      '${view.lang} retry enables at the deadline with no automatic action',
      (tester) async {
        var now = start, retries = 0;
        final capture = GlobalKey();
        await render(
          tester,
          FailureView(
            failure: limited(start.add(const Duration(minutes: 1))),
            onRetry: () => retries++,
            now: () => now,
          ),
          capture: capture,
          lang: view.lang,
          width: view.width,
          brightness: view.brightness,
        );
        expect(button(tester).onPressed, isNull);
        final bounds = tester.getRect(find.byType(FilledButton));
        await shot(tester, capture, '${view.lang}-disabled');
        now = start.add(const Duration(seconds: 59));
        await tester.pump(const Duration(seconds: 59));
        expect(button(tester).onPressed, isNull);
        now = start.add(const Duration(minutes: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(button(tester).onPressed, isNotNull);
        expect(tester.getRect(find.byType(FilledButton)), bounds);
        expect(retries, 0);
        await tester.pump(const Duration(minutes: 2));
        expect(retries, 0);
        await shot(tester, capture, '${view.lang}-enabled');
        await tester.tap(find.byType(FilledButton));
        expect(retries, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'new deadlines replace old timers and owner unavailability stays disabled',
    (tester) async {
      var now = start, retries = 0;
      Future<void> show(DateTime? deadline, {bool available = true}) => render(
        tester,
        FailureView(
          failure: limited(deadline),
          onRetry: () => retries++,
          now: () => now,
          retryAvailable: available,
        ),
      );
      await show(start.add(const Duration(seconds: 60)));
      now = start.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      await show(start.add(const Duration(seconds: 90)), available: false);
      now = start.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 30));
      expect(button(tester).onPressed, isNull);
      now = start.add(const Duration(seconds: 90));
      await tester.pump(const Duration(seconds: 30));
      expect(button(tester).onPressed, isNull);
      await show(start.add(const Duration(seconds: 90)));
      expect(button(tester).onPressed, isNotNull);
      await show(null);
      now = start.add(const Duration(days: 1));
      await tester.pump(const Duration(days: 1));
      expect(button(tester).onPressed, isNull);
      expect(retries, 0);
    },
  );

  testWidgets('unmount cancels pending cooldown notifications', (tester) async {
    var now = start, retries = 0;
    await render(
      tester,
      FailureView(
        failure: limited(start.add(const Duration(minutes: 1))),
        onRetry: () => retries++,
        now: () => now,
      ),
    );
    await tester.pumpWidget(const SizedBox());
    now = start.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(retries, 0);
    expect(tester.takeException(), isNull);
  });
}
