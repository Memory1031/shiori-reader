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
  final _scroll = ScrollController(keepScrollOffset: false);
  final _viewport = GlobalKey();
  final _rows = <int, GlobalKey>{};
  final _placeholders = <int>{};
  Key _center = UniqueKey(), _listIdentity = UniqueKey();
  (double, TextScaler, TextStyle?)? _metrics;
  int _baseIndex = 0, _lastVisible = 0;
  bool _restoring = false;
  final _titles = <(ChapterKey, int), Future<String?>>{};
  final _titleRequest = CancellationSource();
  int _generation = -1, _fill = 0;
  bool _positioned = false;
  ReaderSearchController get state => widget.controller;
  @override
  void initState() {
    super.initState();
    _generation = state.generation;
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
      _fill = 0;
      _positioned = false;
      _titles.clear();
    } else {
      final first = _saveAnchor()?.$1;
      // Only replacing visible placeholders can change existing row heights.
      if (first != null &&
          _rows.keys.any(
            (index) =>
                index >= first &&
                index <= _lastVisible &&
                _placeholders.contains(index) != (state.hitAt(index) == null),
          )) {
        _positioned = false;
      }
    }
    setState(() {});
    _queueVisible();
  }

  void _queueVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _rows.removeWhere((_, key) => key.currentContext == null);
      _placeholders.removeWhere((index) => !_rows.containsKey(index));
      final first = _saveAnchor()?.$1 ?? _baseIndex;
      if (state.loading || state.paused || state.error != null) return;
      for (var index = first; index <= _lastVisible; index++) {
        if (index < state.loadedCount && state.hitAt(index) == null) {
          unawaited(state.loadAt(index));
          return;
        }
      }
      if (_scroll.position.extentAfter <
              _scroll.position.viewportDimension / 2 &&
          state.canContinue) {
        if (_scroll.position.maxScrollExtent == 0 && _fill++ >= 3) return;
        unawaited(state.loadAt(state.loadedCount));
      }
    });
  }

  (int, double)? _saveAnchor() {
    if (_restoring) return null;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    (int, double)? anchor;
    _lastVisible = 0;
    for (final entry in _rows.entries) {
      if (entry.key >= state.loadedCount) continue;
      final row = entry.value.currentContext?.findRenderObject();
      if (row is! RenderBox ||
          !row.attached ||
          !row.hasSize ||
          row.size.height == 0) {
        continue;
      }
      final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top >= viewport.size.height || top + row.size.height <= 0) continue;
      if (entry.key > _lastVisible) _lastVisible = entry.key;
      if (anchor == null || entry.key < anchor.$1) {
        anchor = (entry.key, (-top / row.size.height).clamp(0, .999999));
      }
    }
    if (anchor != null) state.scrollPosition = anchor.$1 + anchor.$2;
    return anchor;
  }

  void _scrolled() {
    _queueVisible();
  }

  Widget _results(BuildContext context, BoxConstraints constraints) {
    final metrics = (
      constraints.maxWidth,
      MediaQuery.textScalerOf(context),
      Theme.of(context).textTheme.bodyMedium,
    );
    if (_metrics != metrics) {
      if (_metrics != null) _saveAnchor();
      _metrics = metrics;
      _positioned = false;
    }
    if (!_positioned) {
      _positioned = true;
      _baseIndex = state.scrollPosition.floor().clamp(0, state.loadedCount);
      final fraction = state.scrollPosition - _baseIndex;
      _center = UniqueKey();
      _listIdentity = UniqueKey();
      _rows.clear();
      _placeholders.clear();
      _restoring = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final row = _rows[_baseIndex]?.currentContext?.findRenderObject();
        if (_scroll.hasClients && row is RenderBox && row.hasSize) {
          _scroll.jumpTo(row.size.height * fraction);
        }
        _restoring = false;
        _queueVisible();
      });
    }
    Widget row(int index) {
      if (index < state.loadedCount && state.hitAt(index) == null) {
        _placeholders.add(index);
      } else {
        _placeholders.remove(index);
      }
      return KeyedSubtree(
        key: _rows.putIfAbsent(index, GlobalKey.new),
        child: _result(context, index),
      );
    }

    // A centered pair of native slivers restores an absolute result anchor
    // without retaining heights or snippets for every previously visited row.
    return KeyedSubtree(
      key: _listIdentity,
      child: CustomScrollView(
        key: const ValueKey('reader-search-results'),
        controller: _scroll,
        center: _center,
        semanticChildCount: state.loadedCount,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, index) => row(_baseIndex - index - 1),
              childCount: _baseIndex,
              addAutomaticKeepAlives: false,
              semanticIndexCallback: (_, index) => _baseIndex - index - 1,
            ),
          ),
          SliverList(
            key: _center,
            delegate: SliverChildBuilderDelegate(
              (_, index) => row(_baseIndex + index),
              childCount: state.loadedCount - _baseIndex + 1,
              addAutomaticKeepAlives: false,
              semanticIndexCallback: (_, index) =>
                  _baseIndex + index < state.loadedCount
                  ? _baseIndex + index
                  : null,
            ),
          ),
        ],
      ),
    );
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
                    child: SizedBox(
                      key: _viewport,
                      child: LayoutBuilder(builder: _results),
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

  Widget _result(BuildContext context, int index) {
    final l = AppLocalizations.of(context), theme = Theme.of(context);
    if (index == state.loadedCount) {
      return SizedBox(
        height: 64,
        child: Center(
          child: state.loading
              ? const CircularProgressIndicator()
              : state.canContinue || state.error != null
              ? TextButton(
                  onPressed: () => state.error != null
                      ? unawaited(state.submit(state.submitted))
                      : unawaited(
                          state.loadAt(state.loadedCount, resume: true),
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
              ? Text(l.readerSearchEnd, style: theme.textTheme.bodySmall)
              : const SizedBox.shrink(),
        ),
      );
    }
    final hit = state.hitAt(index);
    if (hit == null) {
      return SizedBox(
        height: 72,
        child: Center(
          child: TextButton(
            onPressed: () => unawaited(state.loadAt(index, resume: true)),
            child: Text(l.readerSearchRebuilding),
          ),
        ),
      );
    }
    return Semantics(
      key: ValueKey('reader-search-result-$index'),
      selected: state.selectedIndex == index,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShioriSpace.small,
          vertical: ShioriSpace.tight,
        ),
        child: Material(
          color: state.selectedIndex == index
              ? theme.colorScheme.primary.withValues(alpha: .08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(ShioriShape.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(ShioriShape.control),
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
              padding: const EdgeInsets.all(ShioriSpace.medium),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: ShioriSpace.tight),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: hit.snippet.before),
                        TextSpan(
                          text: hit.snippet.match,
                          style: TextStyle(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        TextSpan(text: hit.snippet.after),
                      ],
                    ),
                    maxLines: hit is LocalSearchFootnoteHit ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
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
