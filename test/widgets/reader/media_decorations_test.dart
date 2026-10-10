import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';

Future<List<int> Function(int, int)> pixels(
  BlockBox box, {
  bool top = true,
  bool bottom = true,
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
