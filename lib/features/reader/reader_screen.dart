import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import '../../app/app_exit.dart';
import '../../app/window_caption.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/local_navigation_title.dart';
import '../../shared/widgets/shiori_menu.dart';
import 'reader_controller.dart';
import 'reader_completion_page.dart';
import 'reader_completion_transition.dart';
import 'reader_preferences.dart';
import 'reader_loading_page.dart';
import 'native_reader_settings_adapter.dart';
import 'reader_theme.dart';
import 'reading_progress_format.dart';
export 'reader_actions.dart' show ReaderActions;

import 'reader_actions.dart';
import 'reader_chrome.dart';
import 'reader_commands.dart';
import 'reader_contents.dart';
import 'article_contents.dart';
import 'reader_contents_session.dart';
import 'reader_panel.dart';
import 'reader_progress_panel.dart';
import 'reader_sheet.dart';
import '../../shared/widgets/shiori_sheet.dart' show shioriSheetRoute;
import 'reader_search_controller.dart';
import 'reader_search_panel.dart';
import 'reader_search_highlight.dart';
import 'reader_toolbars.dart';
import 'settings_panel.dart';
import 'reader_margin.dart';
import 'reader_image.dart';
import 'reader_audio.dart';
import 'reader_image_preview.dart';
import 'reader_linked_text.dart';
import 'reader_embedded_fonts.dart';
import 'epub_layout_page.dart';
import '../../domain/local_chapter_progress.dart';
import 'reader_logical_progress.dart';
import 'viewport/paged_reader_viewport.dart';
import 'viewport/page_turn.dart';
import 'viewport/reader_box.dart';

typedef _ProgressText = ({String? percent, bool document});
typedef _ProgressEndpoint = ({Object scope, double fraction, bool document});

/// The body never observes per-frame progress or Chrome visibility changes.
/// Preferences are injected; the composition root may share them across readers.
class ReaderContentView extends StatefulWidget {
  const ReaderContentView({
    super.key,
    required this.content,
    this.runningTitle,
    this.chapterTitle,
    this.navigationEntry,
    this.logicalProgress,
    this.onReady,
    this.onLayoutInvalidated,
    this.onPanelChanged,
    this.onCancelChapter,
    this.onBoundaryDrag,
    this.onEdges,
    this.crossChapterTurning = false,
    this.preferences,
    this.preferencesReady,
    this.onLoadFailure,
    this.onPageAppearance,
    this.images,
    this.audioFactory,
    this.settings,
    this.session,
    this.initialPosition,
    this.actions = const ReaderActions(),
    this.search,
    this.searchEnabled = true,
    this.searchTitle,
    this.onSearchOpen,
    this.articleContents = true,
    this.contentsSession,
    this.onPosition,
    this.completion,
    this.completionTarget,
    this.completionBasis,
    this.onCompletionTurn,
    this.bookTitle,
    this.viewportController,
    this.returnToOrigin = false,
    this.chrome,
    this.quickReturn,
    this.active = true,
    this.appearanceActive,
  });
  final ImageRepository? images;
  final AudioPlaybackFactory? audioFactory;
  final ChapterContent content;
  final String? runningTitle;
  final String? chapterTitle;
  final LocalNavigationEntry? navigationEntry;
  final ReaderLogicalProgress? logicalProgress;
  final VoidCallback? onReady,
      onLoadFailure,
      onLayoutInvalidated,
      onCancelChapter;
  final BoundaryPageDrag? Function(int direction, double grip)? onBoundaryDrag;
  final void Function(bool first, bool last)? onEdges;
  final bool crossChapterTurning;
  final ValueChanged<ReaderPanelHandle<Object?>?>? onPanelChanged;
  final ReaderPreferences? preferences;
  final Future<void>? preferencesReady;

  /// Paper colour and page-turn style, so the host can match chapter and
  /// completion transitions to the page.
  final void Function(Color paper, PageTurnStyle turn)? onPageAppearance;
  final ReaderController? session;
  final ReaderPosition? initialPosition;
  final SettingsStore? settings;
  final ReaderActions actions;
  final ReaderSearchController? search;
  final VoidCallback? onSearchOpen;
  final bool searchEnabled;
  final Future<String?> Function(LocalSearchHit, CancellationToken)?
  searchTitle;

  /// Whether headings recognised inside the article form their own layer.
  final bool articleContents;
  final ReaderContentsSession? contentsSession;
  final ValueChanged<ReaderPosition>? onPosition;
  final BookTerminalState? completion, completionTarget;
  final Object? completionBasis;
  final String? bookTitle;
  final ValueChanged<({VoidCallback cancel, VoidCallback invalidate})?>?
  onCompletionTurn;
  final PagedReaderController? viewportController;
  final bool returnToOrigin;

  /// Toolbar visibility, owned by the caller when it must outlive this view
  /// (e.g. so the screen can close the toolbars on back).
  final ValueNotifier<bool>? chrome;
  final ValueListenable<bool>? quickReturn;

  /// Whether this page takes commands: false for a chapter still turning in
  /// and while the host is changing chapters or leaving. It only gates input
  /// and new panels; the page still lays out, restores and reports ready.
  final bool active;

  /// The host's currently displayed session, independent of temporary input
  /// locks while saving or preparing another chapter. Pending pages are false.
  /// Standalone readers default to [active].
  final bool? appearanceActive;
  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

class _ReaderContentViewState extends State<ReaderContentView>
    with WidgetsBindingObserver {
  AppExitScopeState? _exitOwner;
  void Function()? _removeExit;
  Size? _progressWindowSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    if (_progressWindowSize != null && _progressWindowSize != size) {
      _invalidateProgressPreview();
    }
    _progressWindowSize = size;
    final owner = AppExitScope.of(context);
    if (owner != _exitOwner) {
      _removeExit?.call();
      _exitOwner = owner;
      _removeExit = owner?.register(_saveForExit);
    }
  }

