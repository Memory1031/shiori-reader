import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';

Future<List<int> Function(int, int)> pixels(
  BlockBox box, {
  bool top = true,
  bool bottom = true,
  String? screenshot,
}) async {
  final recorder = ui.PictureRecorder();
  ReaderBoxPainter(
    box,
    ReaderBoxGeometry(box, 100, 20, 200),
    top,
    bottom,
    ReaderAuthoredColors(ThemeData.light()),
  ).paint(Canvas(recorder), const Size(100, 80));
  final picture = recorder.endRecording(),
      image = await picture.toImage(100, 80);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final copy = bytes!.buffer.asUint8List().toList();
  final directory = Platform.environment['SHIORI_BORDER_SCREENSHOTS'];
  if (directory != null && screenshot != null) {
    await Directory(directory).create(recursive: true);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/$screenshot.png',
    ).writeAsBytes(png!.buffer.asUint8List());
  }
  image.dispose();
  picture.dispose();
  return (x, y) => copy.sublist((y * 100 + x) * 4, (y * 100 + x) * 4 + 4);
}

BlockBox border(BoxBorderStyle style, {double radius = 0}) {
  final side = BoxBorderSide(
    style: style,
    width: LayoutLength(6, LayoutUnit.px),
    color: 0xff808080,
  );
  return BlockBox(
    group: 1,
    borders: BoxBorders(top: side, right: side, bottom: side, left: side),
    radius: radius == 0 ? null : LayoutLength(radius, LayoutUnit.px),
  );
}

void main() {
  testWidgets('rounded border ring includes all diagonal corner arcs', (
    tester,
  ) async {
    final side = BoxBorderSide(width: LayoutLength(2), color: 0xff808080);
    final box = BlockBox(
      group: 1,
      borders: BoxBorders(top: side, right: side, bottom: side, left: side),
      radius: LayoutLength(20),
    );
    final get = (await tester.runAsync(
      () => pixels(box, screenshot: 'rounded-ring'),
    ))!;
    for (final point in [(6, 6), (93, 6), (93, 73), (6, 73)]) {
      expect(get(point.$1, point.$2).last, greaterThan(200), reason: '$point');
    }
    expect(get(0, 0).last, 0);
    expect(get(10, 10).last, 0);
    expect(get(50, 1).last, 255);
  });
  testWidgets(
    'rounded joins preserve unequal side colors and open page slices',
    (tester) async {
      BoxBorderSide side(double width, int color) =>
          BoxBorderSide(width: LayoutLength(width), color: color);
      final box = BlockBox(
        group: 1,
        radius: LayoutLength(20),
        borders: BoxBorders(
          top: side(4, 0xffa03030),
          right: side(2, 0xff30a030),
          bottom: side(6, 0xffa03030),
          left: side(8, 0xff3060a0),
        ),
      );
      final full = (await tester.runAsync(
            () => pixels(box, screenshot: 'rounded-unequal'),
          ))!,
          middle = (await tester.runAsync(
            () => pixels(box, top: false, bottom: false),
          ))!;
      expect(full(14, 2).last, 255);
      expect(full(14, 2).first, greaterThan(full(14, 2)[2]));
      expect(full(2, 14).last, 255);
      expect(full(2, 14)[2], greaterThan(full(2, 14).first));
      expect(full(98, 40)[1], greaterThan(full(98, 40).first));
      expect(middle(50, 0).last, 0);
      expect(middle(50, 79).last, 0);
      expect(middle(2, 0).last, 255);
      expect(middle(98, 79).last, 255);
    },
  );
  testWidgets('rounded double bands retain their diagonal gap', (tester) async {
    final get = (await tester.runAsync(
      () => pixels(
        border(BoxBorderStyle.doubleLine, radius: 20),
        screenshot: 'rounded-double',
      ),
    ))!;
    expect(get(6, 6).last, greaterThan(200));
    expect(get(7, 8).last, 0);
    expect(get(9, 9).last, greaterThan(200));
  });
  testWidgets('double draws separated bands with the same geometry as solid', (
    tester,
  ) async {
    final get = await tester.runAsync(
      () => pixels(border(BoxBorderStyle.doubleLine)),
    );
    expect(get!(50, 0).last, 255);
    expect(get(50, 3).last, 0);
    expect(get(50, 5).last, 255);
    final solid = ReaderBoxGeometry(border(BoxBorderStyle.solid), 100, 20, 200),
        doubleLine = ReaderBoxGeometry(
          border(BoxBorderStyle.doubleLine),
          100,
          20,
          200,
        );
    expect(doubleLine.contentWidth, solid.contentWidth);
    expect(doubleLine.top, solid.top);
  });
  testWidgets(
    'ridge and groove reverse outer and inner lighting on joined sides',
    (tester) async {
      final ridge = (await tester.runAsync(
            () => pixels(border(BoxBorderStyle.ridge)),
          ))!,
          groove = (await tester.runAsync(
            () => pixels(border(BoxBorderStyle.groove)),
          ))!;
      expect(ridge(50, 1).first, greaterThan(ridge(50, 4).first));
      expect(ridge(98, 40).first, lessThan(ridge(95, 40).first));
      expect(ridge(50, 1), groove(50, 4));
      expect(ridge(50, 4), groove(50, 1));
      final transparent = BoxBorderSide(
        style: BoxBorderStyle.ridge,
        width: LayoutLength(6),
        color: 0,
      );
      final clear = (await tester.runAsync(
        () => pixels(BlockBox(group: 1, borders: BoxBorders(top: transparent))),
      ))!;
      expect(clear(50, 1).last, 0);
      expect(clear(50, 4).last, 0);
    },
  );
  testWidgets(
    'rounded backgrounds keep only the authored start and end corners',
    (tester) async {
      final box = BlockBox(
        group: 1,
        backgroundColor: 0xff383838,
        radius: LayoutLength(12, LayoutUnit.px),
      );
      final full = (await tester.runAsync(() => pixels(box)))!,
          first = (await tester.runAsync(() => pixels(box, bottom: false)))!,
          middle = (await tester.runAsync(
            () => pixels(box, top: false, bottom: false),
          ))!,
          last = (await tester.runAsync(() => pixels(box, top: false)))!;
      expect(full(0, 0).last, 0);
      expect(full(50, 0).last, 255);
      expect(full(0, 79).last, 0);
      expect(first(0, 0).last, 0);
      expect(first(0, 79).last, 255);
      expect(middle(0, 0).last, 255);
      expect(middle(0, 79).last, 255);
      expect(last(0, 0).last, 255);
      expect(last(0, 79).last, 0);
      final open = (await tester.runAsync(
        () => pixels(
          border(BoxBorderStyle.doubleLine),
          top: false,
          bottom: false,
        ),
      ))!;
      expect(open(50, 0).last, 0);
      expect(open(50, 79).last, 0);
      expect(open(0, 40).last, 255);
    },
  );
}
