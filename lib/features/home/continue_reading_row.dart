import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';
import '../reader/book_progress_label.dart';

/// The desktop shelf's compact resume entry: one row as wide as the shelf
/// frame, with its heading folded in. The whole row resumes on click; the
/// button is its only keyboard stop.
class ContinueReadingRow extends StatelessWidget {
  const ContinueReadingRow({
    super.key,
    required this.progress,
    required this.onContinue,
    this.images,
  });

  final ReadingProgress progress;
  final VoidCallback onContinue;
  final ImageRepository? images;

  static const minHeight = 104.0;
  static const coverWidth = 56.0;
  static const progressWidth = 160.0;

  /// The button moves under the text when the text column beside it, after
  /// the button's own width at the current language and text size, would
  /// be narrower than this.
  static const stackBelow = 220.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = AppLocalizations.of(context);
    final bookProgress = progress.bookProgress;
    final radius = BorderRadius.circular(ShioriShape.control);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.detailContinue,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ShioriSpace.tight),
        Text(
          progress.snapshot.title,
          maxLines: largeText ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: ShioriSpace.small),
        Text(
          bookProgressLabel(strings, bookProgress, descriptive: true) ??
              strings.readerReadingProgress,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (bookProgress != null) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: progressWidth),
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: bookProgress.fraction,
                minHeight: 3,
                borderRadius: BorderRadius.circular(ShioriShape.indicator),
                color: colors.primary.withValues(alpha: .75),
                backgroundColor: colors.primary.withValues(alpha: .10),
                stopIndicatorRadius: 0,
              ),
            ),
          ),
        ],
      ],
    );
    final button = FilledButton.tonalIcon(
      onPressed: onContinue,
      style: FilledButton.styleFrom(
        minimumSize: const Size(112, 40),
        padding: const EdgeInsets.symmetric(horizontal: ShioriSpace.item),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(strings.homeContinueAction),
    );

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      clipBehavior: Clip.antiAlias,
      // The button carries focus and semantics; the row is a larger target
      // for the pointer only.
      child: InkWell(
        onTap: onContinue,
        canRequestFocus: false,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ShioriSpace.item,
              vertical: 10,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: coverWidth,
                  height: coverWidth / ShioriShape.coverRatio,
                  child: BookCover(book: progress.snapshot, images: images),
                ),
                const SizedBox(width: ShioriSpace.item),
                Expanded(
                  child: _ResumeLayout(text: text, button: button),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [text] with [button] after it while the text keeps
/// [ContinueReadingRow.stackBelow] beside the button's laid-out width;
/// otherwise the button goes under the text.
class _ResumeLayout extends MultiChildRenderObjectWidget {
  _ResumeLayout({required Widget text, required Widget button})
    : super(children: [text, button]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderResumeLayout(Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderResumeLayout renderObject,
  ) => renderObject.textDirection = Directionality.of(context);
}

class _RenderResumeLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ResumeParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ResumeParentData> {
  _RenderResumeLayout(this._textDirection);

  static const _gap = ShioriSpace.item, _stackGap = ShioriSpace.small;

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _text => firstChild!;
  RenderBox get _button => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ResumeParentData) {
      child.parentData = _ResumeParentData();
    }
  }

  /// The text width beside a button [button] wide, or null when the button
  /// goes under the text.
  double? _besideWidth(BoxConstraints constraints, double button) {
    if (!constraints.hasBoundedWidth) return null;
    final text = constraints.maxWidth - button - _gap;
    return text >= ContinueReadingRow.stackBelow ? text : null;
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    Size measure(RenderBox child, BoxConstraints c) => dry
        ? child.getDryLayout(c)
        : (child..layout(c, parentUsesSize: true)).size;

    final button = measure(_button, loose);
    final beside = _besideWidth(constraints, button.width);
    if (beside != null) {
      final text = measure(_text, BoxConstraints.tightFor(width: beside));
      final result = constraints.constrain(
        Size(constraints.maxWidth, math.max(text.height, button.height)),
      );
      if (!dry) {
        final rtl = _textDirection == TextDirection.rtl;
        _offset(
          _text,
          Offset(
            rtl ? result.width - text.width : 0,
            (result.height - text.height) / 2,
          ),
        );
        _offset(
          _button,
          Offset(
            rtl ? 0 : result.width - button.width,
            (result.height - button.height) / 2,
          ),
        );
      }
      return result;
    }
    final text = measure(_text, loose);
    final result = constraints.constrain(
      Size(
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : math.max(text.width, button.width),
        text.height + _stackGap + button.height,
      ),
    );
    if (!dry) {
      double start(Size child) =>
          _textDirection == TextDirection.rtl ? result.width - child.width : 0;
      _offset(_text, Offset(start(text), 0));
      _offset(_button, Offset(start(button), text.height + _stackGap));
    }
    return result;
  }

  void _offset(RenderBox child, Offset offset) =>
      (child.parentData! as _ResumeParentData).offset = offset;

  @override
  void performLayout() => size = _layout(constraints, dry: false);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _text.getMinIntrinsicWidth(double.infinity),
    _button.getMinIntrinsicWidth(double.infinity),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _text.getMaxIntrinsicWidth(double.infinity) +
      _gap +
      _button.getMaxIntrinsicWidth(double.infinity);

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final button = _button.getMaxIntrinsicWidth(double.infinity);
    final beside = _besideWidth(BoxConstraints(maxWidth: width), button);
    final buttonHeight = _button.getMaxIntrinsicHeight(button);
    return beside != null
        ? math.max(_text.getMaxIntrinsicHeight(beside), buttonHeight)
        : _text.getMaxIntrinsicHeight(width) + _stackGap + buttonHeight;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _ResumeParentData extends ContainerBoxParentData<RenderBox> {}
