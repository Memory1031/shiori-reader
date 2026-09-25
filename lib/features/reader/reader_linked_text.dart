import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
    required this.align,
    required this.scaler,
    this.onLink,
    this.onFootnote,
    this.inlineImages = const [],
    this.inlineRuby = const [],
    this.inlineStyles = const [],
    this.authoredBackground,
    this.images,
    this.locale,
    this.textHeightBehavior,
  });
  final String text, prefix;
  final List<InlineImage> inlineImages;
  final List<InlineRuby> inlineRuby;
  final List<InlineTextStyle> inlineStyles;
  final int? authoredBackground;
  final ImageRepository? images;
  final Locale? locale;
  final TextHeightBehavior? textHeightBehavior;
  final int blockOffset;
  final List<LocalContentLink> links;
  final TextStyle style;
  final TextAlign align;
  final TextScaler scaler;
  final ValueChanged<LocalContentLink>? onLink;

  /// Shows a tapped footnote; the footnote sheet when null.
  final ValueChanged<LocalContentLink>? onFootnote;
  @override
  State<ReaderLinkedText> createState() => _ReaderLinkedTextState();
}

class _ReaderLinkedTextState extends State<ReaderLinkedText> {
  final _recognizers = <TapGestureRecognizer>[];
  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildText(context, constraints.maxWidth),
  );

  Widget _buildText(BuildContext context, double maxWidth) {
    _clear();
    final colors = ReaderAuthoredColors(Theme.of(context));
    final background = widget.authoredBackground == null
        ? colors.paper
        : colors.resolve(
            Color(widget.authoredBackground!),
            ReaderColorRole.background,
          );
    Color foreground(Color color) => colors.resolve(
      color,
      ReaderColorRole.foreground,
      background: background,
    );
    final displayStyle = widget.style.copyWith(
      color: foreground(widget.style.color ?? colors.ink),
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
          scaler: widget.scaler,
          direction: Directionality.of(context),
          locale: widget.locale,
          maxWidth: maxWidth,
          onRubyTap: onTap,
          resolveColor: foreground,
          style: displayStyle,
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
                  style: (span.style ?? displayStyle).copyWith(
                    color: foreground(Theme.of(context).colorScheme.primary),
                  ),
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
