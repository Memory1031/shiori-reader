import 'dart:async';
import '../../app/window_caption.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/shiori_menu.dart';
import '../../shared/widgets/state_views.dart';
import 'reader_controller.dart';
import 'reader_completion_page.dart';
import 'reader_completion_transition.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';
import 'reading_progress_format.dart';
export 'reader_actions.dart' show ReaderActions;

import 'reader_actions.dart';
import 'reader_chrome.dart';
import 'reader_commands.dart';
import 'reader_contents.dart';
import 'reader_panel.dart';
import 'reader_progress_panel.dart';
import 'reader_sheet.dart';
import 'reader_toolbars.dart';
import 'settings_panel.dart';
import 'reader_margin.dart';
import 'reader_image.dart';
import 'reader_image_preview.dart';
import 'reader_linked_text.dart';
import 'epub_layout_page.dart';
import '../../domain/local_chapter_progress.dart';
import 'reader_logical_progress.dart';
import 'viewport/paged_reader_viewport.dart';
import 'viewport/page_turn.dart';
import 'viewport/reader_box.dart';

/// The body never observes per-frame progress or Chrome visibility changes.
/// Preferences are injected and scoped to this reading session.
class ReaderContentView extends StatefulWidget {
  const ReaderContentView({
    super.key,
    required this.content,
    this.runningTitle,
    this.chapterTitle,
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
    this.settings,
    this.session,
    this.initialPosition,
    this.actions = const ReaderActions(),
    this.articleContents = true,
    this.completion,
    this.completionTarget,
    this.completionBasis,
    this.onCompletionTurn,
    this.bookTitle,
    this.viewportController,
    this.returnToOrigin = false,
    this.chrome,
    this.active = true,
    this.appearanceActive,
  });
  final ImageRepository? images;
  final ChapterContent content;
  final String? runningTitle;
  final String? chapterTitle;
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

