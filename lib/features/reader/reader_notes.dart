import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reader_sheet.dart';

/// Opens the chapter's notes over the reader. Resolves with the chosen
/// cross-reference to follow, or null when the sheet just closes.
///
/// Pass the reader's own context so the sheet takes the reading paper.
Future<LocalContentLink?> showReaderNotes(
  BuildContext readerContext, {
  required List<LocalContentLink> links,
  required ChapterKey current,
  required String? Function(ChapterKey target) titleOf,
}) => showReaderSheet<LocalContentLink>(
  readerContext,
  builder: (sheet) => ReaderNotesPanel(
    links: links,
    current: current,
    titleOf: titleOf,
    onFollow: (link) => Navigator.of(sheet).pop(link),
  ),
);

/// A chapter's footnotes, readable in place, and its cross-references.
/// Placement agnostic: a sheet on phones, a side panel on desktop.
class ReaderNotesPanel extends StatelessWidget {
  const ReaderNotesPanel({
    super.key,
    required this.links,
    required this.current,
    required this.titleOf,
    required this.onFollow,
    this.onClose,
  });
  final List<LocalContentLink> links;
  final ChapterKey current;

  /// Display title of a link target, when the book's navigation names it.
  final String? Function(ChapterKey target) titleOf;
  final ValueChanged<LocalContentLink> onFollow;

  /// Ends the header with a close control, for a side panel without a drag
  /// handle. The panel then fills the height it is given.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notes = [
      for (final link in links)
        if (link.isFootnote) link,
    ];
    final references = [
      for (final link in links)
        if (!link.isFootnote) link,
    ];

    Widget section(String label, int count) => Padding(
      padding: const EdgeInsets.fromLTRB(
        ShioriSpace.page,
        ShioriSpace.medium,
        ShioriSpace.page,
        ShioriSpace.tight,
      ),
      child: Text(
        '$label · $count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    String destination(LocalContentLink link) {
      if (link.unavailable != null) return l.readerLinkUnavailable;
      final target = link.target!;
      if (target == current) return l.readerLinkHere;
      return titleOf(target) ?? l.readerLinkElsewhere;
    }

    final title = Text(l.readerLinks, style: theme.textTheme.titleLarge);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: onClose == null
            ? MediaQuery.sizeOf(context).height * .75
            : double.infinity,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onClose case final close?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ShioriSpace.page,
                ShioriSpace.small,
                ShioriSpace.small,
                0,
              ),
              child: Row(
                children: [
                  Expanded(child: title),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ShioriSpace.page),
              child: title,
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: ShioriSpace.item),
              children: [
                if (notes.isNotEmpty) ...[
                  section(l.readerNotesFootnotes, notes.length),
                  for (final note in notes)
                    _Footnote(key: ObjectKey(note), note: note),
                ],
                if (references.isNotEmpty) ...[
                  section(l.readerNotesLinks, references.length),
                  for (final link in references)
                    ListTile(
                      key: ObjectKey(link),
                      enabled: link.unavailable == null,
                      title: Text(
                        link.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        destination(link),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        link.unavailable == null
                            ? Icons.chevron_right
                            : Icons.link_off,
                      ),
                      onTap: () => onFollow(link),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Marker plus note text; long notes clamp to three lines and expand on tap.
class _Footnote extends StatefulWidget {
  const _Footnote({super.key, required this.note});
  final LocalContentLink note;

  @override
  State<_Footnote> createState() => _FootnoteState();
}

class _FootnoteState extends State<_Footnote> {
  static const _collapsedLines = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = widget.note;
    final text = note.footnoteText;
    final style = theme.textTheme.bodyMedium!.copyWith(
      color: text == null ? scheme.onSurfaceVariant : null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Marker column plus the row's horizontal padding.
        const reserved = 2 * ShioriSpace.page + 28 + ShioriSpace.medium;
        final painter = TextPainter(
          text: TextSpan(text: text ?? l.readerLinkUnavailable, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: (constraints.maxWidth - reserved).clamp(0, 1e9));
        final long = painter.didExceedMaxLines;
        painter.dispose();
        final row = Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ShioriSpace.page,
            vertical: ShioriSpace.small,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 28, minHeight: 22),
                margin: const EdgeInsets.only(top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(ShioriShape.tag),
                ),
                child: Text(
                  _marker(note.label),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: ShioriSpace.medium),
              Expanded(
                child: AnimatedSize(
                  duration: ShioriMotion.of(context, ShioriMotion.transition),
                  alignment: Alignment.topCenter,
                  child: Text(
                    text ?? l.readerLinkUnavailable,
                    maxLines: _expanded ? null : _collapsedLines,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ),
            ],
          ),
        );
        if (!long) {
          return Semantics(label: l.readerFootnote(note.label), child: row);
        }
        return Semantics(
          label: l.readerFootnote(note.label),
          expanded: _expanded,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: row,
          ),
        );
      },
    );
  }

  /// Markers such as "(1)", "[1]" or a superscript "⁽¹⁾" read best as a
  /// plain number inside the badge.
  static String _marker(String label) {
    const superscripts = '⁰¹²³⁴⁵⁶⁷⁸⁹';
    final trimmed = label.trim();
    final plain = String.fromCharCodes(
      trimmed.runes.map((rune) {
        final digit = superscripts.runes.toList().indexOf(rune);
        return digit < 0 ? rune : 0x30 + digit;
      }),
    );
    final bare = plain.replaceAll(RegExp(r'^[(\[（【〔⁽]+|[)\]）】〕⁾]+$'), '');
    return bare.isEmpty ? trimmed : bare;
  }
}
