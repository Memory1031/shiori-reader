import 'viewport/paragraph_flow.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'viewport/reader_box.dart';
import '../../domain/models/models.dart';
import '../../domain/contracts/contracts.dart';
import '../../shared/source_image.dart';
import 'reader_inline_images.dart';
import 'reader_authored_colors.dart';
import 'reader_sheet.dart';

import '../../l10n/generated/app_localizations.dart';

Future<void> showReaderFootnote(BuildContext context, LocalContentLink note) =>
    showReaderSheet<void>(
      context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l.readerFootnote(note.label)),
                trailing: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SelectableText(
                    note.footnoteText ?? l.readerLinkUnavailable,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

/// A single footnote for the desktop dialog: its number with a close
/// control, then its text, selectable and scrolling past the dialog's
/// height.
class ReaderFootnotePanel extends StatelessWidget {
  const ReaderFootnotePanel({
    super.key,
    required this.note,
    required this.onClose,
  });
  final LocalContentLink note;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.readerFootnote(note.label),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SelectableText(
              note.footnoteText ?? l.readerLinkUnavailable,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      ],
    );
  }
}

/// Uses identical glyphs and metrics to PageLayout; only marker color and
/// interaction differ. Offsets stay in source-block Unicode code points.
class ReaderLinkedText extends StatefulWidget {
  const ReaderLinkedText({
    super.key,
    required this.text,
    required this.prefix,
    required this.blockOffset,
    required this.links,
    required this.style,
    this.readerFontSize,
    this.decoration,
    this.linkLayout,
    required this.align,
    required this.scaler,
    this.flow,
    this.onLink,
    this.onFootnote,
    this.inlineImages = const [],
    this.inlineRuby = const [],
    this.inlineStacks = const [],
    this.inlineStyles = const [],
    this.authoredBackground,
    this.hasBackgroundImage = false,
    this.images,
    this.locale,
    this.textHeightBehavior,
    this.linkLabel = false,
  });
  final ParagraphFlow? flow;
  final String text, prefix;
  final List<InlineImage> inlineImages;
  final List<InlineRuby> inlineRuby;
  final List<InlineStack> inlineStacks;
  final List<InlineTextStyle> inlineStyles;
  final bool hasBackgroundImage;
  final int? authoredBackground;
  final ImageRepository? images;
  final Locale? locale;
  final TextHeightBehavior? textHeightBehavior;

  /// A decorated label inherits link color policy without a second recognizer.
  final bool linkLabel;
  final int blockOffset;
  final List<LocalContentLink> links;
  final TextStyle style;
  final double? readerFontSize;
  final LinkDecoration? decoration;
  final ReaderLinkLayout? linkLayout;
  final TextAlign align;
  final TextScaler scaler;
  final ValueChanged<LocalContentLink>? onLink;

  /// Shows a tapped footnote; the footnote sheet when null.
  final ValueChanged<LocalContentLink>? onFootnote;
  @override
  State<ReaderLinkedText> createState() => _ReaderLinkedTextState();
}