  Future<bool> _saveForExit() async {
    if (!mounted) return true;
    _invalidateProgressPreview();
    widget.onCancelChapter?.call();
    _dragSurface.currentState?.cancel();
    _cancelCompletion(immediate: true);
    await _preferences.flush();
    final progressSaved = await widget.session?.saveForExit() ?? true;
    final saved = !_preferences.unsaved && progressSaved;
    if (mounted && !saved) {
      _chrome.value = true;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            progressSaved
                ? l.readerSettingsFailure
                : widget.session?.progressStatus == ReaderProgressStatus.paused
                ? l.readerRestoreReadFailed
                : l.readerProgressUnsaved,
          ),
          action:
              _preferences.unsaved || widget.session?.canRetryProgress == true
              ? SnackBarAction(
                  label: l.retryAction,
                  onPressed: () {
                    _preferences.retry();
                    unawaited(widget.session?.retryProgress());
                  },
                )
              : null,
        ),
      );
    }
    return saved;
  }

  late final ReaderPreferences _preferences;
  ReaderSettings _settings = ReaderSettings();
  final _paperTurn = ValueNotifier<PageTurnFrame>(PageTurnFrame.rest);
  final _dragSurface = GlobalKey<PagedReaderDragSurfaceState>();
  bool _completionTurning = false;
  final _completionTransition = GlobalKey<ReaderCompletionTransitionState>();
  void _cancelCompletion({bool immediate = false}) {
    unawaited(_completionTransition.currentState?.cancel(immediate: immediate));
  }

  void _completionTurnChanged(bool value) {
    if (!mounted || _completionTurning == value) return;
    if (value) _audio.stop();
    setState(() => _completionTurning = value);
    widget.onCompletionTurn?.call(
      value
          ? (
              cancel: () => _cancelCompletion(),
              invalidate: () => _cancelCompletion(immediate: true),
            )
          : null,
    );
    if (!value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applySizes();
      });
    }
  }

  bool _canCompletionTurn(bool entering) =>
      mounted &&
      widget.active &&
      _routeCurrent &&
      widget.session?.isClosed != true &&
      !_dragging &&
      !widget.crossChapterTurning &&
      (!_usesPresentation ? !_paged.isRestoring && _lastPageVisible : true) &&
      (entering
          ? widget.completion == null && _actions.bookEnd != null
          : widget.completion != null && _actions.completionPrevious != null);

  bool _commitCompletion(bool entering) {
    if (!_canCompletionTurn(entering)) return false;
    if (entering) {
      if (!_actions.bookEnd!.call()) return false;
      if (!_usesPresentation) _paged.anchorAtEnd();
    } else {
      _actions.completionPrevious!.call();
    }
    _chrome.value = false;
    return true;
  }

  BoundaryPageDrag? _boundaryDrag(int direction, double grip) {
    if (direction > 0 &&
        _actions.nextChapter == null &&
        _actions.bookEnd != null) {
      return _completionTransition.currentState?.begin(true, grip);
    }
    return widget.onBoundaryDrag?.call(direction, grip);
  }

  bool _settingsReady = false;
  late int? _restoreAttempt = widget.session?.restoreAttempt;
  bool _hintVisible = false;
  String? _failedPresentation;
  ReaderActions get _actions => widget.actions;
  bool get _usesPresentation =>
      widget.session?.pagePresentation != null &&
      widget.session?.pagePresentation != _failedPresentation;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = ReaderAudioController(_audioFactory);
    _preferences = widget.preferences ?? ReaderPreferences(widget.settings);
    _settings = _preferences.value;
    _settingsReady = _preferences.loaded;
    _preferences.addListener(_changed);
    _position = widget.initialPosition;
    _confirmedProgressText = _confirmedProgress;
    _updateProgressText();
    unawaited(_loadPreferences());
  }

  @override
  void didUpdateWidget(ReaderContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final session = widget.session, attempt = session?.restoreAttempt;
    if (attempt != _restoreAttempt) {
      _restoreAttempt = attempt;
      final content = widget.content;
      final target =
          widget.initialPosition ??
          ReaderPosition(
            contentRevision: content.contentRevision,
            blockKey: content.blocks.first.blockKey,
            blockIndex: 0,
            blockFraction: 0,
            chapterFraction: 0,
          );
      // A fast read retry may finish between frames without remounting the page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            widget.session != session ||
            session?.isClosed == true ||
            session?.restoreAttempt != attempt ||
            widget.content != content) {
          return;
        }
        _position = target;
        if (_usesPresentation && _announcedReady) {
          _sample(target, target.chapterFraction == 1);
        } else {
          _paged.restore(target);
        }
      });
    }
    if (!identical(
          oldWidget.logicalProgress?.index,
          widget.logicalProgress?.index,
        ) ||
        oldWidget.logicalProgress?.loading != widget.logicalProgress?.loading ||
        oldWidget.content != widget.content ||
        !widget.active ||
        widget.session?.isClosed == true) {
      _invalidateProgressPreview();
    }
    if (oldWidget.images != widget.images ||
        oldWidget.audioFactory != widget.audioFactory) {
      _audio.dispose();
      _audio = ReaderAudioController(_audioFactory);
    }
    if (oldWidget.logicalProgress?.loading == true &&
        widget.logicalProgress?.loading != true) {
      // The modal lives in another overlay branch; update it after this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _progressMetadataChanges.value++;
      });
    }
    if (!widget.active ||
        widget.session?.isClosed == true ||
        oldWidget.content.key != widget.content.key) {
      _audio.stop();
      _cancelCompletion(immediate: true);
    }
    if (oldWidget.crossChapterTurning && !widget.crossChapterTurning) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applySizes());
    }
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _claimFocus();
    } else {
      // A page leaving the active chapter drops what it was about to open
      // and retires its panel; a choice still coming back from it is not
      // applied, since the page no longer takes commands.
      _progressRequest++;
      _dismissProgressPanel();
      _panel?.dismiss();
      _panel = null;
      _retireSearchSheet();
    }
  }

  /// The page's keyboard focus: shortcuts act while it or a control on the
  /// page holds focus.
  final _pageFocus = FocusNode(debugLabel: 'reader-page');
  late ReaderAudioController _audio;
  AudioPlaybackFactory? get _audioFactory =>
      widget.audioFactory ??
      (widget.images is AudioPlaybackFactory
          ? widget.images as AudioPlaybackFactory
          : null);

  /// Gives the page focus once it becomes the active chapter. The chapter it
  /// replaces takes its focus away with it, which leaves focus on the route
  /// and the keys unheard; focus held anywhere else, or by a route above,
  /// is left alone.
  void _claimFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      if (!_routeCurrent) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null ||
          primary is FocusScopeNode && _pageFocus.ancestors.contains(primary)) {
        _pageFocus.requestFocus();
      }
    });
  }

  Future<void> _loadPreferences() async {
    await (widget.preferencesReady ?? _preferences.ready);
    if (!mounted) return;
    setState(() {
      _settingsReady = true;
      _settings = _preferences.value;
      _hintVisible = widget.active && !_settings.controlsHintSeen;
      if (widget.active) _chrome.value = _hintVisible;
    });
    if (widget.active && widget.session?.usedFallback == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.active) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).readerRestoreNearby),
          ),
        );
      });
    }
  }

  void _changed() {
    if (!mounted || _settings == _preferences.value) return;
    _invalidateProgressPreview();
    _position = _paged.capture() ?? _position;
    setState(() {
      _settings = _preferences.value;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _invalidateProgressPreview();
      _audio.stop();
      _progressRequest++;
      _dismissProgressPanel();
      _dragSurface.currentState?.cancel();
      _cancelCompletion(immediate: true);
      unawaited(_preferences.flush());
      unawaited(widget.session?.flushProgress());
    }
  }

  /// The open desktop panel, if any: the page's one slot, shared by every
  /// panel it opens. Phones and tablets use sheets.
  ReaderPanelHandle<Object?>? _panel;
  final _progressAnchor = GlobalKey(debugLabel: 'reader-progress');

  bool get _desktopPanels => ShioriCapabilities.of(context).pointerFirst;

  /// Whether a live callback from [panel], such as a seek, may still act on
  /// this reader.
  bool _owns(ReaderPanelHandle<Object?> panel) =>
      mounted && panel.isValid && identical(_panel, panel);

  /// Opens a desktop panel in the reading theme, following live edits.
  /// Null while another panel holds the slot or the page takes no commands.
  ReaderPanelHandle<T>? _openPanel<T>(
    ReaderPanelPlacement placement, {
    required String semanticLabel,
    required Widget Function(BuildContext context, ReaderPanelHandle<T> panel)
    builder,
    GlobalKey? anchor,
  }) {
    if (_panel?.isValid == true || !_interactive) return null;
    final panel = ReaderPanelHandle<T>.open(
      this,
      placement: placement,
      semanticLabel: semanticLabel,
      anchor: anchor,
      themeChanges: _preferences,
      theme: (context) => readerTheme(
        _preferences.value,
        MediaQuery.platformBrightnessOf(context),
        accent: appAccentOf(context),
      ),
      builder: builder,
    );
    _panel = panel;
    widget.onPanelChanged?.call(panel);
    unawaited(
      panel.closed.then((_) {
        if (identical(_panel, panel)) {
          _panel = null;
          widget.onPanelChanged?.call(null);
        }
      }),
    );
    return panel;
  }

  /// Applies the choice [panel] hands back once it has closed, only if this
  /// page still reads the session it was opened for and takes commands.
  /// Esc, a click outside and retirement hand back nothing.
  Future<void> _deliver(ReaderPanelHandle<VoidCallback>? panel) async {
    if (panel == null) return;
    final session = widget.session;
    final then = await panel.closed;
    if (then != null &&
        mounted &&
        identical(widget.session, session) &&
        _interactive) {
      then();
    }
  }

  void _retireSearchSheet() {
    final sheet = _searchSheet;
    _searchSheet = null;
    if (sheet == null) return;
    final navigator = sheet.navigator;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator?.mounted == true && sheet.isActive) {
        navigator!.removeRoute(sheet);
      }
    });
  }

  ModalBottomSheetRoute<void>? _searchSheet;
  Future<void> _searchPanel(BuildContext context) async {
    final state = widget.search;
    if (state == null) return;
    if (_panel?.isValid == true || _searchSheet?.isActive == true) {
      state.focusRequest.value++;
      return;
    }
    if (!_interactive) return;
    widget.onSearchOpen?.call();
    final source = widget.session;
    if (_desktopPanels) {
      final panel = _openPanel<void>(
        ReaderPanelPlacement.end,
        semanticLabel: AppLocalizations.of(context).readerSearchBook,
        builder: (context, panel) => ReaderSearchPanel(
          controller: state,
          accepts: () => _owns(panel) && identical(source, widget.session),
          onClose: panel.close,
          closeForNavigation: () async {
            panel.close();
            await panel.completed;
          },
          titleFor: widget.searchTitle ?? (_, _) async => widget.content.title,
        ),
      );
      if (panel != null) {
        await panel.closed;
        await state.panelClosed();
      }
    } else {
      late ModalBottomSheetRoute<void> route;
      route = shioriSheetRoute<void>(
        context,
        size: ReaderSheetSize.tall,
        builder: (context) => ReaderSearchPanel(
          controller: state,
          accepts: () =>
              mounted && route.isCurrent && identical(source, widget.session),
          onClose: () => Navigator.of(context).pop(),
          closeForNavigation: () async {
            Navigator.of(context).pop();
            await route.completed;
          },
          titleFor: widget.searchTitle ?? (_, _) async => widget.content.title,
        ),
      );
      _searchSheet = route;
      await Navigator.of(context, rootNavigator: true).push(route);
      if (identical(_searchSheet, route)) _searchSheet = null;
      await state.panelClosed();
    }
  }

  /// A single footnote over the page: a compact dialog in the reading theme
  /// on desktop, sharing the page's slot, and the sheet elsewhere.
  Future<void> _footnote(BuildContext context, LocalContentLink note) async {
    if (!_interactive) return;
    if (!_desktopPanels) return showReaderFootnote(context, note);
    final panel = _openPanel<void>(
      ReaderPanelPlacement.center,
      semanticLabel: AppLocalizations.of(context).readerFootnote(note.label),
      builder: (context, panel) =>
          ReaderFootnotePanel(note: note, onClose: () => panel.close()),
    );
    await panel?.closed;
  }

  Future<void> _settingsPanel(BuildContext context) async {
    if (!_desktopPanels) return showReaderSettings(context, _preferences);
    final panel = _openPanel(
      ReaderPanelPlacement.end,
      semanticLabel: AppLocalizations.of(context).readerSettings,
      builder: (context, panel) => ReaderSettingsPanel(
        preferences: _preferences,
        onDone: () => panel.close(),
      ),
    );
    if (panel == null) return;
    await panel.closed;
    // As the sheet: edits are flushed once the panel closes; an owner going
    // away first flushes through the preferences' own dispose.
    await _preferences.flush();
  }

  late ChapterContent _articleContent = widget.content;
  late var _articleEntries = articleContents(_articleContent);
  List<ReaderContentsLayer> _contentsLayers(BuildContext context) {
    if (widget.articleContents && !identical(_articleContent, widget.content)) {
      _articleContent = widget.content;
      _articleEntries = articleContents(_articleContent);
    }
    return [
      if (widget.articleContents)
        articleContentsLayer(
          context,
          widget.content,
          entries: _articleEntries,
          current: _readingPosition,
          browsing: widget.contentsSession?.article,
          onSelect: (target) {
            if (mounted) _navigateTo(target);
          },
        ),
      if (_actions.bookContents case final book?) book(context),
    ];
  }

  /// [book] opens on the book-level layer, e.g. from the completion page.
  Future<void> _contents(BuildContext context, {bool book = false}) async {
    if (!_desktopPanels) {
      final layers = _contentsLayers(context);
      if (layers.isEmpty) return;
      return showReaderContents(
        context,
        layers: layers,
        initialLayer: book ? layers.length - 1 : null,
        session: widget.contentsSession,
      );
    }
    final layers = _contentsLayers(context);
    if (layers.isEmpty) return;
    // The selection comes back as the panel's result and is applied only
    // after the panel has closed, to the page that opened it.
    await _deliver(
      _openPanel<VoidCallback>(
        ReaderPanelPlacement.start,
        semanticLabel: layers.length == 1
            ? layers.single.label
            : AppLocalizations.of(context).catalogTitle,
        builder: (context, panel) => ReaderContentsPanel(
          layers: layers,
          initialLayer: book ? layers.length - 1 : null,
          session: widget.contentsSession,
          closeButton: true,
          onDone: ([then]) => panel.close(then),
        ),
      ),
    );
  }

  late final _paged = widget.viewportController ?? PagedReaderController();
  late final _chrome = widget.chrome ?? ValueNotifier(true);
  final _readingPosition = ValueNotifier<ReaderPosition?>(null);
  ReaderPosition? _latestReadingPosition;
  bool _lastPageVisible = false;
  double get _displayChapterFraction =>
      (_latestReadingPosition ?? _readingPosition.value ?? _position)
          ?.chapterFraction ??
      0;
  // Show the extent of the visible page; keep its start as the resume anchor.
  double get _visibleChapterFraction =>
      _lastPageVisible ? 1 : _displayChapterFraction;
  ReaderPosition? get _anchor =>
      _latestReadingPosition ??
      _readingPosition.value ??
      _position ??
      widget.initialPosition;
  LocalChapterSection? get _logicalSection =>
      widget.logicalProgress?.index?.sectionAt(widget.content.key, _anchor);
  double get _visibleScopeFraction {
    final section = _logicalSection, index = widget.logicalProgress?.index;
    return section == null || index == null
        ? _visibleChapterFraction
        : section.fraction(
            index.coordinate(widget.content.key, _visibleChapterFraction)!,
          );
  }

  final _progressText =
      ValueNotifier<({_ProgressText shown, _ProgressText confirmed})>((
        shown: (percent: '0', document: false),
        confirmed: (percent: '0', document: false),
      ));
  ReaderTurnPreview? _progressTurn;
  _ProgressEndpoint? _progressFrom, _progressTo;
  double _turnProgress = 0;
  bool _progressTextQueued = false;
  _ProgressText _confirmedProgressText = (percent: '0', document: false);

  _ProgressText get _confirmedProgress => (
    percent: widget.logicalProgress?.loading == true
        ? null
        : formatReadingPercent(_visibleScopeFraction),
    document: widget.logicalProgress != null && _logicalSection == null,
  );

  _ProgressEndpoint? _progressEndpoint(
    ({ReaderPosition position, bool last}) endpoint,
  ) {
    final logical = widget.logicalProgress, index = logical?.index;
    if (logical?.loading == true ||
        (index != null &&
            index.documents[widget.content.key]?.matches(widget.content) !=
                true)) {
      return null;
    }
    final section = index?.sectionAt(widget.content.key, endpoint.position);
    final fraction = endpoint.last ? 1.0 : endpoint.position.chapterFraction;
    return (
      scope: section ?? widget.content.key,
      fraction: section == null
          ? fraction
          : section.fraction(index!.coordinate(widget.content.key, fraction)!),
      document: logical != null && section == null,
    );
  }

  void _previewProgress(ReaderTurnPreview turn, double? progress) {
    if (!mounted) return;
    if (progress == null) {
      if (!identical(_progressTurn, turn)) return;
      _progressTurn = null;
      _progressFrom = _progressTo = null;
    } else {
      if (!identical(_progressTurn, turn)) {
        _progressTurn = turn;
        _progressFrom = _progressEndpoint(turn.from);
        _progressTo = _progressEndpoint(turn.to);
      }
      _turnProgress = progress.clamp(0.0, 1.0);
      if (_exitOwner?.saving == true ||
          turn.layoutGeneration != _paged.layoutGeneration ||
          _paged.isRestoring ||
          widget.session?.isClosed == true) {
        _progressFrom = _progressTo = null;
      }
    }
    _updateProgressText();
  }

  void _invalidateProgressPreview() {
    // Keep the operation identity so later frames cannot revive invalid inputs.
    _progressFrom = _progressTo = null;
    _confirmedProgressText = _confirmedProgress;
    _updateProgressText();
  }

  void _updateProgressText() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_progressTextQueued) return;
      _progressTextQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _progressTextQueued = false;
        if (mounted) _updateProgressText();
      });
      return;
    }
    final confirmed = _confirmedProgressText;
    var shown = confirmed;
    final from = _progressFrom, to = _progressTo;
    if (from != null && to != null) {
      final discrete = _progressTurn!.discrete;
      if (discrete || from.scope == to.scope) {
        final fraction = discrete || _turnProgress == 1
            ? to.fraction
            : from.fraction + (to.fraction - from.fraction) * _turnProgress;
        shown = (
          percent: formatReadingPercent(fraction),
          document: to.document,
        );
      }
    }
    _progressText.value = (shown: shown, confirmed: confirmed);
  }

  bool _announcedReady = false;
  late final _openingReady = ValueNotifier(
    !widget.active || widget.completion != null,
  );
  int _layoutEpoch = 0;
  void _layoutInvalidated() {
    _invalidateProgressPreview();
    _audio.stop();
    _layoutEpoch++;
    _announcedReady = false;
    _cancelCompletion(immediate: true);
    widget.session?.restoringProgress();
    widget.onLayoutInvalidated?.call();
  }

  void _sample(ReaderPosition position, bool completed) {
    widget.session?.finishRestoringProgress();
    if (_exitOwner?.saving == true) return;
    _lastPageVisible = _usesPresentation || completed;
    if ((widget.completion != null || _completionTurning) &&
        widget.session?.hasPendingNavigation != true) {
      return;
    }
    if (!_announcedReady) {
      _announcedReady = true;
      final epoch = _layoutEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _layoutEpoch) {
          if (!_openingReady.value) {
            _openingReady.value = true;
            if (widget.active) _claimFocus();
          }
          widget.onReady?.call();
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    _latestReadingPosition = position;
    _lastPageVisible = _usesPresentation || completed;
    _readingPosition.value = position;
    _confirmedProgressText = _confirmedProgress;
    _updateProgressText();
    widget.session?.sampleProgress(position, completed);
    widget.onPosition?.call(position);
  }

  ReaderPosition? _position;
  // Horizontal page margin from the last build; the chrome aligns to it.
  double _margin = 0;
  (Color, PageTurnStyle)? _reportedLook;

  // Whether the chapter has flowing prose (spreads apply); scanning every
  // block is linear, so remember the answer per content instance.
  (ChapterContent, bool)? _prose;
  bool _isProse(ChapterContent content) {
    if (_prose case (
      final cached,
      final value,
    ) when identical(cached, content)) {
      return value;
    }
    final value = content.blocks.whereType<ParagraphBlock>().any(
      (block) =>
          block.box == null &&
          block.alignment == ParagraphAlignment.start &&
          block.text.replaceAll('\uFFFC', '').trim().isNotEmpty,
    );
    _prose = (content, value);
    return value;
  }

  EdgeInsets _pageInsets = EdgeInsets.zero;
  final _sizes = <MediaRef, Size>{};
  final _pendingSizes = <MediaRef, Size>{};
  bool _dragging = false;
  bool get _layoutFrozen =>
      _dragging || widget.crossChapterTurning || _completionTurning;
  void _dimensions(MediaRef ref, Size size) {
    if (_sizes[ref] == size) return;
    _pendingSizes[ref] = size;
    if (!_layoutFrozen) _applySizes();
  }

  void _applySizes() {
    if (!mounted ||
        _layoutFrozen ||
        widget.session?.isClosed == true ||
        _pendingSizes.isEmpty) {
      return;
    }
    _position = _paged.capture();
    setState(() {
      _sizes.addAll(_pendingSizes);
      _pendingSizes.clear();
    });
  }

  void _toggle() => _chrome.value = !_chrome.value;

  /// Whether this page may take a command now: it is the active chapter,
  /// nothing covers its route and no completion turn is running. Whether a
  /// given command exists at all is [_can].
  bool get _interactive =>
      mounted && widget.active && !_completionTurning && _routeCurrent;

  /// The page's route, recorded by a leaf of [build] rather than looked up
  /// here: depending on the route from this state would rebuild the whole
  /// page, and the EPUB view in it, each time a panel opens or closes.
  ModalRoute<Object?>? _route;

  bool get _routeCurrent => _route?.isCurrent != false;

  /// Shared permission checks for text, completion, menus and shortcuts.
  bool _can(ReaderCommand command) {
    final text = widget.completion == null;
    return switch (command) {
      ReaderCommand.previousPage => text || _actions.completionPrevious != null,
      ReaderCommand.nextPage || ReaderCommand.progress => text,
      ReaderCommand.toggleControls => true,
      ReaderCommand.contents =>
        widget.articleContents || _actions.bookContents != null,
      ReaderCommand.settings => true,
      ReaderCommand.search => widget.search != null && widget.searchEnabled,
      ReaderCommand.notes => text && _actions.links != null,
      ReaderCommand.prefetch => text && _actions.prefetch != null,
      ReaderCommand.details => _actions.details != null,
      ReaderCommand.previousLocation => _actions.previousLocation != null,
      ReaderCommand.retrySave => widget.session?.canRetryProgress == true,
      ReaderCommand.retrySettings => _preferences.failure != null,
    };
  }

  /// The one handler behind toolbar buttons, menus and shortcuts.
  void _run(BuildContext context, ReaderCommand command) {
    if (!_interactive || !_can(command)) return;
    switch (command) {
      case ReaderCommand.previousPage:
        _turnPage(false);
      case ReaderCommand.nextPage:
        _turnPage(true);
      case ReaderCommand.toggleControls:
        _toggle();
      case ReaderCommand.contents:
        unawaited(_contents(context, book: widget.completion != null));
      case ReaderCommand.progress:
        _requestProgress(context);
      case ReaderCommand.settings || ReaderCommand.retrySettings:
        unawaited(_settingsPanel(context));
      case ReaderCommand.search:
        unawaited(_searchPanel(context));
      case ReaderCommand.notes:
        _actions.links?.call(_PagePanels(this, context));
      case ReaderCommand.prefetch:
        _actions.prefetch?.call(_PagePanels(this, context));
      case ReaderCommand.details:
        _actions.details?.call();
      case ReaderCommand.previousLocation:
        _actions.previousLocation?.call();
      case ReaderCommand.retrySave:
        widget.session?.retryProgress();
    }
  }

  /// Space belongs to a focused control: it turns the page only while the
  /// page itself holds focus. Other keys always reach [_run].
  bool _accepts(ReaderCommandIntent intent) =>
      !intent.yieldsToControls ||
      identical(FocusManager.instance.primaryFocus, _pageFocus);

  /// Esc hands back to the route, whose back handling closes the toolbars,
  /// saves before leaving or leaves directly, as the system back does.
  void _back(BuildContext context) {
    if (_routeCurrent && _completionTurning) {
      _cancelCompletion();
      return;
    }
    if (_routeCurrent && widget.onCancelChapter != null) {
      widget.onCancelChapter!();
      return;
    }
    if (_interactive) unawaited(Navigator.of(context).maybePop());
  }

  /// Bumped to drop a progress request still waiting for the toolbars.
  int _progressRequest = 0;
  final _progressMetadataChanges = ValueNotifier(0);
  ModalRoute<VoidCallback>? _progressRoute;

  /// Retire only the progress host. A result already in its closing animation
  /// still finishes normally, but its request generation prevents navigation.
  void _dismissProgressPanel() {
    final route = _progressRoute;
    _progressRoute = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  bool get _progressAnchored {
    final anchor = _progressAnchor.currentContext?.findRenderObject();
    return anchor is RenderBox && anchor.attached && anchor.hasSize;
  }

  /// Opens progress over its control, first showing the toolbars when they
  /// are hidden and waiting for the control to lay out. The request is
  /// dropped if, by then, the page is no longer active, the toolbars were
  /// hidden again or a route covers the page.
  void _requestProgress(BuildContext context) {
    final request = ++_progressRequest;
    if (!_desktopPanels || _chrome.value && _progressAnchored) {
      unawaited(_progressPanel(context));
      return;
    }
    _chrome.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (request != _progressRequest ||
          !context.mounted ||
          !_interactive ||
          !_chrome.value ||
          !_progressAnchored) {
        return;
      }
      unawaited(_progressPanel(context));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Context menu entries for the page, in the order of the bottom bar and
  /// then the overflow menu.
  List<(ReaderCommand, String)> _contextEntries(AppLocalizations l) => [
    for (final (command, label) in [
      (ReaderCommand.contents, l.catalogTitle),
      (ReaderCommand.progress, l.readerProgressLabel),
      (ReaderCommand.settings, l.readerSettings),
      (
        ReaderCommand.previousLocation,
        _actions.previousLocationLabel ?? l.readerPreviousLocation,
      ),
      (ReaderCommand.notes, l.readerLinks),
      (ReaderCommand.details, l.novelDetailsTitle),
      (
        ReaderCommand.toggleControls,
        _chrome.value ? l.hideReaderControls : l.showReaderControls,
      ),
    ])
      if (_can(command)) (command, label),
  ];

  /// The page's context menu, at [at] for a right click or in the middle of
  /// the page from the keyboard. The chosen command runs only if this page
  /// still reads the same session and takes commands.
  Future<void> _contextMenu(BuildContext context, {Offset? at}) async {
    if (!_desktopPanels || !_interactive) return;
    final entries = _contextEntries(AppLocalizations.of(context));
    if (entries.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final page = context.findRenderObject()! as RenderBox;
    final point = overlay.globalToLocal(
      at ?? page.localToGlobal(page.size.center(Offset.zero)),
    );
    final session = widget.session;
    final command = await showMenu<ReaderCommand>(
      context: context,
      position: RelativeRect.fromRect(
        point & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final (command, label) in entries)
          ShioriMenuItem(value: command, label: label),
      ],
    );
    if (command == null ||
        !mounted ||
        !context.mounted ||
        !identical(widget.session, session)) {
      return;
    }
    _run(context, command);
  }

  // A right press that a right release near it completes opens the menu.
  // Only the press carries the button, so it is remembered by pointer.
  int? _secondaryPointer;
  Offset _secondaryDown = Offset.zero;

  void _pointerDown(PointerDownEvent event) {
    final secondary =
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kSecondaryMouseButton;
    _secondaryPointer = secondary ? event.pointer : null;
    _secondaryDown = event.position;
  }

  void _pointerUp(BuildContext context, PointerUpEvent event) {
    if (event.pointer != _secondaryPointer) return;
    _secondaryPointer = null;
    if ((event.position - _secondaryDown).distance > kTouchSlop) return;
    unawaited(_contextMenu(context, at: event.position));
  }

  void _leave(BuildContext context) {
    if (_actions.leave case final leave?) {
      leave();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _turnPage(bool forward, {bool queueIfTurning = true}) {
    if (!widget.active || _completionTurning || !_routeCurrent) {
      return;
    }
    if (widget.completion != null) {
      if (!forward) _completionTransition.currentState?.turn(false);
      return;
    }
    if (_usesPresentation) {
      if (forward) {
        _presentationNext();
      } else {
        _actions.previousChapter?.call();
      }
    } else {
      unawaited(
        forward
            ? _paged.next(queueIfTurning: queueIfTurning)
            : _paged.previous(queueIfTurning: queueIfTurning),
      );
    }
  }

  void _forwardBoundary() {
    if (_actions.nextChapter case final next?) {
      next();
    } else if (_actions.bookEnd != null) {
      _completionTransition.currentState?.turn(true);
    }
  }

  void _presentationNext() {
    final last = widget.content.blocks.length - 1;
    _sample(
      ReaderPosition(
        contentRevision: widget.content.contentRevision,
        blockKey: widget.content.blocks[last].blockKey,
        blockIndex: last,
        blockFraction: 1,
        chapterFraction: 1,
      ),
      true,
    );
    _forwardBoundary();
  }

  Timer? _wheelCooldown;
  void _scrollPage(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        (_usesPresentation && widget.completion == null) ||
        event.scrollDelta.dy == 0 ||
        event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs() ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        !_routeCurrent) {
      return;
    }
    // Let nested scrollables claim the event first. A wheel burst advances one
    // page group, without queuing turns while the paper animation is active.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final active = _wheelCooldown != null;
      _wheelCooldown?.cancel();
      _wheelCooldown = Timer(const Duration(milliseconds: 350), () {
        _wheelCooldown = null;
      });
      if (active || _dragging || _paged.isRestoring) return;
      _turnPage(event.scrollDelta.dy > 0, queueIfTurning: false);
    });
  }

  @override
  void dispose() {
    _removeExit?.call();
    _retireSearchSheet();
    _audio.dispose();
    _panel?.dismiss();
    _panel = null;
    _progressRequest++;
    _dismissProgressPanel();
    _progressMetadataChanges.dispose();
    _pageFocus.dispose();
    _wheelCooldown?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _preferences.removeListener(_changed);
    if (widget.preferences == null) _preferences.dispose();
    _paperTurn.dispose();
    if (widget.chrome == null) _chrome.dispose();
    _progressText.dispose();
    _readingPosition.dispose();
    _openingReady.dispose();
    super.dispose();
  }

  Widget _image(BuildContext context, ImageBlock image) => Semantics(
    image: true,
    label: image.alt ?? AppLocalizations.of(context).readerImagePlaceholder,
    child: ExcludeSemantics(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(ShioriSpace.medium),
            child: Text(
              image.caption ??
                  image.alt ??
                  AppLocalizations.of(context).readerImagePlaceholder,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final brightness = switch (_settings.themeMode) {
      ReaderThemeMode.system => MediaQuery.platformBrightnessOf(context),
      ReaderThemeMode.light => Brightness.light,
      ReaderThemeMode.dark => Brightness.dark,
    };
    final page = AnnotatedRegion<SystemUiOverlayStyle>(
      // Transparent bars let edge-to-edge pages show paper, not black.
      value:
          (brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
                systemNavigationBarIconBrightness: brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
      child: Theme(
        data: readerTheme(
          _settings,
          MediaQuery.platformBrightnessOf(context),
          accent: appAccentOf(context),
        ),
        child: ReaderFontGate(
          content: widget.content,
          repository: widget.images,
          child: Builder(builder: _body),
        ),
      ),
    );
    // Only this leaf rebuilds when the route changes; it hands back the same
    // page, which is left as it is.
    return Builder(
      builder: (context) {
        _route = ModalRoute.of(context);
        if (!_routeCurrent) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_routeCurrent) _audio.stop();
          });
          _dragSurface.currentState?.cancel();
          _cancelCompletion(immediate: true);
        }
        return page;
      },
    );
  }

  Widget _body(BuildContext context) {
    if (!_settingsReady) {
      return const ReaderLoadingPage();
    }
    final look = (
      Theme.of(context).scaffoldBackgroundColor,
      _settings.pageTurn,
    );
    if (look != _reportedLook) {
      _reportedLook = look;
      widget.onPageAppearance?.call(look.$1, look.$2);
    }
    _pageInsets = MediaQuery.paddingOf(context);
    final layout = NativeReaderSettingsAdapter.resolve(
      _settings,
      theme: Theme.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      explicitUiTypeface: ShioriCapabilities.of(context).explicitUiTypeface,
    );
    _margin = layout.horizontalMargin;
    final style = layout.bodyStyle;
    final page = WindowCaptionScope(
      enabled:
          (widget.appearanceActive ?? widget.active) &&
          (widget.session == null ||
              !widget.session!.isClosed &&
                  widget.session!.status == ReaderStatus.ready &&
                  widget.session!.chapter == widget.content.key),
      appearance: (
        color: Theme.of(context).scaffoldBackgroundColor,
        brightness: Theme.of(context).brightness,
      ),
      child: LayoutBuilder(
        builder: (context, pageBounds) => Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              resizeToAvoidBottomInset: false,
              // Not modal: a key whose command stands aside, such as Space on
              // a focused button, goes on to the control's own handling.
              body: Shortcuts(
                shortcuts: _desktopPanels
                    ? desktopReaderShortcuts
                    : readerShortcuts,
                child: Actions(
                  actions: _commandActions(context),
                  child: Focus(
                    focusNode: _pageFocus,
                    autofocus: widget.active,
                    child: ReaderCompletionTransition(
                      key: _completionTransition,
                      style: _settings.pageTurn,
                      animate: !_usesPresentation,
                      basis: (widget.completionBasis, widget.content),
                      canTurn: _canCompletionTurn,
                      onCommit: _commitCompletion,
                      onTurning: _completionTurnChanged,
                      preview: widget.completionTarget == null
                          ? null
                          : _completionPage(
                              context,
                              style,
                              pageBounds.biggest,
                              widget.completionTarget!,
                            ),
                      completion: widget.completion == null
                          ? null
                          : _completionPage(
                              context,
                              style,
                              pageBounds.biggest,
                              widget.completion!,
                            ),
                      child: SafeArea(
                        child: Stack(
                          fit: StackFit.expand,
                          // Toolbars paint into the safe-area insets.
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: _page(context, pageBounds, layout),
                            ),
                            ValueListenableBuilder<bool>(
                              valueListenable: _chrome,
                              builder: (context, visible, _) =>
                                  ListenableBuilder(
                                    listenable: _preferences,
                                    builder: (context, _) => visible
                                        ? _toolbars(context)
                                        : _runningChrome(context),
                                  ),
                            ),
                            if (_hintVisible && widget.completion == null)
                              Positioned(
                                left: ShioriSpace.item,
                                right: ShioriSpace.item,
                                bottom:
                                    ReaderChromeMetrics.of(context).bottomBar +
                                    ShioriSpace.small,
                                child: ReaderControlsHint(
                                  onDismiss: _dismissHint,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<PageTurnFrame>(
              valueListenable: _paperTurn,
              builder: (context, frame, _) => PageTurnOverlay(
                frame: frame,
                paper: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          ],
        ),
      ),
    );
    return ReaderOpeningTransition(ready: _openingReady, child: page);
  }

  Map<Type, Action<Intent>> _commandActions(BuildContext context) => {
    ReaderCommandIntent: _ReaderAction<ReaderCommandIntent>(
      enabled: _accepts,
      run: (intent) => _run(context, intent.command),
    ),
    ReaderBackIntent: _ReaderAction<ReaderBackIntent>(
      run: (_) => _back(context),
    ),
    ReaderContextMenuIntent: _ReaderAction<ReaderContextMenuIntent>(
      run: (_) => unawaited(_contextMenu(context)),
    ),
  };

  void _dismissHint() {
    setState(() => _hintVisible = false);
    _preferences.update(_settings.copyWith(controlsHintSeen: true));
    _preferences.flush();
  }

  String get _bookTitle =>
      widget.bookTitle ??
      widget.session?.progress?.snapshot.title ??
      widget.runningTitle ??
      widget.content.title;

  Widget _completionPage(
    BuildContext context,
    TextStyle style,
    Size pageSize,
    BookTerminalState state,
  ) {
    final metrics = ReaderChromeMetrics.of(context);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Listener(
          onPointerSignal: _scrollPage,
          onPointerDown: _pointerDown,
          onPointerUp: (event) => _pointerUp(context, event),
          child: ValueListenableBuilder<bool>(
            valueListenable: _chrome,
            builder: (context, visible, _) => Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                ReaderCompletionPage(
                  state: state,
                  title: _bookTitle,
                  style: style,
                  chromeVisible: visible,
                  pageSize: pageSize,
                  contentOrigin: Offset(_pageInsets.left, _pageInsets.top),
                  padding: EdgeInsets.only(
                    top: metrics.topBar,
                    bottom: metrics.bottomBar,
                  ),
                  onPrevious: () => _run(context, ReaderCommand.previousPage),
                  onToggleChrome: () =>
                      _run(context, ReaderCommand.toggleControls),
                  onDrag: _usesPresentation
                      ? null
                      : (grip) => _completionTransition.currentState?.begin(
                          false,
                          grip,
                        ),
                  onExit: () {
                    if (_interactive) _actions.exitToShelf?.call();
                  },
                  onCatalog: () => _run(context, ReaderCommand.contents),
                  onRestart: () {
                    if (_interactive) _actions.restart?.call();
                  },
                ),
                if (visible)
                  ListenableBuilder(
                    listenable: _preferences,
                    builder: (context, _) =>
                        _toolbars(context, completion: true),
                  )
                else if (ShioriCapabilities.of(context).immersiveSystemUi)
                  Positioned(
                    bottom: 0,
                    left: _margin,
                    right: _margin,
                    height: metrics.footer,
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: ReaderChromeMetrics.inner,
                          bottom: ReaderChromeMetrics.edge,
                        ),
                        child: const Center(
                          child: ReaderStatusRow(progress: SizedBox.shrink()),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The paginated page (native or EPUB presentation) inside stable gutters
  /// that keep showing / hiding the toolbars from repaginating content.
  Widget _page(
    BuildContext context,
    BoxConstraints pageBounds,
    NativeReaderLayoutSettings layout,
  ) {
    final chrome = ReaderChromeMetrics.of(context);
    final spread =
        !_usesPresentation &&
        _isProse(widget.content) &&
        pageBounds.maxWidth - _pageInsets.horizontal - 2 * _margin >=
            2 * readerMinColumnWidth + readerColumnGap;
    final page = Listener(
      onPointerSignal: _scrollPage,
      onPointerDown: _pointerDown,
      onPointerUp: (event) => _pointerUp(context, event),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _margin,
          chrome.header,
          _margin,
          chrome.footer,
        ),
        child: Align(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: spread
                  ? 2 * readerMaxPageWidth + readerColumnGap
                  : readerMaxPageWidth,
            ),
            child: LayoutBuilder(
              builder: (context, bounds) => _usesPresentation
                  ? _presentationPage()
                  : _nativePage(
                      context,
                      pageBounds: pageBounds,
                      bounds: bounds,
                      columns: spread ? 2 : 1,
                      layout: layout,
                      contentTop: _pageInsets.top + chrome.header,
                    ),
            ),
          ),
        ),
      ),
    );
    if (_usesPresentation) return page;
    return PagedReaderDragSurface(
      key: _dragSurface,
      controller: _paged,
      enabled: _interactive && widget.completion == null,
      isCurrent: () =>
          mounted &&
          _routeCurrent &&
          _panel?.isValid != true &&
          widget.session?.isClosed != true,
      pageSize: pageBounds.biggest,
      pageOrigin: Offset(_pageInsets.left, _pageInsets.top),
      child: page,
    );
  }

  Widget _presentationPage() {
    final presentation = widget.session!.pagePresentation!;
    return ExcludeSemantics(
      excluding: widget.completion != null,
      child: EpubLayoutPage(
        html: presentation,
        links: widget.session?.contentLinks ?? const [],
        onLink: _actions.contentLink,
        onFailed: () {
          if (mounted) setState(() => _failedPresentation = presentation);
        },
        onCenterTap: _toggle,
        chromeVisible: _chrome,
        onPrevious: _actions.previousChapter,
        onNext: _presentationNext,
        onReady: () {
          final position =
              _position ??
              ReaderPosition(
                contentRevision: widget.content.contentRevision,
                blockKey: widget.content.blocks.first.blockKey,
                blockIndex: 0,
                blockFraction: 0,
                chapterFraction: 0,
              );
          _position = position;
          _sample(position, position.chapterFraction == 1);
        },
      ),
    );
  }

  Widget _nativePage(
    BuildContext context, {
    required BoxConstraints pageBounds,
    required BoxConstraints bounds,
    required int columns,
    required NativeReaderLayoutSettings layout,
    required double contentTop,
  }) {
    final style = layout.bodyStyle;
    final columnWidth =
        (bounds.maxWidth - (columns - 1) * readerColumnGap) / columns;
    final imageIndexes = Map<ImageBlock, int>.identity();
    for (final (index, block) in widget.content.blocks.indexed) {
      if (block is ImageBlock) {
        imageIndexes[block] = index;
      }
    }
    ({double height, double caption}) extent(ImageBlock block) {
      final boxes = readerBlockBoxes(
        block,
        columnWidth,
        style,
        MediaQuery.textScalerOf(context),
        pageHeight: bounds.maxHeight,
      );
      final edges = readerBoxEdges(
        widget.content,
        imageIndexes[block] ?? widget.content.blocks.indexOf(block),
        width: columnWidth,
        style: style,
        scaler: MediaQuery.textScalerOf(context),
        pageHeight: bounds.maxHeight,
      );
      return readerImageExtent(
        block,
        width: boxes.innerWidth,
        maxHeight: (bounds.maxHeight - edges.top - edges.bottom).clamp(
          1,
          bounds.maxHeight,
        ),
        scaler: MediaQuery.textScalerOf(context),
        direction: Directionality.of(context),
        knownSize: _sizes[block.media],
      );
    }

    Widget image(BuildContext context, ImageBlock block) {
      final geometry = extent(block);
      return SizedBox(
        height: geometry.height,
        child: widget.images == null
            ? _image(context, block)
            : ReaderImage(
                onTap: !_interactive
                    ? null
                    : () => showReaderImagePreview(
                        context,
                        block: block,
                        repository: widget.images!,
                      ),
                block: block,
                repository: widget.images!,
                captionHeight: geometry.caption,
                onIntrinsicSize: (size) {
                  if (block.width == size.width &&
                      block.height == size.height) {
                    return;
                  }
                  _dimensions(block.media, size);
                },
              ),
      );
    }

    final viewport = ExcludeSemantics(
      excluding: widget.completion != null,
      child: PagedReaderViewport(
        hostedDrag: true,
        inputEnabled:
            widget.active && widget.completion == null && !_completionTurning,
        onBoundaryDrag: _boundaryDrag,
        onEdges: widget.onEdges,
        columns: columns,
        images: widget.images,
        content: widget.content,
        pageSize: pageBounds.biggest,
        contentOrigin: Offset(
          _pageInsets.left +
              (pageBounds.maxWidth - _pageInsets.horizontal - bounds.maxWidth) /
                  2,
          contentTop,
        ),
        onTurnVisual: (frame) => _paperTurn.value = frame,
        onTurnPreview: _previewProgress,
        turnStyle: _settings.pageTurn,
        startAtEnd:
            (widget.session?.startAtEnd ?? false) &&
            _position?.chapterFraction == 1 &&
            _position?.blockFraction == 1,
        onTurning: (turning) {
          if (turning) _audio.stop();
          _dragging = turning;
          if (!turning) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _applySizes();
            });
          }
        },
        onPosition: _sample,
        onTurnCommitted: () {
          _chrome.value = false;
          _actions.pageTurnCommitted?.call();
        },
        onRestoreStart: _layoutInvalidated,
        controller: _paged,
        onLink: _actions.contentLink,
        // Phones and tablets keep the footnote sheet the text opens itself.
        onFootnote: !widget.active
            ? (_) {}
            : _desktopPanels
            ? (note) => unawaited(_footnote(context, note))
            : null,
        contentLinks: widget.session?.contentLinks.toList() ?? const [],
        initialPosition: _position,
        textStyle: style,
        paragraphSpacing: layout.paragraphSpacing,
        onCenterTap: _toggle,
        chromeVisible: _chrome,
        onBoundary: (direction) {
          if (direction > 0) {
            _forwardBoundary();
          } else {
            _actions.previousChapter?.call();
          }
        },
        imageBuilder: image,
        audioBuilder: (context, block) => ReaderAudioControl(
          block: block,
          controller: _audio,
          enabled: _interactive && !_dragging,
        ),
        imageExtent: (block) => extent(block).height,
      ),
    );
    return widget.search == null
        ? viewport
        : ReaderSearchHighlightScope(
            active: widget.search!.highlight,
            content: widget.content,
            child: viewport,
          );
  }

  LocalNavigationEntry? get _titleNavigationEntry {
    if (_logicalSection case final section?) return section.entry;
    final logical = widget.logicalProgress;
    // An auxiliary document is outside logical reading-order sections, but
    // its direct navigation label still names the displayed content.
    if (logical != null &&
        !logical.loading &&
        (logical.index == null ||
            logical.index!.metrics.ordinal(widget.content.key) != null)) {
      return null;
    }
    return widget.navigationEntry;
  }

  String get _effectiveChapterTitle {
    final entry = _titleNavigationEntry;
    if (entry != null) {
      return localNavigationTitle(entry, AppLocalizations.of(context));
    }
    return widget.logicalProgress != null && !widget.logicalProgress!.loading
        ? widget.content.title
        : widget.chapterTitle ?? widget.content.title;
  }

  void _seekChapter(double fraction) {
    final count = widget.content.blocks.length;
    if (count == 0) return;
    final scaled = fraction * count;
    final index = scaled.floor().clamp(0, count - 1);
    final target = ReaderPosition(
      contentRevision: widget.content.contentRevision,
      blockKey: widget.content.blocks[index].blockKey,
      blockIndex: index,
      blockFraction: (scaled - index).clamp(0.0, 1.0),
      chapterFraction: fraction,
    );
    _navigateTo(target);
  }

  /// The one entry for user-chosen positions inside this chapter (headings,
  /// the progress scrubber). It marks the jump as navigation so the session
  /// drops any book-end state and samples during the transition persist,
  /// and leaves the completion page first when it is showing.
  void _navigateTo(ReaderPosition target) {
    _invalidateProgressPreview();
    widget.session?.beginPositionNavigation();
    if (widget.completion != null) _actions.completionPrevious?.call();
    if (_actions.navigatePosition case final navigate?) {
      final session = widget.session, content = widget.content;
      final panel = _panel, route = _progressRoute;
      final request = _progressRequest;
      bool accepts() =>
          mounted &&
          identical(widget.session, session) &&
          widget.content == content &&
          session?.isClosed != true &&
          request == _progressRequest &&
          (_routeCurrent ||
              panel?.isValid == true && panel!.route.isCurrent ||
              route?.isActive == true && route!.isCurrent);
      unawaited(navigate(target, accepts));
    } else {
      _position = target;
      _paged.restore(target);
    }
  }

  Future<void> _progressPanel(BuildContext context) async {
    final request = _progressRequest;
    final session = widget.session, content = widget.content;
    capture() {
      final logical = widget.logicalProgress;
      final index = logical?.index;
      final section = _logicalSection;
      return (
        logical: logical,
        index: index,
        section: section,
        anchor: section == null
            ? _displayChapterFraction
            : section.fraction(
                index!.coordinate(content.key, _displayChapterFraction)!,
              ),
        visible: _visibleScopeFraction,
        entry: _titleNavigationEntry,
        title: _effectiveChapterTitle,
      );
    }

    var basis = capture();
    bool sameReader() =>
        mounted &&
        request == _progressRequest &&
        identical(widget.session, session) &&
        widget.content == content &&
        session?.isClosed != true;
    bool valid() =>
        sameReader() &&
        (basis.logical == null ||
            identical(widget.logicalProgress?.index, basis.index));
    bool live() => valid() && _interactive;
    VoidCallback? step(int direction) {
      final logical = basis.logical,
          index = basis.index,
          section = basis.section;
      if (logical == null) {
        final turn = direction < 0
            ? _actions.previousChapter
            : _actions.nextChapter;
        final navigate = _actions.navigateChapter;
        return turn == null || navigate == null
            ? turn
            : () => navigate(direction);
      }
      if (index == null || section == null) return null;
      final adjacent = index.adjacent(section, direction);
      return adjacent == null
          ? null
          : () {
              if (live()) {
                unawaited(logical.navigate(section, index.target(adjacent, 0)));
              }
            };
    }

    Widget progress(ReaderPanelDone onDone, bool Function() accepts) =>
        ListenableBuilder(
          listenable: _progressMetadataChanges,
          builder: (context, _) {
            final l = AppLocalizations.of(context);
            // Only a disabled loading placeholder adopts new metadata. Once
            // usable, the section and conversion callbacks stay frozen.
            if (sameReader() &&
                basis.logical?.loading == true &&
                widget.logicalProgress?.loading != true) {
              basis = capture();
            }
            final logical = basis.logical,
                index = basis.index,
                section = basis.section;
            return ReaderProgressPanel(
              key: ObjectKey(logical),
              chapterTitle: basis.entry == null
                  ? basis.title
                  : localNavigationTitle(basis.entry!, l),
              chapterFraction: basis.visible,
              anchorFraction: basis.anchor,
              enabled: logical?.loading != true,
              scopeLabel: logical?.loading == true
                  ? l.readerChapterProgressLoading
                  : logical != null && section == null
                  ? l.readerCurrentDocument
                  : null,
              bookFractionAt: (fraction) => section == null
                  ? session?.bookProgressAt(fraction)?.fraction
                  : index!.bookFractionAt(section, fraction),
              onSeek: (fraction) {
                if (!valid() || !accepts()) return;
                if (index == null || section == null) {
                  _seekChapter(fraction);
                  return;
                }
                final target = index.target(section, fraction);
                if (target.chapter == content.key) {
                  _navigateTo(target.position);
                } else {
                  onDone(() {
                    if (live()) unawaited(logical!.navigate(section, target));
                  });
                }
              },
              onDone: onDone,
              showChapterStepper: logical == null
                  ? _actions.hasChapterStepper
                  : section != null,
              onPreviousChapter: step(-1),
              onNextChapter: step(1),
            );
          },
        );
    if (!_desktopPanels) {
      Future<dynamic>? completed;
      ModalRoute<VoidCallback>? route;
      final intent = await showReaderSheet<VoidCallback>(
        context,
        builder: (sheet) {
          if (route == null) {
            route = ModalRoute.of<VoidCallback>(sheet)!;
            _progressRoute = route;
            completed = route!.completed;
            if (!sameReader()) _dismissProgressPanel();
          }
          final sheetRoute = route!;
          return progress(
            ([then]) {
              if (sheetRoute.isCurrent) Navigator.of(sheet).pop(then);
            },
            () =>
                sheetRoute.isCurrent &&
                mounted &&
                identical(widget.session, session),
          );
        },
      );
      await completed;
      if (identical(_progressRoute, route)) _progressRoute = null;
      if (intent != null && live()) intent();
      return;
    }
    // Same-document seeks retain the panel; other choices leave as its result.
    final panel = _openPanel<VoidCallback>(
      ReaderPanelPlacement.anchored,
      semanticLabel: basis.title,
      anchor: _progressAnchor,
      builder: (context, panel) =>
          progress(([then]) => panel.close(then), () => _owns(panel)),
    );
    if (panel == null) return;
    _progressRoute = panel.route;
    final intent = await panel.closed;
    await panel.completed;
    if (identical(_progressRoute, panel.route)) _progressRoute = null;
    if (intent != null && live()) intent();
  }

  /// Only formatted labels observe turn previews; accessibility keeps the anchor.
  Widget _progressLabel(
    String Function(String percent) label, {
    TextStyle? style,
    StrutStyle? strut,
  }) =>
      ValueListenableBuilder<({_ProgressText shown, _ProgressText confirmed})>(
        key: const ValueKey('reader-progress-text'),
        valueListenable: _progressText,
        builder: (context, value, _) {
          String text(_ProgressText progress) => progress.percent == null
              ? AppLocalizations.of(context).readerChapterProgressLoading
              : progress.document
              ? AppLocalizations.of(
                  context,
                ).readerDocumentPercent(progress.percent!)
              : label(progress.percent!);
          return Text(
            text(value.shown),
            semanticsLabel: text(value.confirmed),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            strutStyle: strut,
            style: style,
          );
        },
      );

  Widget _runningChrome(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = Theme.of(context).textTheme.labelSmall ?? const TextStyle();
    final metrics = ReaderChromeMetrics.of(context);
    final progress = _progressLabel(
      l.readerChapterProgress,
      style: label.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      // Keep the status row's forced line box with CJK fallback fonts.
      strut: StrutStyle.fromTextStyle(label, height: 1, forceStrutHeight: true),
    );
    final running = ReaderRunningChrome(
      reserveReturnSpace: widget.quickReturn != null,
      metrics: metrics,
      margin: _margin,
      title: widget.runningTitle ?? widget.content.title,
      statusRow: ShioriCapabilities.of(context).immersiveSystemUi,
      progress: switch (widget.session?.progressStatus) {
        ReaderProgressStatus.unsaved => const ReaderProgressWarning(
          paused: false,
        ),
        ReaderProgressStatus.paused => const ReaderProgressWarning(
          paused: true,
        ),
        _ => progress,
      },
    );
    final visibility = widget.quickReturn;
    if (visibility == null) return running;
    return Stack(
      children: [
        running,
        Positioned(
          top: 0,
          left: ShioriSpace.small,
          child: ValueListenableBuilder<bool>(
            valueListenable: visibility,
            builder: (context, visible, _) => ReaderLocationReturn(
              label: widget.actions.previousLocationLabel,
              metrics: metrics,
              visible:
                  visible &&
                  _interactive &&
                  !_paged.isRestoring &&
                  (_actions.previousLocation != null || widget.returnToOrigin),
              onPressed: () {
                if (!_interactive) return;
                if (_actions.previousLocation != null) {
                  _run(context, ReaderCommand.previousLocation);
                } else if (widget.returnToOrigin) {
                  _leave(context);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Overflow menu entries: what the bottom bar does not already offer.
  List<(ReaderCommand, String)> _menu(AppLocalizations l) => [
    for (final (command, label) in [
      (
        ReaderCommand.previousLocation,
        _actions.previousLocationLabel ?? l.readerPreviousLocation,
      ),
      (ReaderCommand.notes, l.readerLinks),
      (ReaderCommand.prefetch, l.prefetchTitle),
      (ReaderCommand.details, l.novelDetailsTitle),
      (
        ReaderCommand.retrySave,
        widget.session?.progressStatus == ReaderProgressStatus.paused
            ? l.readerRetryReadProgress
            : l.readerRetrySaveProgress,
      ),
      (ReaderCommand.retrySettings, l.readerSettingsFailure),
      (ReaderCommand.toggleControls, l.hideReaderControls),
    ])
      if (_can(command)) (command, label),
  ];

  Widget _toolbars(BuildContext context, {bool completion = false}) {
    final l = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _readingPosition,
      builder: (context, _) => ReaderToolbars(
        metrics: ReaderChromeMetrics.of(context),
        insets: _pageInsets,
        top: ReaderTopBar(
          title: completion ? _bookTitle : _effectiveChapterTitle,
          returnToOrigin: widget.returnToOrigin,
          showSearch: widget.search != null,
          onSearch: _command(context, ReaderCommand.search),
          onLeave: () => _leave(context),
          menu: _menu(l),
          onMenu: (command) => _run(context, command),
        ),
        bottom: ReaderBottomBar(
          contentsTooltip:
              _contentsLayers(context).firstOrNull?.label ?? l.catalogTitle,
          onContents: _command(context, ReaderCommand.contents),
          showProgress: !completion,
          progress: completion
              ? const SizedBox.shrink()
              : _progressLabel(l.readerChapterPercent),
          onProgress: _command(context, ReaderCommand.progress),
          onSettings: _command(context, ReaderCommand.settings),
          progressKey: completion ? null : _progressAnchor,
        ),
      ),
    );
  }

  /// A control's callback for [command], null while the command is
  /// unavailable so the control shows as disabled.
  VoidCallback? _command(BuildContext context, ReaderCommand command) =>
      _can(command) ? () => _run(context, command) : null;
}

/// A reader shortcut's action. [enabled] false lets the key go on to the
/// focused control; otherwise the key is taken even when the command then
/// finds nothing to do, as the page keys always were.
/// The panel slot of one page for a screen-level command, bound to the
/// session the command was invoked for.
class _PagePanels implements ReaderPanels {
  _PagePanels(this._page, this.context)
    : _session = _page.widget.session,
      desktop = _page._desktopPanels;

  final _ReaderContentViewState _page;
  final Object? _session;
  @override
  final BuildContext context;
  @override
  final bool desktop;

  @override
  bool get live =>
      _page.mounted &&
      context.mounted &&
      identical(_page.widget.session, _session) &&
      _page._interactive;

  @override
  ReaderPanelHandle<T>? open<T>(
    ReaderPanelPlacement placement, {
    required String semanticLabel,
    required Widget Function(BuildContext context, ReaderPanelHandle<T> panel)
    builder,
  }) => live
      ? _page._openPanel<T>(
          placement,
          semanticLabel: semanticLabel,
          builder: builder,
        )
      : null;

  @override
  Future<void> footnote(LocalContentLink note) async {
    if (live) await _page._footnote(context, note);
  }
}

class _ReaderAction<T extends Intent> extends Action<T> {
  _ReaderAction({required this.run, this.enabled});
  final void Function(T intent) run;
  final bool Function(T intent)? enabled;

  @override
  bool isEnabled(T intent) => enabled?.call(intent) ?? true;

  @override
  void invoke(T intent) => run(intent);
}
