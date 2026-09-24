import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/dev/viewport/reader_viewport.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  ChapterContent _content = const FixtureData().content(
    FixtureScenario.longChapter,
  );
  ReaderViewportController _vertical = ReaderViewportController();
  PagedReaderController _horizontal = PagedReaderController();
  bool _paged = false;
  ReaderPosition? _initial;
  double _font = 20;
  String _status = 'READER_VIEWPORT_RUNNING';
  @override
  void initState() {
    super.initState();
    _initial = _at(1499);
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  ReaderPosition _at(int index, [double fraction = 0]) => ReaderPosition(
    contentRevision: _content.contentRevision,
    blockKey: _content.blocks[index].blockKey,
    blockIndex: index,
    blockFraction: fraction,
    chapterFraction: ReaderPosition.fractionFor(
      blockIndex: index,
      blockFraction: fraction,
      blockCount: _content.blocks.length,
    ),
  );
  Future<void> _frames() async {
    for (var i = 0; i < 5; i++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  void _check(bool result, String name) {
    if (!result) throw StateError(name);
  }

  Future<void> _verify() async {
    try {
      await _frames();
      _check(_vertical.capture()!.blockIndex == 1499, 'vertical deep');
      _check(_vertical.buildCount < 80, 'vertical build budget');
      debugPrint(
        'READER_METRIC vertical1500 mounted=${_vertical.mountedCount} built=${_vertical.buildCount}',
      );
      _vertical.restore(_at(1999));
      await _frames();
      _check(_vertical.capture()!.blockIndex == 1999, 'vertical last');
      setState(() {
        _paged = true;
        _initial = _at(1499);
      });
      await _frames();
      _check(_horizontal.capture()!.blockIndex == 1499, 'paged deep');
      _check(_horizontal.measuredChunks < 100, 'paged measure budget');
      debugPrint(
        'READER_METRIC paged1500 measured=${_horizontal.measuredChunks} cached=${_horizontal.cachedPages}',
      );
      await _horizontal.next();
      await _frames();
      _check(_horizontal.capture()!.blockIndex > 1499, 'paged next');
      await _horizontal.previous();
      await _frames();
      _check(_horizontal.capture()!.blockIndex == 1499, 'paged previous');
      _horizontal.restore(_at(1999));
      await _frames();
      _check(_horizontal.capture()!.blockIndex == 1999, 'paged last');
      setState(() {
        _content = const FixtureData().content(
          FixtureScenario.extremeParagraph,
        );
        _horizontal = PagedReaderController();
        _initial = _at(0, .75);
      });
      await _frames();
      // Content replacement first preserves the old anchor by design; restore
      // the new chapter explicitly as the production chapter owner will do.
      _horizontal.restore(_at(0, .75));
      await _frames();
      _check(
        (_horizontal.capture()!.blockFraction - .75).abs() < .0001,
        'long paragraph',
      );
      final anchor = _horizontal.capture();
      setState(() {
        _font = 28;
      });
      await _frames();
      _check(
        (_horizontal.capture()!.blockFraction - anchor!.blockFraction).abs() <
            .0001,
        'paged font',
      );
      setState(() {
        _paged = false;
        _vertical = ReaderViewportController();
        _initial = anchor;
      });
      await _frames();
      _check(
        (_vertical.capture()!.blockFraction - .75).abs() < .002,
        'mode switch',
      );
      debugPrint(
        'READER_METRIC longParagraph fraction=${_vertical.capture()!.blockFraction} mounted=${_vertical.mountedCount}',
      );
      setState(() => _status = 'READER_VIEWPORT_PASS');
      debugPrint(_status);
    } catch (error) {
      setState(() => _status = 'READER_VIEWPORT_FAIL $error');
      debugPrint(_status);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_status)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _paged
            ? PagedReaderViewport(
                content: _content,
                controller: _horizontal,
                initialPosition: _initial,
                textStyle: TextStyle(fontSize: _font, height: 1.7),
              )
            : ReaderViewport(
                content: _content,
                controller: _vertical,
                initialPosition: _initial,
                textStyle: TextStyle(fontSize: _font, height: 1.7),
              ),
      ),
    ),
  );
}
