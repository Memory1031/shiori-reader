import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'harness.dart';

void main() {
  for (final (locale, width, scale) in [
    ('en', 900.0, 1.0),
    ('zh', 390.0, 1.5),
  ]) {
    testWidgets(
      'passive automatic status $locale $width',
      (tester) async {
        final boundary = GlobalKey();
        final store = LocalStore(count: 3);
        for (final i in [0, 1]) {
          final book = store.books[i];
          store.books[i] = LocalBookInfo(
            key: book.key,
            title: book.title,
            format: book.format,
            importedAt: book.importedAt,
            autoReparseIssue: i == 0
                ? LocalAutoReparseIssue.approximatePosition
                : LocalAutoReparseIssue.ambiguousEncoding,
          );
        }
        final h =
            LocalHarness(
                tester,
                store: store,
                preview: (context, child) =>
                    RepaintBoundary(key: boundary, child: child),
              )
              ..lang = locale
              ..scale = scale;
        final font = Platform.environment['SHIORI_REPARSE_FONT'];
        if (font != null) {
          await tester.runAsync(() async {
            final loader = FontLoader('Microsoft YaHei UI')
              ..addFont(
                Future.value(
                  ByteData.sublistView(await File(font).readAsBytes()),
                ),
              );
            await loader.load();
          });
        }
        await h.pump(width: width, lang: locale, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text(h.l.localAutoReparseUnfinished(2)), findsOneWidget);
        expect(
          find.textContaining(h.l.localAutoReparseApproximate),
          findsOneWidget,
        );
        expect(
          find.textContaining(h.l.localAutoReparseEncoding),
          findsOneWidget,
        );
        await tester.tap(find.text('Book'));
        expect(h.reads, 1);
        final directory = Platform.environment['SHIORI_REPARSE_SCREENSHOTS'];
        if (directory != null) {
          await tester.runAsync(() async {
            await Directory(directory).create(recursive: true);
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$directory/$locale.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await h.close();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
