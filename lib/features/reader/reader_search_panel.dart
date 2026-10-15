import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reader_search_controller.dart';

class ReaderSearchPanel extends StatefulWidget {
  const ReaderSearchPanel({
    super.key,
    required this.controller,
    required this.onClose,
    required this.accepts,
    required this.closeForNavigation,
    required this.titleFor,
  });
  final ReaderSearchController controller;
  final VoidCallback onClose;
  final bool Function() accepts;
  final Future<void> Function() closeForNavigation;
  final Future<String?> Function(LocalSearchHit, CancellationToken) titleFor;
  @override
  State<ReaderSearchPanel> createState() => _ReaderSearchPanelState();
}

class _ReaderSearchPanelState extends State<ReaderSearchPanel> {
  late final _input = TextEditingController(text: widget.controller.draft);
  final _focus = FocusNode(debugLabel: 'reader-search-input');
  final _scope = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final _scroll = ScrollController();
  final _titles = <(ChapterKey, int), Future<String?>>{};
  final _titleRequest = CancellationSource();
  double _extent = 132;
  int _generation = -1, _fill = 0;
  bool _positioned = false;
  ReaderSearchController get state => widget.controller;
  @override
  void initState() {
    super.initState();
    state.addListener(_changed);
    state.focusRequest.addListener(_refocus);
    _scroll.addListener(_scrolled);
  }

  void _refocus() {
    if (mounted) _focus.requestFocus();
  }

  void _changed() {
    if (!mounted) return;
    if (_generation != state.generation) {
      _generation = state.generation;
      _positioned = false;
      _fill = 0;
    }
    setState(() {});
    _queueVisible();
  }