  /// Whether headings recognised inside the article form their own layer.
  final bool articleContents;
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
    _preferences = widget.preferences ?? ReaderPreferences(widget.settings);
    _settings = _preferences.value;
    _preferences.addListener(_changed);
    _position = widget.initialPosition;
    unawaited(_loadPreferences());
  }

  @override
  void didUpdateWidget(ReaderContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logicalProgress?.loading == true &&
        widget.logicalProgress?.loading != true) {
      // The modal lives in another overlay branch; update it after this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _progressMetadataChanges.value++;
      });
    }
    if (!widget.active || widget.session?.isClosed == true) {
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
    }
  }

  /// The page's keyboard focus: shortcuts act while it or a control on the
  /// page holds focus.
  final _pageFocus = FocusNode(debugLabel: 'reader-page');

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
    await (widget.preferencesReady ?? _preferences.load());
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
    _position = _paged.capture() ?? _position;
    setState(() {
      _settings = _preferences.value;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
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

  List<ReaderContentsLayer> _contentsLayers(BuildContext context) => [
    if (widget.articleContents)
      articleContentsLayer(
        context,
        widget.content,
        onSelect: (target) {
          if (mounted) _navigateTo(target);
        },
      ),
    if (_actions.bookContents case final book?) book(context),
  ];

  /// [book] opens on the book-level layer, e.g. from the completion page.
  Future<void> _contents(BuildContext context, {bool book = false}) async {
    if (!_desktopPanels) {
      final layers = _contentsLayers(context);
      if (layers.isEmpty) return;
      return showReaderContents(
        context,
        layers: layers,
        initialLayer: book ? layers.length - 1 : 0,
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
          initialLayer: book ? layers.length - 1 : 0,
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

  Timer? _positionLabelTimer;
  bool _announcedReady = false;
  int _layoutEpoch = 0;
  void _layoutInvalidated() {
    _layoutEpoch++;
    _announcedReady = false;
    _cancelCompletion(immediate: true);
    widget.session?.restoringProgress();
    widget.onLayoutInvalidated?.call();
  }

  void _sample(ReaderPosition position, bool completed) {
    widget.session?.finishRestoringProgress();
    _lastPageVisible = _usesPresentation || completed;
    if ((widget.completion != null || _completionTurning) &&
        widget.session?.hasPendingNavigation != true) {
      return;
    }
    if (!_announcedReady) {
      _announcedReady = true;
      final epoch = _layoutEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _layoutEpoch) widget.onReady?.call();
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    _latestReadingPosition = position;
    _lastPageVisible = _usesPresentation || completed;
    // Display is bounded to 4Hz; persistence still receives every sample.
    _positionLabelTimer ??= Timer(const Duration(milliseconds: 250), () {
      _positionLabelTimer = null;
      _readingPosition.value = _latestReadingPosition;
    });
    widget.session?.sampleProgress(position, completed);
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

  bool get _unsaved {
    final session = widget.session;
    return session?.progressFailure != null ||
        session?.progress?.unsaved == true ||
        session?.restoreFailure != null;
  }

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
      ReaderCommand.notes => text && _actions.links != null,
      ReaderCommand.prefetch => text && _actions.prefetch != null,
      ReaderCommand.details => _actions.details != null,
      ReaderCommand.retrySave => _unsaved,
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
      case ReaderCommand.notes:
        _actions.links?.call(_PagePanels(this, context));
      case ReaderCommand.prefetch:
        _actions.prefetch?.call(_PagePanels(this, context));
      case ReaderCommand.details:
        _actions.details?.call();
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
    _positionLabelTimer?.cancel();
    _readingPosition.dispose();
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
        child: Builder(builder: _body),
      ),
    );
    // Only this leaf rebuilds when the route changes; it hands back the same
    // page, which is left as it is.
    return Builder(
      builder: (context) {
        _route = ModalRoute.of(context);
        if (!_routeCurrent) {
          _dragSurface.currentState?.cancel();
          _cancelCompletion(immediate: true);
        }
        return page;
      },
    );
  }

  TextStyle _bodyStyle(BuildContext context) {
    final theme = Theme.of(context);
    final typography = ShioriCapabilities.of(context).explicitUiTypeface
        ? theme.textTheme.bodyLarge
        : null;
    return TextStyle(
      fontFamily: typography?.fontFamily,
      fontFamilyFallback: typography?.fontFamilyFallback,
      fontSize: _settings.fontSize,
      height: _settings.lineHeight,
      color: theme.colorScheme.onSurface,
    );
  }

  Widget _body(BuildContext context) {
    if (!_settingsReady) {
      return const Scaffold(body: SafeArea(child: LoadingView()));
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
    _margin = readerHorizontalMargin(
      _settings,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
    final style = _bodyStyle(context);
    return WindowCaptionScope(
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
                              child: _page(context, pageBounds, style),
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
    TextStyle style,
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
                      style: style,
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
    required TextStyle style,
    required double contentTop,
  }) {
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

    return ExcludeSemantics(
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
        turnStyle: _settings.pageTurn,
        startAtEnd:
            (widget.session?.startAtEnd ?? false) &&
            _position?.chapterFraction == 1 &&
            _position?.blockFraction == 1,
        onTurning: (turning) {
          _dragging = turning;
          if (!turning) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _applySizes();
            });
          }
        },
        onPosition: _sample,
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
        paragraphSpacing: _settings.paragraphSpacing,
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
        imageExtent: (block) => extent(block).height,
      ),
    );
  }

  String get _effectiveChapterTitle =>
      _logicalSection?.title ??
      (widget.logicalProgress != null && !widget.logicalProgress!.loading
          ? widget.content.title
          : widget.chapterTitle ?? widget.content.title);

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
    widget.session?.beginPositionNavigation();
    if (widget.completion != null) _actions.completionPrevious?.call();
    _position = target;
    _paged.restore(target);
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
        title: _effectiveChapterTitle,
      );
    }

    var basis = capture();
    final l = AppLocalizations.of(context);
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
        return direction < 0 ? _actions.previousChapter : _actions.nextChapter;
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
              chapterTitle: basis.title,
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

  /// Chapter progress text, rebuilt at most at the sampling rate.
  Widget _progressLabel(
    String Function(String percent) label, {
    TextStyle? style,
    StrutStyle? strut,
  }) => ValueListenableBuilder<ReaderPosition?>(
    valueListenable: _readingPosition,
    builder: (context, position, _) => Text(
      widget.logicalProgress?.loading == true
          ? AppLocalizations.of(context).readerChapterProgressLoading
          : widget.logicalProgress != null && _logicalSection == null
          ? AppLocalizations.of(context).readerDocumentPercent(
              formatReadingPercent(_visibleChapterFraction),
            )
          : label(formatReadingPercent(_visibleScopeFraction)),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      strutStyle: strut,
      style: style,
    ),
  );

  Widget _runningChrome(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = Theme.of(context).textTheme.labelSmall ?? const TextStyle();
    return ReaderRunningChrome(
      metrics: ReaderChromeMetrics.of(context),
      margin: _margin,
      title: widget.runningTitle ?? widget.content.title,
      statusRow: ShioriCapabilities.of(context).immersiveSystemUi,
      progress: _progressLabel(
        l.readerChapterProgress,
        style: label.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        // Same forced line box as the status row labels, so CJK fallback
        // cannot shift it against them.
        strut: StrutStyle.fromTextStyle(
          label,
          height: 1,
          forceStrutHeight: true,
        ),
      ),
    );
  }

  /// Overflow menu entries: what the bottom bar does not already offer.
  List<(ReaderCommand, String)> _menu(AppLocalizations l) => [
    for (final (command, label) in [
      (ReaderCommand.notes, l.readerLinks),
      (ReaderCommand.prefetch, l.prefetchTitle),
      (ReaderCommand.details, l.novelDetailsTitle),
      (
        ReaderCommand.retrySave,
        widget.session?.restoreFailure != null
            ? l.readerRestoreReadFailed
            : l.readerProgressUnsaved,
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
