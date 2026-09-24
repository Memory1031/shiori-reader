import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
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
import 'reader_contents.dart';
import 'reader_progress_panel.dart';
import 'reader_sheet.dart';
import 'reader_toolbars.dart';
import 'settings_panel.dart';
import 'reader_margin.dart';
import 'reader_image.dart';
import 'reader_image_preview.dart';
import 'epub_layout_page.dart';
import 'viewport/paged_reader_viewport.dart';
import 'viewport/page_turn.dart';

/// The body never observes per-frame progress or Chrome visibility changes.
/// Preferences are injected and scoped to this reading session.
class ReaderContentView extends StatefulWidget {
  const ReaderContentView({
    super.key,
    required this.content,
    this.runningTitle,
    this.chapterTitle,
    this.onReady,
    this.onLoadFailure,
    this.onPageAppearance,
    this.images,
    this.settings,
    this.session,
    this.initialPosition,
    this.actions = const ReaderActions(),
    this.articleContents = true,
    this.completion,
    this.viewportController,
    this.returnToOrigin = false,
    this.chrome,
  });
  final ImageRepository? images;
  final ChapterContent content;
  final String? runningTitle;
  final String? chapterTitle;
  final VoidCallback? onReady, onLoadFailure;

  /// Paper colour and page-turn style, so the host can match chapter and
  /// completion transitions to the page.
  final void Function(Color paper, PageTurnStyle turn)? onPageAppearance;
  final ReaderController? session;
  final ReaderPosition? initialPosition;
  final SettingsStore? settings;
  final ReaderActions actions;

  /// Whether headings recognised inside the article form their own layer.
  final bool articleContents;
  final BookTerminalState? completion;
  final PagedReaderController? viewportController;
  final bool returnToOrigin;

  /// Toolbar visibility, owned by the caller when it must outlive this view
  /// (e.g. so the screen can close the toolbars on back).
  final ValueNotifier<bool>? chrome;
  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

class _ReaderContentViewState extends State<ReaderContentView>
    with WidgetsBindingObserver {
  late final ReaderPreferences _preferences;
  ReaderSettings _settings = ReaderSettings();
  final _paperTurn = ValueNotifier<PageTurnFrame>(PageTurnFrame.rest);
  bool _completionTurning = false;
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
    _preferences = ReaderPreferences(widget.settings)..addListener(_changed);
    _position = widget.initialPosition;
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    await _preferences.load();
    if (!mounted) return;
    setState(() {
      _settingsReady = true;
      _hintVisible = !_settings.controlsHintSeen;
      _chrome.value = _hintVisible;
    });
    if (widget.session?.usedFallback == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
      unawaited(_preferences.flush());
      unawaited(widget.session?.flushProgress());
    }
  }

  Future<void> _settingsPanel(BuildContext context) =>
      showReaderSettings(context, _preferences);

  List<ReaderContentsLayer> _contentsLayers(BuildContext context) => [
    if (widget.articleContents)
      articleContentsLayer(
        context,
        widget.content,
        onSelect: (target) {
          if (!mounted) return;
          _position = target;
          _paged.restore(target);
        },
      ),
    if (_actions.bookContents case final book?) book(context),
  ];

