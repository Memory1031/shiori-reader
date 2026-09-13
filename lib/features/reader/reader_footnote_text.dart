import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/contracts/local_content_links.dart';
import '../../l10n/generated/app_localizations.dart';

Future<void> showReaderFootnote(BuildContext context, LocalContentLink note) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
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

/// Uses identical glyphs and metrics to PageLayout; only marker color and
/// interaction differ. Offsets stay in source-block Unicode code points.
class ReaderFootnoteText extends StatefulWidget {
  const ReaderFootnoteText({
    super.key,
    required this.text,
    required this.prefix,
    required this.blockOffset,
    required this.notes,
    required this.style,
    required this.align,
    required this.scaler,
  });
  final String text, prefix;
  final int blockOffset;
  final List<LocalContentLink> notes;
  final TextStyle style;
  final TextAlign align;
  final TextScaler scaler;
  @override
  State<ReaderFootnoteText> createState() => _ReaderFootnoteTextState();
}

class _ReaderFootnoteTextState extends State<ReaderFootnoteText> {
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
  Widget build(BuildContext context) {
    _clear();
    final runes = widget.text.runes.toList();
    final spans = <InlineSpan>[TextSpan(text: widget.prefix)];
    var cursor = 0;
    for (final note in widget.notes) {
      final offset = note.sourceOffset;
      if (offset == null) continue;
      final start = (offset - widget.blockOffset).clamp(0, runes.length);
      final end = (offset + note.label.runes.length - widget.blockOffset).clamp(
        0,
        runes.length,
      );
      if (end <= start || start < cursor) continue;
      spans.add(
        TextSpan(text: String.fromCharCodes(runes.sublist(cursor, start))),
      );
      final recognizer = TapGestureRecognizer()
        ..onTap = () => showReaderFootnote(context, note);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: String.fromCharCodes(runes.sublist(start, end)),
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
          semanticsLabel: AppLocalizations.of(
            context,
          ).readerFootnote(note.label),
          recognizer: recognizer,
        ),
      );
      cursor = end;
    }
    spans.add(TextSpan(text: String.fromCharCodes(runes.sublist(cursor))));
    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
      textAlign: widget.align,
      textScaler: widget.scaler,
    );
  }
}