  void _queueVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          state.loading ||
          state.paused ||
          state.error != null) {
        return;
      }
      final first = (_scroll.offset / _extent).floor().clamp(
        0,
        state.loadedCount,
      );
      if (first < state.loadedCount && state.hitAt(first) == null) {
        unawaited(state.loadAt(first));
        return;
      }
      if (_scroll.position.extentAfter < _extent * 2 && state.canContinue) {
        if (_scroll.position.maxScrollExtent == 0 && _fill++ >= 3) return;
        unawaited(state.loadAt(state.loadedCount));
      }
    });
  }

  void _scrolled() {
    state.scrollPosition = _scroll.offset / _extent;
    _queueVisible();
  }

  @override
  void dispose() {
    state.removeListener(_changed);
    state.focusRequest.removeListener(_refocus);
    _titleRequest.cancel();
    _focus.dispose();
    _scope.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<String?> _title(LocalSearchHit hit) {
    final key = (hit.chapter, hit.blockIndex);
    if (_titles.length >= 64 && !_titles.containsKey(key)) {
      _titles.remove(_titles.keys.first);
    }
    return _titles.putIfAbsent(
      key,
      () => widget.titleFor(hit, _titleRequest.token),
    );
  }

  void _submit() {
    _fill = 0;
    unawaited(state.submit(_input.text));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), theme = Theme.of(context);
    _extent = 132 * MediaQuery.textScalerOf(context).scale(14) / 14;
    if (!_positioned) {
      _positioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            (state.scrollPosition * _extent).clamp(
              0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    }
    String status = state.loading
        ? l.readerSearchLoading
        : state.error == ReaderSearchError.tooLong
        ? l.readerSearchTooLong
        : state.error == ReaderSearchError.invalidQuery
        ? l.readerSearchInvalid
        : state.error == ReaderSearchError.expired
        ? l.readerSearchExpired
        : state.error != null
        ? l.readerSearchFailed
        : state.paused
        ? l.readerSearchPaused
        : state.submitted.isEmpty
        ? l.readerSearchHint
        : state.totalMatches == 0
        ? l.readerSearchEmpty
        : state.totalMatches != null
        ? l.readerSearchTotal(state.totalMatches!)
        : l.readerSearchFound(state.loadedCount);
    return FocusScope(
      node: _scope,
      autofocus: true,
      child: Shortcuts(
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              const ActivateIntent(),
        },
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _refocus();
                return null;
              },
            ),
          },
          child: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                if (!_input.value.composing.isValid ||
                    _input.value.composing.isCollapsed) {
                  widget.onClose();
                }
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ShioriSpace.page,
                      ShioriSpace.small,
                      ShioriSpace.small,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.readerSearchBook,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShioriSpace.page,
                      vertical: ShioriSpace.small,
                    ),
                    child: TextField(
                      key: const ValueKey('reader-search-input'),
                      controller: _input,
                      focusNode: _focus,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submit(),
                      onChanged: state.edit,
                      decoration: InputDecoration(
                        hintText: l.readerSearchHint,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_input.text.isNotEmpty)
                              IconButton(
                                tooltip: l.readerSearchClear,
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _input.clear();
                                  unawaited(state.clear());
                                  _refocus();
                                },
                              ),
                            IconButton(
                              tooltip: l.readerSearchSubmit,
                              onPressed: _submit,
                              icon: const Icon(Icons.search),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShioriSpace.page,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        status,
                        key: const ValueKey('reader-search-status'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  if (state.draft.trim() != state.submitted &&
                      state.submitted.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ShioriSpace.page,
                      ),
                      child: Text(
                        l.readerSearchDraft(state.submitted),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      key: const ValueKey('reader-search-results'),
                      controller: _scroll,
                      itemExtent: _extent,
                      itemCount: state.loadedCount + 1,
                      itemBuilder: (context, index) {
                        if (index == state.loadedCount) {
                          return Center(
                            child: state.loading
                                ? const CircularProgressIndicator()
                                : state.canContinue || state.error != null
                                ? TextButton(
                                    onPressed: () => state.error != null
                                        ? unawaited(
                                            state.submit(state.submitted),
                                          )
                                        : unawaited(
                                            state.loadAt(
                                              state.loadedCount,
                                              resume: true,
                                            ),
                                          ),
                                    child: Text(
                                      state.paused
                                          ? l.readerSearchResume
                                          : state.error != null
                                          ? l.readerSearchRetry
                                          : l.loadMoreAction,
                                    ),
                                  )
                                : state.submitted.isNotEmpty
                                ? Text(
                                    l.readerSearchEnd,
                                    style: theme.textTheme.bodySmall,
                                  )
                                : const SizedBox.shrink(),
                          );
                        }
                        final hit = state.hitAt(index);
                        if (hit == null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !state.paused) {
                              unawaited(state.loadAt(index));
                            }
                          });
                          return Center(
                            child: TextButton(
                              onPressed: () =>
                                  unawaited(state.loadAt(index, resume: true)),
                              child: Text(l.readerSearchRebuilding),
                            ),
                          );
                        }
                        return Semantics(
                          selected: state.selectedIndex == index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ShioriSpace.small,
                              vertical: ShioriSpace.tight,
                            ),
                            child: Material(
                              color: state.selectedIndex == index
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: .08,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                ShioriShape.control,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  ShioriShape.control,
                                ),
                                onTap: state.navigating
                                    ? null
                                    : () => unawaited(
                                        state.select(
                                          index,
                                          accepts: widget.accepts,
                                          closePanel: widget.closeForNavigation,
                                        ),
                                      ),
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                    ShioriSpace.medium,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      FutureBuilder<String?>(
                                        future: _title(hit),
                                        builder: (context, title) => Text(
                                          title.data ?? l.readerLinkElsewhere,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ),
                                      if (hit is LocalSearchFootnoteHit)
                                        Text(
                                          l.readerSearchFootnote,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              TextSpan(
                                                text: hit.snippet.before,
                                              ),
                                              TextSpan(
                                                text: hit.snippet.match,
                                                style: TextStyle(
                                                  backgroundColor: theme
                                                      .colorScheme
                                                      .primaryContainer,
                                                  color: theme
                                                      .colorScheme
                                                      .onPrimaryContainer,
                                                ),
                                              ),
                                              TextSpan(text: hit.snippet.after),
                                            ],
                                          ),
                                          maxLines:
                                              hit is LocalSearchFootnoteHit
                                              ? 2
                                              : 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
}
