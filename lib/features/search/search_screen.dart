import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/desktop_content_frame.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/book_cover.dart';
import 'search_controller.dart';

/// The shell can show search without constructing a source or a controller.
class SearchUnavailable extends StatelessWidget {
  const SearchUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final body = EmptyView(message: strings.noSources);
    if (!DesktopLayoutScope.useDesktopPage(context)) {
      return AppScaffold(title: strings.searchTitle, body: body);
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DesktopContentFrame(
              maxWidth: ShioriLayout.shelfList,
              child: DesktopPageToolbar(
                title: strings.searchTitle,
                leading: ModalRoute.of(context)?.impliesAppBarDismissal == true
                    ? const BackButton()
                    : null,
              ),
            ),
            Expanded(
              child: DesktopContentFrame(
                maxWidth: ShioriLayout.shelfList,
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The route owns its controller; the composition root owns the repository.
class SearchScreen extends StatelessWidget {
  const SearchScreen({
    super.key,
    required this.repository,
    required this.sourceId,
    required this.routes,
    this.supportsPaging = true,
    this.sourceName,
    this.environmentLabel,
    this.images,
  });
  final NovelRepository repository;
  final SourceId sourceId;
  final AppRoutes routes;
  final bool supportsPaging;
  final String? sourceName, environmentLabel;
  final ImageRepository? images;

  @override
  Widget build(BuildContext context) => ControllerScope<SearchController>(
    create: () => SearchController(
      repository: repository,
      sourceId: sourceId,
      supportsPaging: supportsPaging,
    ),
    builder: (context, controller) => _SearchBody(
      controller: controller,
      routes: routes,
      sourceName: sourceName,
      environmentLabel: environmentLabel,
      images: images,
    ),
  );
}

class _SearchBody extends StatefulWidget {
  const _SearchBody({
    required this.controller,
    required this.routes,
    this.sourceName,
    this.environmentLabel,
    this.images,
  });
  final SearchController controller;
  final AppRoutes routes;
  final String? sourceName, environmentLabel;
  final ImageRepository? images;

  @override
  State<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<_SearchBody> {
  final _text = TextEditingController();
  final _inputFocus = FocusNode(debugLabel: 'search-input');
  final _scroll = ScrollController();

  @override
  void dispose() {
    _text.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final sourceName = widget.sourceName;
    final environmentLabel = widget.environmentLabel;
    final desktop = DesktopLayoutScope.useDesktopPage(context);
    final strings = AppLocalizations.of(context);
    final state = controller.state;
    final pointerFirst = ShioriCapabilities.of(context).pointerFirst;
    final gutter = desktop
        ? ShioriLayout.gutter(DesktopLayoutScope.widthOf(context))
        : 0.0;
    void submit() {
      if (!desktop) FocusScope.of(context).unfocus();
      controller.submit();
    }

    final slivers = <Widget>[
      SliverPadding(
        padding: EdgeInsets.symmetric(
          horizontal: desktop ? 0 : ShioriSpace.page,
          vertical: ShioriSpace.page,
        ),
        sliver: SliverToBoxAdapter(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: desktop ? ShioriLayout.page : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sourceName != null || environmentLabel != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(ShioriShape.tag),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            environmentLabel ??
                                sourceName ??
                                strings.onlineSource,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ShioriSpace.medium),
                  ],
                  _SearchInput(
                    text: _text,
                    focusNode: _inputFocus,
                    keepFocus: desktop,
                    onChanged: controller.edit,
                    onSubmit: submit,
                    enabled:
                        state.draftKeyword.trim().isNotEmpty &&
                        state.status != SearchStatus.loading &&
                        !state.loadingMore,
                  ),
                  if (state.submittedQuery != null &&
                      state.status != SearchStatus.idle) ...[
                    const SizedBox(height: ShioriSpace.item),
                    Text(
                      strings.searchResultsFor(state.submittedQuery!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (state.needsSubmission && state.items.isNotEmpty)
                    Text(strings.searchDraftNotice),
                ],
              ),
            ),
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
              images: widget.images,
              desktop: desktop,
              onTap: () {
                if (!desktop) FocusScope.of(context).unfocus();
                widget.routes.open(context, NovelDestination(book.key));
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
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
          ),
        ),
      ] else
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 32),
            child: switch (state.status) {
              SearchStatus.loading => const LoadingView(),
              SearchStatus.error => FailureView(
                failure: state.failure!,
                onRetry: submit,
              ),
              SearchStatus.empty => EmptyView(message: strings.searchNoResults),
              _ => EmptyView(message: strings.searchInitial),
            },
          ),
        ),
    ];
    final content = CustomScrollView(
      // Touch layouts inherit the route primary (including iOS status-bar
      // scroll-to-top). Pointer layouts keep one owner at every window width.
      controller: pointerFirst ? _scroll : null,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // Keep the pointer viewport across the Workspace for edge scrollbar and
      // wheel access. Persistent sliver wrappers center only the content, also
      // preserving input and list elements when crossing the desktop breakpoint.
      slivers: pointerFirst
          ? [
              for (final sliver in slivers)
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final geometry = desktopContentGeometry(
                      availableWidth: constraints.crossAxisExtent,
                      gutter: gutter,
                      maxWidth: desktop
                          ? ShioriLayout.shelfList
                          : ShioriLayout.page,
                    );
                    return SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: geometry.inset),
                      sliver: sliver,
                    );
                  },
                ),
            ]
          : slivers,
    );
    if (pointerFirst) {
      return Scaffold(
        appBar: desktop ? null : AppBar(title: Text(strings.searchTitle)),
        body: SafeArea(
          child: Column(
            children: [
              if (desktop)
                DesktopContentFrame(
                  maxWidth: ShioriLayout.shelfList,
                  child: DesktopPageToolbar(
                    title: strings.searchTitle,
                    leading:
                        ModalRoute.of(context)?.impliesAppBarDismissal == true
                        ? const BackButton()
                        : null,
                  ),
                )
              else
                const SizedBox.shrink(),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }
    return AppScaffold(
      title: strings.searchTitle,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ShioriLayout.page),
          child: content,
        ),
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.onChanged,
    required this.onSubmit,
    required this.enabled,
    required this.text,
    required this.focusNode,
    required this.keepFocus,
  });
  final TextEditingController text;
  final FocusNode focusNode;
  final bool keepFocus;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      final enter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      // Let the IME consume Enter while composing CJK candidates.
      if (!enter || !text.value.composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) onSubmit();
      return KeyEventResult.handled;
    },
    child: TextField(
      key: const ValueKey('search-input'),
      // Keep the keyword prompt available to assistive technology after entry.
      controller: text,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onEditingComplete: keepFocus ? () {} : null,
      onSubmitted: (_) {
        if (text.value.composing.isCollapsed) onSubmit();
      },
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).searchKeyword,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelText: AppLocalizations.of(context).searchKeyword,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShioriShape.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShioriShape.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShioriShape.control),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1,
          ),
        ),
        prefixIcon: const Icon(Icons.search, size: 22),
        suffixIcon: Padding(
          padding: const EdgeInsets.all(ShioriSpace.tight),
          child: TextButton(
            key: const ValueKey('search-submit'),

            onPressed: enabled ? onSubmit : null,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: ShioriSpace.item),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShioriShape.control),
              ),
            ),
            child: Text(AppLocalizations.of(context).searchTitle),
          ),
        ),
      ),
    ),
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.book,
    required this.onTap,
    this.images,
    this.desktop = false,
  });
  final bool desktop;
  final ImageRepository? images;
  final NovelSummary book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    onTap: onTap,
    label: [book.title, ...book.authors].join(', '),
    excludeSemantics: true,
    child: Padding(
      padding: EdgeInsets.fromLTRB(desktop ? 0 : 20, 0, desktop ? 0 : 20, 12),
      child: Material(
        color: desktop
            ? Theme.of(context).scaffoldBackgroundColor
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(ShioriShape.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: desktop
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .04)
              : null,
          focusColor: desktop
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
              : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: desktop ? 0 : 14,
              vertical: 14,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 68,
                  child: BookCover(book: book, images: images),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (book.authors.isNotEmpty) ...[
                        const SizedBox(height: ShioriSpace.small),
                        Text(
                          book.authors.join(', '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
