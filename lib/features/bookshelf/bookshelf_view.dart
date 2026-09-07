import 'package:flutter/material.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/source_image.dart';
import '../../shared/widgets/state_views.dart';
import 'library_controller.dart';

class BookshelfView extends StatefulWidget {
  const BookshelfView({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onSearch,
    this.images,
  });
  final LibraryController controller;
  final ValueChanged<NovelKey> onOpen;
  final VoidCallback onSearch;
  final ImageRepository? images;
  @override
  State<BookshelfView> createState() => _BookshelfViewState();
}

class _BookshelfViewState extends State<BookshelfView> {
  bool _grid = true;
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final strings = AppLocalizations.of(context);
    final books = controller.sorted;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: strings.shelfLayout,
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ),
        if (controller.shelfFailure != null)
          Flexible(child: FailureView(failure: controller.shelfFailure!)),
        if (controller.writeFailure != null)
          Flexible(child: FailureView(failure: controller.writeFailure!)),
        if (controller.removed != null)
          TextButton(
            onPressed: controller.writing ? null : controller.undo,
            child: Text(strings.shelfUndo),
          ),
        Expanded(
          flex: 4,
          child: !controller.shelfReady
              ? const LoadingView()
              : books.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(strings.shelfEmpty),
                        TextButton(
                          onPressed: widget.onSearch,
                          child: Text(strings.searchTitle),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, bounds) {
                    Widget item(int index) {
                      final book = books[index].snapshot;
                      final cover = SizedBox(
                        width: 72,
                        height: 108,
                        child: book.cover != null && widget.images != null
                            ? SourceImage(
                                media: book.cover!,
                                repository: widget.images!,
                                semanticLabel: strings.detailCover,
                              )
                            : const Center(child: Icon(Icons.bookmark_outline)),
                      );
                      final remove = IconButton(
                        tooltip: strings.detailRemoveShelf,
                        onPressed: controller.writing
                            ? null
                            : () => controller.remove(book.key),
                        icon: const Icon(Icons.remove_circle_outline),
                      );
                      if (!_grid) {
                        return ListTile(
                          key: ValueKey(book.key),
                          title: Text(book.title),
                          leading: SizedBox(
                            width: 36,
                            height: 54,
                            child: cover,
                          ),
                          trailing: remove,
                          onTap: () => widget.onOpen(book.key),
                        );
                      }
                      return Column(
                        key: ValueKey(book.key),
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => widget.onOpen(book.key),
                              child: Semantics(
                                button: true,
                                label: book.title,
                                child: SizedBox.expand(child: cover),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => widget.onOpen(book.key),
                            child: Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          remove,
                        ],
                      );
                    }

                    if (!_grid) {
                      return ListView.builder(
                        key: const PageStorageKey('shelf-list'),
                        itemCount: books.length,
                        itemBuilder: (_, i) => item(i),
                      );
                    }
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final columns =
                        (bounds.maxWidth / (110 * scale.clamp(1, 1.5)))
                            .floor()
                            .clamp(2, 6);
                    return GridView.builder(
                      key: const PageStorageKey('shelf-grid'),
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 160 + 48 * scale,
                      ),
                      itemCount: books.length,
                      itemBuilder: (_, i) => item(i),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
