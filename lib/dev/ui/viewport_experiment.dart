import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../features/reader/viewport/reader_viewport.dart';
import '../../features/reader/viewport/paged_reader_viewport.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';

/// READER-001 lab: local controls only, no persisted mode/settings/progress.
class ViewportExperiment extends StatefulWidget {
  const ViewportExperiment({
    super.key,
    required this.content,
    required this.images,
  });
  final ChapterContent content;
  final ImageRepository images;
  @override
  State<ViewportExperiment> createState() => _ViewportExperimentState();
}

class _ViewportExperimentState extends State<ViewportExperiment> {
  final _paged = PagedReaderController();
  final _scroll = ReaderViewportController();
  final _ratios = <MediaRef, double>{};
  bool _isPaged = true;
  double _fontSize = 20;
  ReaderPosition? _anchor;
  ReaderPosition? _capture() => _isPaged ? _paged.capture() : _scroll.capture();
  void _jump(int block, double fraction) {
    final content = widget.content;
    final position = ReaderPosition(
      contentRevision: content.contentRevision,
      blockKey: content.blocks[block].blockKey,
      blockIndex: block,
      blockFraction: fraction,
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: block,
        blockFraction: fraction,
        blockCount: content.blocks.length,
      ),
    );
    if (_isPaged) {
      _paged.restore(position);
    } else {
      _scroll.restore(position);
    }
  }

  void _dimensions(MediaRef ref, Size size) {
    final ratio = size.height / size.width;
    if (!mounted || _ratios[ref] == ratio) return;
    setState(() {
      _anchor = _capture();
      _ratios[ref] = ratio;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.readerTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ChoiceChip(
                  label: Text(strings.pagedReading),
                  selected: _isPaged,
                  onSelected: (_) {
                    if (_isPaged) return;
                    setState(() {
                      _anchor = _capture();
                      _isPaged = true;
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(strings.scrollReading),
                  selected: !_isPaged,
                  onSelected: (_) {
                    if (!_isPaged) return;
                    setState(() {
                      _anchor = _capture();
                      _isPaged = false;
                    });
                  },
                ),
                for (final index in [0, 1499, 1999])
                  TextButton(
                    onPressed: index < widget.content.blocks.length
                        ? () => _jump(index, 0)
                        : null,
                    child: Text('${index + 1}'),
                  ),
                TextButton(
                  onPressed: () => _jump(
                    widget.content.blocks.length == 1
                        ? 0
                        : (widget.content.blocks.length * .75).floor(),
                    widget.content.blocks.length == 1 ? 0.75 : 0,
                  ),
                  child: const Text('75%'),
                ),
              ],
            ),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Aa ${_fontSize.round()}'),
                ),
                Expanded(
                  child: Slider(
                    value: _fontSize,
                    min: 14,
                    max: 32,
                    divisions: 18,
                    onChanged: (value) {
                      setState(() {
                        _anchor = _capture();
                        _fontSize = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final heights = {
                      for (final entry in _ratios.entries)
                        entry.key: entry.value * constraints.maxWidth,
                    };
                    Widget image(BuildContext context, ImageBlock block) =>
                        _LabImage(
                          key: ValueKey(block.media),
                          repository: widget.images,
                          image: block,
                          onDimensions: (size) =>
                              _dimensions(block.media, size),
                        );
                    if (_isPaged) {
                      return PagedReaderViewport(
                        content: widget.content,
                        controller: _paged,
                        initialPosition: _anchor,
                        textStyle: TextStyle(fontSize: _fontSize, height: 1.7),
                        imageHeights: heights,
                        imageBuilder: image,
                      );
                    }
                    return ReaderViewport(
                      content: widget.content,
                      controller: _scroll,
                      initialPosition: _anchor,
                      textStyle: TextStyle(fontSize: _fontSize, height: 1.7),
                      imageBuilder: (context, block) {
                        final height =
                            heights[block.media] ??
                            (block.width != null && block.height != null
                                ? constraints.maxWidth *
                                      block.height! /
                                      block.width!
                                : 180.0);
                        return SizedBox(
                          height: height,
                          child: image(context, block),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabImage extends StatefulWidget {
  const _LabImage({
    super.key,
    required this.repository,
    required this.image,
    required this.onDimensions,
  });
  final ImageRepository repository;
  final ImageBlock image;
  final void Function(Size) onDimensions;
  @override
  State<_LabImage> createState() => _LabImageState();
}

class _LabImageState extends State<_LabImage> {
  final _cancellation = CancellationSource();
  MediaLease? _lease;
  AppFailure? _failure;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancellation.cancel();
    unawaited(_lease?.close());
    super.dispose();
  }

  Future<void> _load() async {
    final result = await widget.repository.load(
      widget.image.media,
      mode: ReadMode.cacheFirst,
      cancellation: _cancellation.token,
    );
    if (!mounted) {
      if (result case Success(:final value)) await value.value.close();
      return;
    }
    switch (result) {
      case Failure(:final failure):
        setState(() => _failure = failure);
      case Success(:final value):
        final lease = value.value;
        final data = lease.data as MemoryMedia;
        try {
          final codec = await ui.instantiateImageCodec(data.bytes);
          try {
            final frame = await codec.getNextFrame();
            try {
              if (mounted) {
                widget.onDimensions(
                  Size(
                    frame.image.width.toDouble(),
                    frame.image.height.toDouble(),
                  ),
                );
              }
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
          if (!mounted) {
            await lease.close();
            return;
          }
          setState(() {
            _lease = lease;
            _failure = null;
          });
        } catch (_) {
          await lease.close();
          if (mounted) {
            setState(
              () => _failure = AppFailure(
                kind: FailureKind.parse,
                operation: Operation.media,
                retryPolicy: RetryPolicy.manual,
              ),
            );
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failure case final failure?) {
      return FailureView(failure: failure, onRetry: _load);
    }
    if (_lease == null) return const Center(child: CircularProgressIndicator());
    return Image.memory(
      (_lease!.data as MemoryMedia).bytes,
      fit: BoxFit.contain,
      semanticLabel: widget.image.alt,
    );
  }
}
