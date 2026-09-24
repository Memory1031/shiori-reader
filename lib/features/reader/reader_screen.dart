import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/state_views.dart';
import 'reader_controller.dart';
import 'reader_completion_page.dart';
import 'reader_completion_transition.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';
import 'reading_progress_format.dart';
import 'reader_chrome.dart';
import 'reader_contents.dart';
import 'settings_panel.dart';
import 'reader_margin.dart';
import 'reader_image.dart';
import 'reader_image_preview.dart';
import 'epub_layout_page.dart';
import 'viewport/paged_reader_viewport.dart';
import 'viewport/paper_turn.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({
    super.key,
    required this.chapter,
    required this.repository,
    this.images,
    this.settings,
    this.library,
  });
  final SettingsStore? settings;
  final LibraryRepository? library;
  final ChapterKey chapter;
  final NovelRepository repository;
  final ImageRepository? images;

  @override
  Widget build(BuildContext context) => ControllerScope<ReaderController>(
    key: ValueKey((chapter, repository, library)),
    create: () => ReaderController(
      repository: repository,
      chapter: chapter,
      library: library,
    ),
    builder: (context, controller) {
      final strings = AppLocalizations.of(context);
      if (controller.status == ReaderStatus.ready) {
        return ReaderContentView(
          key: ValueKey(controller.restoreAttempt),
          content: controller.content!,
          images: images,
          settings: settings,
          session: controller,
          initialPosition: controller.initialPosition,
        );
      }
      return Scaffold(
        appBar: AppBar(title: Text(strings.readerTitle)),
        body: SafeArea(
          child: switch (controller.status) {
            ReaderStatus.loading => const LoadingView(),
            ReaderStatus.error => FailureView(
              failure: controller.failure!,
              onRetry: controller.load,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            ReaderStatus.cancelled => Center(
              child: TextButton(
                onPressed: controller.load,
                child: Text(strings.retryAction),
              ),
            ),
            ReaderStatus.ready => const SizedBox.shrink(),
          },
        ),
      );
    },
  );
}

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
    this.bookContents,
    this.articleContents = true,
    this.onPreviousChapter,
    this.onNextChapter,
    this.onBookEnd,
    this.completion,
    this.onCompletionPrevious,
    this.onCompletionExit,
    this.onRestart,
    this.onDetails,
    this.onPrefetch,
    this.onLinks,
    this.onContentLink,
    this.viewportController,
    this.returnToOrigin = false,
  });
  final ImageRepository? images;
  final ChapterContent content;
  final String? runningTitle;
  final String? chapterTitle;
  final VoidCallback? onReady, onLoadFailure;
  final ValueChanged<Color>? onPageAppearance;
  final ReaderController? session;
  final ReaderPosition? initialPosition;
  final SettingsStore? settings;

  /// The book-level navigation layer (volume catalog or local contents).
  final ReaderContentsLayer Function(BuildContext context)? bookContents;

  /// Whether headings recognised inside the article form their own layer.
  final bool articleContents;
  final VoidCallback? onPreviousChapter, onNextChapter;
  final VoidCallback? onBookEnd,
      onCompletionPrevious,
      onCompletionExit,
      onRestart;
  final BookTerminalState? completion;
  final VoidCallback? onDetails;
  final VoidCallback? onPrefetch;
  final void Function(BuildContext readerContext)? onLinks;
  final ValueChanged<LocalContentLink>? onContentLink;
  final PagedReaderController? viewportController;
  final bool returnToOrigin;
  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