  /// [book] opens on the book-level layer, e.g. from the completion page.
  Future<void> _contents(BuildContext context, {bool book = false}) async {
    final layers = _contentsLayers(context);
    if (layers.isEmpty) return;
    await showReaderContents(
      context,
      layers: layers,
      initialLayer: book ? layers.length - 1 : 0,
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
  Timer? _positionLabelTimer;
  bool _announcedReady = false;
  void _sample(ReaderPosition position, bool completed) {
    widget.session?.finishRestoringProgress();
    if ((widget.completion != null || _completionTurning) &&
        widget.session?.hasPendingNavigation != true) {
      return;
    }
    if (!_announcedReady) {
      _announcedReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onReady?.call();
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
  void _dimensions(MediaRef ref, Size size) {
    if (_sizes[ref] == size) return;
    _pendingSizes[ref] = size;
    if (!_dragging) _applySizes();
  }

  void _applySizes() {
    if (!mounted || _dragging || _pendingSizes.isEmpty) return;
    _position = _paged.capture();
    setState(() {
      _sizes.addAll(_pendingSizes);
      _pendingSizes.clear();
    });
  }

  void _toggle() => _chrome.value = !_chrome.value;

  void _leave(BuildContext context) {
    if (_actions.leave case final leave?) {
      leave();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _turnPage(bool forward, {bool queueIfTurning = true}) {
    if (_completionTurning || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    if (widget.completion != null) {
      if (!forward) _actions.completionPrevious?.call();
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

  void _forwardBoundary() => (_actions.nextChapter ?? _actions.bookEnd)?.call();
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
        ModalRoute.of(context)?.isCurrent == false) {
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
    _wheelCooldown?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _preferences.removeListener(_changed);
    _preferences.dispose();
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
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
    return LayoutBuilder(
      builder: (context, pageBounds) => Stack(
        fit: StackFit.expand,
        children: [
          Scaffold(
            body: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.f2): _toggle,
                const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                    _turnPage(true),
                const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                    _turnPage(false),
                const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                    _turnPage(true),
                const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                    _turnPage(false),
              },
              child: Focus(
                autofocus: true,
                child: ReaderCompletionTransition(
                  style: _settings.pageTurn,
                  onTurning: (value) => _completionTurning = value,
                  completion: widget.completion == null
                      ? null
                      : _completionPage(context, style),
                  child: SafeArea(
                    child: Stack(
                      fit: StackFit.expand,
                      // Toolbars paint into the safe-area insets.
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: _page(context, pageBounds, style),
                        ),
                        if (widget.completion == null)
                          ValueListenableBuilder<bool>(
                            valueListenable: _chrome,
                            builder: (context, visible, _) => ListenableBuilder(
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
                            child: ReaderControlsHint(onDismiss: _dismissHint),
                          ),
                      ],
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
    );
  }

  void _dismissHint() {
    setState(() => _hintVisible = false);
    _preferences.update(_settings.copyWith(controlsHintSeen: true));
    _preferences.flush();
  }

  Widget _completionPage(BuildContext context, TextStyle style) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      child: Listener(
        onPointerSignal: _scrollPage,
        child: ReaderCompletionPage(
          state: widget.completion!,
          title:
              widget.session?.progress?.snapshot.title ??
              widget.runningTitle ??
              widget.content.title,
          style: style,
          onPrevious: _actions.completionPrevious ?? () {},
          onExit: _actions.exitToShelf ?? () {},
          onCatalog: () => _contents(context, book: true),
          onRestart: _actions.restart ?? () {},
        ),
      ),
    ),
  );

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
    return Listener(
      onPointerSignal: _scrollPage,
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
    ({double height, double caption}) extent(ImageBlock block) =>
        readerImageExtent(
          block,
          width: bounds.maxWidth.clamp(0, readerMaxPageWidth),
          maxHeight: bounds.maxHeight,
          scaler: MediaQuery.textScalerOf(context),
          direction: Directionality.of(context),
          knownSize: _sizes[block.media],
        );
    Widget image(BuildContext context, ImageBlock block) {
      final geometry = extent(block);
      return SizedBox(
        height: geometry.height,
        child: widget.images == null
            ? _image(context, block)
            : ReaderImage(
                onTap: () => showReaderImagePreview(
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
        columns: columns,
        images: widget.images,
        content: widget.content,
        pageSize: pageBounds.biggest,
        contentOrigin: Offset(
          (pageBounds.maxWidth - bounds.maxWidth) / 2,
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
        onRestoreStart: widget.session?.restoringProgress,
        controller: _paged,
        onLink: _actions.contentLink,
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
      widget.chapterTitle ?? widget.content.title;

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
    widget.session?.beginPositionNavigation();
    _position = target;
    _paged.restore(target);
  }

  Future<void> _progressPanel(BuildContext context) => showReaderSheet<void>(
    context,
    builder: (sheet) => ReaderProgressPanel(
      chapterTitle: _effectiveChapterTitle,
      chapterFraction: _visibleChapterFraction,
      anchorFraction: _displayChapterFraction,
      bookFractionAt: (fraction) =>
          widget.session?.bookProgressAt(fraction)?.fraction,
      onSeek: _seekChapter,
      onDone: () => Navigator.of(sheet).pop(),
      showChapterStepper: _actions.hasChapterStepper,
      onPreviousChapter: _actions.previousChapter,
      onNextChapter: _actions.nextChapter,
    ),
  );

  /// Chapter progress text, rebuilt at most at the sampling rate.
  Widget _progressLabel(
    String Function(String percent) label, {
    TextStyle? style,
    StrutStyle? strut,
  }) => ValueListenableBuilder<ReaderPosition?>(
    valueListenable: _readingPosition,
    builder: (context, position, _) => Text(
      label(formatReadingPercent(_visibleChapterFraction)),
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

  List<(ReaderMenuAction, String)> _menu(AppLocalizations l) {
    final session = widget.session;
    final unsaved =
        session?.progressFailure != null ||
        session?.progress?.unsaved == true ||
        session?.restoreFailure != null;
    return [
      if (_actions.links != null) (ReaderMenuAction.links, l.readerLinks),
      if (_actions.prefetch != null)
        (ReaderMenuAction.prefetch, l.prefetchTitle),
      if (_actions.details != null)
        (ReaderMenuAction.details, l.novelDetailsTitle),
      if (unsaved)
        (
          ReaderMenuAction.retrySave,
          session?.restoreFailure != null
              ? l.readerRestoreReadFailed
              : l.readerProgressUnsaved,
        ),
      if (_preferences.failure != null)
        (ReaderMenuAction.retrySettings, l.readerSettingsFailure),
      (ReaderMenuAction.hideControls, l.hideReaderControls),
    ];
  }

  void _onMenu(BuildContext context, ReaderMenuAction action) {
    switch (action) {
      case ReaderMenuAction.links:
        _actions.links?.call(context);
      case ReaderMenuAction.prefetch:
        _actions.prefetch?.call();
      case ReaderMenuAction.details:
        _actions.details?.call();
      case ReaderMenuAction.retrySave:
        widget.session?.retryProgress();
      case ReaderMenuAction.retrySettings:
        _settingsPanel(context);
      case ReaderMenuAction.hideControls:
        _toggle();
    }
  }

  Widget _toolbars(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ReaderToolbars(
      metrics: ReaderChromeMetrics.of(context),
      insets: _pageInsets,
      top: ReaderTopBar(
        title: _effectiveChapterTitle,
        returnToOrigin: widget.returnToOrigin,
        onLeave: () => _leave(context),
        menu: _menu(l),
        onMenu: (action) => _onMenu(context, action),
      ),
      bottom: ReaderBottomBar(
        contentsTooltip:
            _contentsLayers(context).firstOrNull?.label ?? l.catalogTitle,
        onContents: () => _contents(context),
        progress: _progressLabel(l.readerChapterPercent),
        onProgress: () => _progressPanel(context),
        onSettings: () => _settingsPanel(context),
      ),
    );
  }
}
