import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';
import '../local_books/local_catalog.dart';
import '../novel_detail/catalog_controller.dart';
import '../novel_detail/catalog_view.dart';
import 'article_contents.dart';
import 'reader_sheet.dart';

/// One navigation level of the reader contents, e.g. headings inside the
/// current article or the book's volume catalog. [build] receives `done`,
/// which closes the host before the selection is applied.
class ReaderContentsLayer {
  const ReaderContentsLayer({
    required this.label,
    required this.build,
    this.action,
  });
  final String label;
  final Widget Function(BuildContext context, VoidCallback done) build;

  /// Optional header control for this layer, such as refreshing a catalog.
  final Widget? action;
}

/// Placement-agnostic contents surface: a sheet on phones, and suitable for a
/// persistent side panel on wide windows.
class ReaderContentsPanel extends StatefulWidget {
  const ReaderContentsPanel({
    super.key,
    required this.layers,
    required this.onDone,
    this.initialLayer = 0,
  });
  final List<ReaderContentsLayer> layers;
  final VoidCallback onDone;
  final int initialLayer;
  @override
  State<ReaderContentsPanel> createState() => _ReaderContentsPanelState();
}

class _ReaderContentsPanelState extends State<ReaderContentsPanel> {
  late int _layer = widget.initialLayer.clamp(0, widget.layers.length - 1);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final layer = widget.layers[_layer];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ShioriSpace.page,
            0,
            ShioriSpace.small,
            ShioriSpace.small,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.layers.length == 1 ? layer.label : l.catalogTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?layer.action,
            ],
          ),
        ),
        if (widget.layers.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShioriSpace.page,
              0,
              ShioriSpace.page,
              ShioriSpace.medium,
            ),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final (index, item) in widget.layers.indexed)
                  ButtonSegment(
                    value: index,
                    label: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {_layer},
              onSelectionChanged: (value) =>
                  setState(() => _layer = value.single),
            ),
          ),
        // Row fills and splashes paint on the nearest Material; give the list
        // its own clipped one so selected rows never show through the header.
        Expanded(
          child: ClipRect(
            child: Material(
              type: MaterialType.transparency,
              child: KeyedSubtree(
                key: ValueKey(_layer),
                child: layer.build(context, widget.onDone),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showReaderContents(
  BuildContext context, {
  required List<ReaderContentsLayer> layers,
  int initialLayer = 0,
}) => showReaderSheet<void>(
  context,
  size: ReaderSheetSize.tall,
  builder: (sheet) => ReaderContentsPanel(
    layers: layers,
    initialLayer: initialLayer,
    onDone: () => Navigator.of(sheet).pop(),
  ),
);

/// Headings recognised inside the current article.
ReaderContentsLayer articleContentsLayer(
  BuildContext context,
  ChapterContent content, {
  required ValueChanged<ReaderPosition> onSelect,
}) {
  final l = AppLocalizations.of(context);
  return ReaderContentsLayer(
    label: l.articleContents,
    build: (context, done) {
      final entries = articleContents(content);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ShioriSpace.page),
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
                      onTap: () {
                        done();
                        onSelect(entries[i].position);
                      },
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

/// The source's volume catalog, read from the reader's own catalog session.
///
/// Loading policy stays with the host: [onRetry] and [onRefresh] decide the
/// read mode (an offline reader must stay cache-only), and a null
/// [onRefresh] hides the refresh control. A failed refresh keeps the loaded
/// catalog usable and shows its reason above it.
///
/// [changes] must notify whenever [catalog] does. It is owned by the host
/// and outlives it safely: a sheet can still be listening while the reader
/// that owns [catalog] is torn down, and a disposed controller may not be
/// unsubscribed from.
ReaderContentsLayer volumeContentsLayer(
  BuildContext context, {
  required CatalogController catalog,
  required Listenable changes,
  required ChapterKey current,
  required ValueChanged<ChapterKey> onSelect,
  required VoidCallback onRetry,
  VoidCallback? onRefresh,
}) {
  final l = AppLocalizations.of(context);
  return ReaderContentsLayer(
    label: l.volumesTitle,
    action: onRefresh == null
        ? null
        : ListenableBuilder(
            listenable: changes,
            builder: (context, _) => IconButton(
              onPressed: catalog.canLoad ? onRefresh : null,
              tooltip: l.detailRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
    build: (context, done) => ListenableBuilder(
      listenable: changes,
      builder: (context, _) {
        final loaded = catalog.loaded;
        final failure = catalog.failure;
        if (loaded == null) {
          if (catalog.loading) return const LoadingView();
          if (failure != null) {
            return FailureView(
              failure: failure,
              onRetry: onRetry,
              retryAvailable: catalog.canLoad,
            );
          }
          return EmptyView(message: l.catalogEmpty);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (catalog.loading) const LinearProgressIndicator(),
            if (failure != null && !catalog.loading)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .3,
                ),
                child: FailureView(
                  key: const ValueKey('catalog-refresh-failure'),
                  failure: failure,
                  onRetry: onRetry,
                  retryAvailable: catalog.canLoad,
                ),
              ),
            if (loaded.isStale)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShioriSpace.page,
                ),
                child: Text(
                  l.catalogStale,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShioriSpace.medium,
                ),
                child: CatalogView(
                  catalog: loaded.value,
                  current: current,
                  onSelect: (key) {
                    done();
                    onSelect(key);
                  },
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Local EPUB / TXT navigation already loaded by the reader.
ReaderContentsLayer localContentsLayer(
  BuildContext context, {
  required ValueListenable<Result<List<LocalNavigationEntry>>?> navigation,
  required ChapterKey current,
  required VoidCallback onRetry,
  required ValueChanged<LocalNavigationEntry> onSelect,
}) => ReaderContentsLayer(
  label: AppLocalizations.of(context).localBookContents,
  build: (context, done) => ValueListenableBuilder(
    valueListenable: navigation,
    builder: (context, result, _) => switch (result) {
      null => const LoadingView(),
      Failure(:final failure) => FailureView(
        failure: failure,
        onRetry: onRetry,
      ),
      Success(:final value) => LocalNavigationView(
        entries: value,
        current: current,
        onSelect: (entry) {
          done();
          onSelect(entry);
        },
      ),
    },
  ),
);