class _ReaderLinkedTextState extends State<ReaderLinkedText> {
  final _linkFocus = FocusNode(debugLabel: 'reader-authored-link');
  final _recognizers = <TapGestureRecognizer>[];
  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _linkFocus.dispose();
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        widget.decoration != null && widget.linkLayout != null
        ? _buildDecorated(context)
        : _buildText(context, constraints.maxWidth),
  );

  Widget _buildDecorated(BuildContext context) {
    final decoration = widget.decoration!, layout = widget.linkLayout!;
    final link = widget.links
        .where(
          (l) =>
              !l.isFootnote &&
              l.sourceOffset == 0 &&
              l.sourceLength == widget.text.runes.length,
        )
        .firstOrNull;
    void activate() {
      if (link != null) widget.onLink?.call(link);
    }

    final background = ReaderAuthoredColors(
      Theme.of(context),
    ).resolve(Color(decoration.backgroundColor), ReaderColorRole.background);
    return Align(
      alignment: switch (widget.align) {
        TextAlign.center => Alignment.center,
        TextAlign.right || TextAlign.end => AlignmentDirectional.centerEnd,
        _ => AlignmentDirectional.centerStart,
      },
      child: Semantics(
        link: true,
        label: widget.text,
        onTap: link == null ? null : activate,
        child: ExcludeSemantics(
          child: FocusableActionDetector(
            focusNode: _linkFocus,
            mouseCursor: SystemMouseCursors.click,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
                  ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
                  ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  activate();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: link == null
                  ? null
                  : () {
                      _linkFocus.requestFocus();
                      activate();
                    },
              child: SizedBox(
                width: layout.width,
                height: layout.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(layout.radius),
                  ),
                  child: Padding(
                    padding: layout.padding,
                    child: ReaderLinkedText(
                      text: widget.text,
                      prefix: '',
                      blockOffset: widget.blockOffset,
                      links: const [],
                      style: widget.style,
                      readerFontSize: widget.readerFontSize,
                      align: widget.align,
                      scaler: widget.scaler,
                      inlineStyles: widget.inlineStyles,
                      authoredBackground: decoration.backgroundColor,
                      linkLabel: true,
                      locale: widget.locale,
                      textHeightBehavior: widget.textHeightBehavior,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context, double maxWidth) {
    _clear();
    if (widget.flow case final flow?) {
      final runes = widget.text.runes.toList();
      return SizedBox(
        height: flow.height,
        child: Stack(
          children: [
            if (flow.dividerX case final x?)
              Positioned(
                left: x,
                top: 0,
                width: flow.dividerWidth,
                height: flow.height,
                child: ColoredBox(
                  color: ReaderAuthoredColors(
                    Theme.of(context),
                  ).resolve(Color(flow.dividerColor), ReaderColorRole.border),
                ),
              ),
            for (final line in flow.lines)
              for (final piece in line.pieces)
                Positioned(
                  left: piece.rect.left,
                  top: piece.rect.top,
                  width: piece.width,
                  child: ReaderLinkedText(
                    text: String.fromCharCodes(
                      runes.sublist(piece.start, piece.end),
                    ).replaceFirst(RegExp(r'\n$'), ''),
                    prefix: '',
                    blockOffset: widget.blockOffset + piece.start,
                    links: widget.links,
                    style: widget.style,
                    readerFontSize: widget.readerFontSize,
                    align: TextAlign.left,
                    scaler: widget.scaler,
                    onLink: widget.onLink,
                    onFootnote: widget.onFootnote,
                    inlineImages: widget.inlineImages,
                    inlineRuby: widget.inlineRuby,
                    inlineStacks: widget.inlineStacks,
                    inlineStyles: widget.inlineStyles,
                    authoredBackground: widget.authoredBackground,
                    images: widget.images,
                    locale: widget.locale,
                    textHeightBehavior: widget.textHeightBehavior,
                  ),
                ),
          ],
        ),
      );
    }
    final colors = ReaderAuthoredColors(Theme.of(context));
    final background = widget.authoredBackground == null
        ? colors.paper
        : colors.resolve(
            Color(widget.authoredBackground!),
            ReaderColorRole.background,
          );
    Color foreground(Color color) =>
        widget.hasBackgroundImage && ReaderBackgroundPresence.of(context)
        ? color
        : colors.resolve(
            color,
            ReaderColorRole.foreground,
            background: background,
          );
    final primary = Theme.of(context).colorScheme.primary;
    final linkColor = widget.authoredBackground == null
        ? foreground(primary)
        : colors.linkForeground(primary, background);
    final displayStyle = widget.style.copyWith(
      color: widget.linkLabel
          ? linkColor
          : foreground(widget.style.color ?? colors.ink),
    );
    final runes = widget.text.runes.toList();
    final spans = <InlineSpan>[TextSpan(text: widget.prefix)];
    List<InlineSpan> segment(int start, int end, {VoidCallback? onTap}) =>
        readerInlineSpans(
          text: String.fromCharCodes(runes.sublist(start, end)),
          offset: widget.blockOffset + start,
          images: widget.inlineImages,
          styles: widget.inlineStyles,
          ruby: widget.inlineRuby,
          stacks: widget.inlineStacks,
          scaler: widget.scaler,
          direction: Directionality.of(context),
          locale: widget.locale,
          maxWidth: maxWidth,
          onRubyTap: onTap,
          resolveColor: onTap == null && !widget.linkLabel
              ? foreground
              : widget.authoredBackground == null
              ? (_) => linkColor
              : (raw) =>
                    colors.linkForeground(primary, background, authored: raw),
          style: onTap == null && !widget.linkLabel
              ? displayStyle
              : displayStyle.copyWith(color: linkColor),
          readerFontSize: widget.readerFontSize,
          imageBuilder: (image) => GestureDetector(
            onTap: onTap,
            child: widget.images == null
                ? const SizedBox.shrink()
                : SourceImage(
                    media: image.media,
                    repository: widget.images!,
                    semanticLabel: image.alt,
                    backgroundColor: Colors.transparent,
                    placeholder: const Center(
                      child: Icon(Icons.image_outlined, size: 12),
                    ),
                  ),
          ),
        );
    var cursor = 0;
    final orderedLinks = [...widget.links]
      ..sort((a, b) => (a.sourceOffset ?? -1).compareTo(b.sourceOffset ?? -1));
    for (final note in orderedLinks) {
      final offset = note.sourceOffset;
      if (offset == null) continue;
      final start = (offset - widget.blockOffset).clamp(0, runes.length);
      final end =
          (offset +
                  (note.sourceLength ?? note.label.runes.length) -
                  widget.blockOffset)
              .clamp(0, runes.length);
      if (end <= start || start < cursor) continue;
      spans.add(TextSpan(children: segment(cursor, start)));
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (note.isFootnote) {
            if (widget.onFootnote case final show?) {
              show(note);
            } else {
              showReaderFootnote(context, note);
            }
          } else {
            widget.onLink?.call(note);
          }
        };
      _recognizers.add(recognizer);
      for (final span in segment(start, end, onTap: recognizer.onTap)) {
        spans.add(
          span is TextSpan
              ? TextSpan(
                  text: span.text,
                  style: span.style,
                  semanticsLabel: note.isFootnote
                      ? AppLocalizations.of(context).readerFootnote(note.label)
                      : null,
                  recognizer: recognizer,
                )
              : span,
        );
      }
      cursor = end;
    }
    spans.add(TextSpan(children: segment(cursor, runes.length)));
    return Text.rich(
      TextSpan(children: spans),
      style: displayStyle,
      textAlign: widget.align,
      textScaler: widget.scaler,
      locale: widget.locale,
      textHeightBehavior: widget.textHeightBehavior,
    );
  }
}
