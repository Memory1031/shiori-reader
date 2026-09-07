import 'article_heading.dart';
import 'package:flutter/material.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';

/// Navigation projection only: never rewrite source text, block keys or offsets.
List<({String title, ReaderPosition position})> articleContents(
  ChapterContent content,
) {
  final result = <({String title, ReaderPosition position})>[];
  for (var i = 0; i < content.blocks.length; i++) {
    final block = content.blocks[i];
    final text = switch (block) {
      HeadingBlock(:final text) => text.trim(),
      ParagraphBlock(:final text) => text.trim(),
      _ => '',
    };
    if (text.isEmpty) continue;
    final recognised = block is HeadingBlock || isArticleHeading(text);
    if (!recognised) continue;
    result.add((
      title: text,
      position: ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: block.blockKey,
        blockIndex: i,
        blockFraction: 0,
        chapterFraction: ReaderPosition.fractionFor(
          blockIndex: i,
          blockFraction: 0,
          blockCount: content.blocks.length,
        ),
      ),
    ));
  }
  return result;
}

Future<ReaderPosition?> showArticleContents(
  BuildContext context,
  ChapterContent content, {
  VoidCallback? onVolumes,
}) => showModalBottomSheet<ReaderPosition>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) {
    final l = AppLocalizations.of(context);
    final entries = articleContents(content);
    return FractionallySizedBox(
      heightFactor: .8,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.articleContents,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (onVolumes != null)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onVolumes();
                      },
                      child: Text(l.volumesTitle),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                l.articleContentsHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? EmptyView(message: l.articleContentsEmpty)
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) => ListTile(
                        key: ValueKey(entries[i].position.blockKey),
                        title: Text(entries[i].title),
                        onTap: () =>
                            Navigator.of(context).pop(entries[i].position),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  },
);