class _ReaderContentViewState extends State<ReaderContentView>
    with WidgetsBindingObserver {
  late final ReaderPreferences _preferences;
  ReaderSettings _settings = ReaderSettings();
  final _paperTurn = ValueNotifier<(double, int)>((0, 1));
  bool _completionTurning = false;
  bool _settingsReady = false;
  bool _hintVisible = false;
  String? _failedPresentation;
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

  Future<void> _panel(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // The panel owns the handle so it follows live reading-theme changes.
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => FractionallySizedBox(
        heightFactor: .75,
        child: ReaderSettingsPanel(preferences: _preferences),
      ),
    );
    await _preferences.flush();
  }

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
    if (widget.bookContents case final book?) book(context),
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
  final _chrome = ValueNotifier(true);
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

  void _turnPage(bool forward, {bool queueIfTurning = true}) {
    if (_completionTurning || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    if (widget.completion != null) {
      if (!forward) widget.onCompletionPrevious?.call();
      return;
    }
    if (_usesPresentation) {
      if (forward) {
        _presentationNext();
      } else {
        widget.onPreviousChapter?.call();
      }
    } else {
      unawaited(
        forward
            ? _paged.next(queueIfTurning: queueIfTurning)
            : _paged.previous(queueIfTurning: queueIfTurning),
      );
    }
  }

  void _forwardBoundary() => (widget.onNextChapter ?? widget.onBookEnd)?.call();
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
    _chrome.dispose();
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
            padding: const EdgeInsets.all(12),
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

  Widget _body(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (!_settingsReady) {
      return const Scaffold(body: SafeArea(child: LoadingView()));
    }
    widget.onPageAppearance?.call(Theme.of(context).scaffoldBackgroundColor);
    final pageInsets = MediaQuery.paddingOf(context);
    _pageInsets = pageInsets;
    final chrome = ReaderChromeMetrics.of(context);
    final theme = Theme.of(context);
    final bodyTypography = ShioriCapabilities.of(context).explicitUiTypeface
        ? theme.textTheme.bodyLarge
        : null;
    final style = TextStyle(
      fontFamily: bodyTypography?.fontFamily,
      fontFamilyFallback: bodyTypography?.fontFamilyFallback,
      fontSize: _settings.fontSize,
      height: _settings.lineHeight,
      color: theme.colorScheme.onSurface,
    );
    final margin = readerHorizontalMargin(
      _settings,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
    _margin = margin;
    final prose = widget.content.blocks.whereType<ParagraphBlock>().any(
      (block) =>
          block.box == null &&
          block.alignment == ParagraphAlignment.start &&
          block.text.replaceAll('\uFFFC', '').trim().isNotEmpty,
    );
    bool spreadFor(BoxConstraints bounds) =>
        !_usesPresentation &&
        prose &&
        bounds.maxWidth - pageInsets.horizontal - 2 * margin >=
            2 * readerMinColumnWidth + readerColumnGap;
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
                  onTurning: (value) => _completionTurning = value,
                  completion: widget.completion == null
                      ? null
                      : ColoredBox(
                          color: theme.scaffoldBackgroundColor,
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
                                onPrevious:
                                    widget.onCompletionPrevious ?? () {},
                                onExit: widget.onCompletionExit ?? () {},
                                onCatalog: () => _contents(context, book: true),
                                onRestart: widget.onRestart ?? () {},
                              ),
                            ),
                          ),
                        ),
                  child: SafeArea(
                    child: Stack(
                      fit: StackFit.expand,
                      // Toolbars paint into the safe-area insets.
                      clipBehavior: Clip.none,
                      children: [
                        // Stable gutters keep showing/hiding controls from repaginating content.
                        Positioned.fill(
                          child: Listener(
                            onPointerSignal: _scrollPage,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                margin,
                                chrome.header,
                                margin,
                                chrome.footer,
                              ),
                              child: Align(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: spreadFor(pageBounds)
                                        ? 2 * readerMaxPageWidth +
                                              readerColumnGap
                                        : readerMaxPageWidth,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, bounds) {
                                      final maxHeight = bounds.maxHeight;
                                      ({double height, double caption}) extent(
                                        ImageBlock block,
                                      ) => readerImageExtent(
                                        block,
                                        width: bounds.maxWidth.clamp(
                                          0,
                                          readerMaxPageWidth,
                                        ),
                                        maxHeight: maxHeight,
                                        scaler: MediaQuery.textScalerOf(
                                          context,
                                        ),
                                        direction: Directionality.of(context),
                                        knownSize: _sizes[block.media],
                                      );
                                      Widget image(
                                        BuildContext context,
                                        ImageBlock block,
                                      ) {
                                        final geometry = extent(block);
                                        return SizedBox(
                                          height: geometry.height,
                                          child: widget.images == null
                                              ? _image(context, block)
                                              : ReaderImage(
                                                  onTap: () =>
                                                      showReaderImagePreview(
                                                        context,
                                                        block: block,
                                                        repository:
                                                            widget.images!,
                                                      ),
                                                  block: block,
                                                  repository: widget.images!,
                                                  captionHeight:
                                                      geometry.caption,
                                                  onIntrinsicSize: (size) {
                                                    if (block.width ==
                                                            size.width &&
                                                        block.height ==
                                                            size.height) {
                                                      return;
                                                    }
                                                    _dimensions(
                                                      block.media,
                                                      size,
                                                    );
                                                  },
                                                ),
                                        );
                                      }

                                      final presentation =
                                          widget.session?.pagePresentation;
                                      if (_usesPresentation) {
                                        return ExcludeSemantics(
                                          excluding: widget.completion != null,
                                          child: EpubLayoutPage(
                                            html: presentation!,
                                            links:
                                                widget.session?.contentLinks ??
                                                const [],
                                            onLink: widget.onContentLink,
                                            onFailed: () {
                                              if (mounted) {
                                                setState(
                                                  () => _failedPresentation =
                                                      presentation,
                                                );
                                              }
                                            },
                                            onCenterTap: _toggle,
                                            onPrevious:
                                                widget.onPreviousChapter,
                                            onNext: _presentationNext,
                                            onReady: () {
                                              final position =
                                                  _position ??
                                                  ReaderPosition(
                                                    contentRevision: widget
                                                        .content
                                                        .contentRevision,
                                                    blockKey: widget
                                                        .content
                                                        .blocks
                                                        .first
                                                        .blockKey,
                                                    blockIndex: 0,
                                                    blockFraction: 0,
                                                    chapterFraction: 0,
                                                  );
                                              _position = position;
                                              _sample(
                                                position,
                                                position.chapterFraction == 1,
                                              );
                                            },
                                          ),
                                        );
                                      }
                                      return ExcludeSemantics(
                                        excluding: widget.completion != null,
                                        child: PagedReaderViewport(
                                          columns: spreadFor(pageBounds)
                                              ? 2
                                              : 1,
                                          images: widget.images,
                                          content: widget.content,
                                          pageSize: pageBounds.biggest,
                                          contentOrigin: Offset(
                                            (pageBounds.maxWidth -
                                                    bounds.maxWidth) /
                                                2,
                                            pageInsets.top + chrome.header,
                                          ),
                                          onTurnVisual: (progress, direction) {
                                            _paperTurn.value = (
                                              progress,
                                              direction,
                                            );
                                          },
                                          startAtEnd:
                                              (widget.session?.startAtEnd ??
                                                  false) &&
                                              _position?.chapterFraction == 1 &&
                                              _position?.blockFraction == 1,
                                          onTurning: (turning) {
                                            _dragging = turning;
                                            if (!turning) {
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    if (mounted) {
                                                      _applySizes();
                                                    }
                                                  });
                                            }
                                          },
                                          onPosition: _sample,
                                          onRestoreStart:
                                              widget.session?.restoringProgress,
                                          controller: _paged,
                                          onLink: widget.onContentLink,
                                          contentLinks:
                                              widget.session?.contentLinks
                                                  .toList() ??
                                              const [],
                                          initialPosition: _position,
                                          textStyle: style,
                                          paragraphSpacing:
                                              _settings.paragraphSpacing,
                                          onCenterTap: _toggle,
                                          onBoundary: (direction) {
                                            if (direction > 0) {
                                              _forwardBoundary();
                                            } else {
                                              widget.onPreviousChapter?.call();
                                            }
                                          },
                                          imageBuilder: image,
                                          imageExtent: (block) =>
                                              extent(block).height,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: _chrome,
                          builder: (context, visible, _) => ListenableBuilder(
                            listenable: _preferences,
                            builder: (context, _) => widget.completion == null
                                ? _controls(context, visible)
                                : const SizedBox.shrink(),
                          ),
                        ),
                        if (_hintVisible && widget.completion == null)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: chrome.bottomBar + ShioriSpace.small,
                            child: Material(
                              elevation: 2,
                              borderRadius: BorderRadius.circular(
                                ShioriShape.control,
                              ),
                              color: Theme.of(context).colorScheme.surface,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.sizeOf(context).height * .4,
                                ),
                                child: SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(strings.readerControlsHint),
                                        TextButton(
                                          onPressed: () {
                                            setState(
                                              () => _hintVisible = false,
                                            );
                                            _preferences.update(
                                              _settings.copyWith(
                                                controlsHintSeen: true,
                                              ),
                                            );
                                            _preferences.flush();
                                          },
                                          child: Text(strings.readerGotIt),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<(double, int)>(
            valueListenable: _paperTurn,
            builder: (context, turn, _) => PaperTurnFold(
              progress: turn.$1,
              direction: turn.$2,
              paper: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
        ],
      ),
    );
  }

  String get _effectiveChapterTitle =>
      widget.chapterTitle ?? widget.content.title;

  Future<void> _progressPanel(BuildContext context) async {
    final l = AppLocalizations.of(context);
    var fraction = _visibleChapterFraction.clamp(0.0, 1.0);
    var bookFraction = _displayChapterFraction.clamp(0.0, 1.0);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.readerReadingProgress,
                      style: Theme.of(sheet).textTheme.titleLarge,
                    ),
                  ),
                  if (widget.session?.bookProgressAt(bookFraction)
                      case final book?)
                    Text(
                      '${formatReadingPercent(book.fraction)}%',
                      style: Theme.of(sheet).textTheme.titleMedium,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: _effectiveChapterTitle,
                      child: Text(
                        _effectiveChapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('${formatReadingPercent(fraction)}%'),
                ],
              ),
              Slider(
                value: fraction,
                onChanged: (v) => update(() {
                  fraction = v;
                  bookFraction = v;
                }),
                onChangeEnd: (v) {
                  final count = widget.content.blocks.length;
                  if (count == 0) return;
                  final scaled = v * count;
                  final index = scaled.floor().clamp(0, count - 1);
                  final target = ReaderPosition(
                    contentRevision: widget.content.contentRevision,
                    blockKey: widget.content.blocks[index].blockKey,
                    blockIndex: index,
                    blockFraction: (scaled - index).clamp(0.0, 1.0),
                    chapterFraction: v,
                  );
                  widget.session?.beginPositionNavigation();
                  _position = target;
                  _paged.restore(target);
                },
              ),
              if (widget.onPreviousChapter != null ||
                  widget.onNextChapter != null)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: widget.onPreviousChapter == null
                            ? null
                            : () {
                                Navigator.pop(sheet);
                                widget.onPreviousChapter!();
                              },
                        child: Text(l.previousChapter),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: widget.onNextChapter == null
                            ? null
                            : () {
                                Navigator.pop(sheet);
                                widget.onNextChapter!();
                              },
                        child: Text(l.nextChapter),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, bool visible) {
    final l = AppLocalizations.of(context);
    final chrome = ReaderChromeMetrics.of(context);
    if (!visible) {
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      final progress = ValueListenableBuilder<ReaderPosition?>(
        valueListenable: _readingPosition,
        builder: (context, position, _) => Text(
          l.readerChapterProgress(
            formatReadingPercent(_visibleChapterFraction),
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: muted),
        ),
      );
      return IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: _margin,
              right: _margin,
              height: chrome.header,
              child: Center(
                child: Text(
                  widget.runningTitle ?? widget.content.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            // With system bars hidden, the footer carries the clock and
            // battery; elsewhere it shows progress alone.
            Positioned(
              bottom: 0,
              left: _margin,
              right: _margin,
              height: chrome.footer,
              child: Center(
                child: ShioriCapabilities.of(context).immersiveSystemUi
                    ? ReaderStatusRow(progress: progress)
                    : progress,
              ),
            ),
          ],
        ),
      );
    }
    final failedRead = widget.session?.restoreFailure != null;
    final unsaved =
        widget.session?.progressFailure != null ||
        widget.session?.progress?.unsaved == true ||
        widget.session?.restoreFailure != null;
    // Bars bleed into the safe area so they read as one surface over the page.
    final insets = _pageInsets;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -insets.top,
          left: -insets.left,
          right: -insets.right,
          height: insets.top + chrome.topBar,
          child: ReaderToolbarSurface(
            edge: VerticalDirection.down,
            padding: EdgeInsets.fromLTRB(
              insets.left,
              insets.top,
              insets.right,
              0,
            ),
            child: Row(
              children: [
                if (widget.returnToOrigin)
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(l.readerLinkReturn),
                  )
                else
                  const BackButton(),
                Expanded(
                  child: Tooltip(
                    message: _effectiveChapterTitle,
                    child: Text(
                      _effectiveChapterTitle,
                      key: const ValueKey('reader-chapter-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: l.moreActions,
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) {
                    if (value == 'links') widget.onLinks?.call(context);
                    if (value == 'details') widget.onDetails?.call();
                    if (value == 'prefetch') widget.onPrefetch?.call();
                    if (value == 'hide') _toggle();
                    if (value == 'save') widget.session?.retryProgress();
                    if (value == 'settings') _panel(context);
                  },
                  itemBuilder: (_) => [
                    if (widget.onLinks != null)
                      PopupMenuItem(value: 'links', child: Text(l.readerLinks)),
                    if (widget.onPrefetch != null)
                      PopupMenuItem(
                        value: 'prefetch',
                        child: Text(l.prefetchTitle),
                      ),
                    if (widget.onDetails != null)
                      PopupMenuItem(
                        value: 'details',
                        child: Text(l.novelDetailsTitle),
                      ),
                    if (unsaved)
                      PopupMenuItem(
                        value: 'save',
                        child: Text(
                          failedRead
                              ? l.readerRestoreReadFailed
                              : l.readerProgressUnsaved,
                        ),
                      ),
                    if (_preferences.failure != null)
                      PopupMenuItem(
                        value: 'settings',
                        child: Text(l.readerSettingsFailure),
                      ),
                    PopupMenuItem(
                      value: 'hide',
                      child: Text(l.hideReaderControls),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: -insets.bottom,
          left: -insets.left,
          right: -insets.right,
          height: insets.bottom + chrome.bottomBar,
          child: ReaderToolbarSurface(
            edge: VerticalDirection.up,
            padding: EdgeInsets.fromLTRB(
              insets.left,
              0,
              insets.right,
              insets.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message:
                        _contentsLayers(context).firstOrNull?.label ??
                        l.catalogTitle,
                    child: TextButton.icon(
                      onPressed: () => _contents(context),
                      icon: const Icon(Icons.list, size: 20),
                      label: Text(l.catalogTitle),
                    ),
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<ReaderPosition?>(
                    valueListenable: _readingPosition,
                    builder: (context, position, _) => TextButton(
                      onPressed: () => _progressPanel(context),
                      child: Text(
                        l.readerChapterPercent(
                          formatReadingPercent(_visibleChapterFraction),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Tooltip(
                    message: l.readerSettings,
                    child: TextButton(
                      onPressed: () => _panel(context),
                      child: Text('Aa', semanticsLabel: l.readerSettings),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
