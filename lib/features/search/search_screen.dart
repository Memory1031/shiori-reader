import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'search_controller.dart';

/// The route owns its controller; the composition root owns the repository.
class SearchScreen extends StatelessWidget {
  const SearchScreen({
    super.key,
    required this.repository,
    required this.sourceId,
    required this.routes,
    this.supportsPaging = true,
  });
  final NovelRepository repository;
  final SourceId sourceId;
  final AppRoutes routes;
  final bool supportsPaging;

  @override
  Widget build(BuildContext context) => ControllerScope<SearchController>(
    create: () => SearchController(
      repository: repository,
      sourceId: sourceId,
      supportsPaging: supportsPaging,
    ),
    builder: (context, controller) =>
        _SearchBody(controller: controller, routes: routes),
  );
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({required this.controller, required this.routes});
  final SearchController controller;
  final AppRoutes routes;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final state = controller.state;
    void submit() {
      FocusScope.of(context).unfocus();
      controller.submit();
    }

    return AppScaffold(
      title: strings.searchTitle,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(ShioriSpace.page),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SearchInput(
                        onChanged: controller.edit,
                        onSubmit: submit,
                      ),
                      const SizedBox(height: ShioriSpace.medium),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: const ValueKey('search-submit'),
                          onPressed:
                              state.draftKeyword.trim().isEmpty ||
                                  state.status == SearchStatus.loading ||
                                  state.loadingMore
                              ? null
                              : submit,
                          child: Text(strings.searchTitle),
                        ),
                      ),
                      if (state.submittedQuery != null &&
                          state.status != SearchStatus.idle) ...[
                        const SizedBox(height: ShioriSpace.item),
                        Text(strings.searchResultsFor(state.submittedQuery!)),
                      ],
                      if (state.needsSubmission && state.items.isNotEmpty)
                        Text(strings.searchDraftNotice),
                    ],
                  ),
                ),
              ),
              if (state.status == SearchStatus.ready) ...[
                SliverList.builder(
                  itemCount: state.items.length,
                  itemBuilder: (context, index) {
                    final book = state.items[index];
                    return _ResultRow(
                      key: ValueKey(book.key),
                      book: book,
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        routes.open(context, NovelDestination(book.key));
                      },
                    );
                  },
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(ShioriSpace.page),
                    child: state.loadingMore
                        ? const LoadingView()
                        : state.paginationFailure != null
                        ? FailureView(
                            failure: state.paginationFailure!,
                            onRetry: controller.canLoadMore
                                ? controller.loadMore
                                : null,
                          )
                        : state.needsSubmission
                        ? const SizedBox.shrink()
                        : controller.canLoadMore
                        ? Center(
                            child: OutlinedButton(
                              key: const ValueKey('search-more'),
                              onPressed: controller.loadMore,
                              child: Text(strings.loadMoreAction),
                            ),
                          )
                        : Text(
                            strings.searchNoMore,
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ] else
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: switch (state.status) {
                    SearchStatus.loading => const LoadingView(),
                    SearchStatus.error => FailureView(
                      failure: state.failure!,
                      onRetry: submit,
                    ),
                    SearchStatus.empty => EmptyView(
                      message: strings.searchNoResults,
                    ),
                    _ => EmptyView(message: strings.searchInitial),
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchInput extends StatefulWidget {
  const _SearchInput({required this.onChanged, required this.onSubmit});
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  @override
  State<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<_SearchInput> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      final enter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      // Let the IME consume Enter while composing CJK candidates.
      if (!enter || !_text.value.composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) widget.onSubmit();
      return KeyEventResult.handled;
    },
    child: TextField(
      key: const ValueKey('search-input'),
      controller: _text,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmit(),
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).searchKeyword,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.book, required this.onTap});
  final NovelSummary book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    onTap: onTap,
    label: [book.title, ...book.authors].join(', '),
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShioriSpace.page,
          vertical: ShioriSpace.medium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stable 2:3 placeholder. Media loading remains independently owned.
            Container(
              width: 64,
              height: 64 / ShioriShape.coverRatio,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(ShioriShape.cover),
              ),
              child: const Icon(Icons.bookmark_outline),
            ),
            const SizedBox(width: ShioriSpace.item),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (book.authors.isNotEmpty) ...[
                    const SizedBox(height: ShioriSpace.small),
                    Text(book.authors.join(', ')),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
