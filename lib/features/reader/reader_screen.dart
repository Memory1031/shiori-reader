import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'reader_controller.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';
import 'article_contents.dart';
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
    this.onReady,
    this.onLoadFailure,
    this.onPageAppearance,
    this.images,
    this.settings,
    this.session,
    this.initialPosition,
    this.onCatalog,
    this.onPreviousChapter,
    this.onNextChapter,
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
  final VoidCallback? onReady, onLoadFailure;
  final ValueChanged<Color>? onPageAppearance;
  final ReaderController? session;
  final ReaderPosition? initialPosition;
  final SettingsStore? settings;
  final VoidCallback? onCatalog, onPreviousChapter, onNextChapter;
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

  Future<void> _contents(BuildContext context) async {
    if (widget.content.key.novelKey.sourceId == LocalBookIdentity.sourceId) {
      widget.onCatalog?.call();
      return;
    }
    final target = await showArticleContents(
      context,
      widget.content,
      onVolumes: widget.onCatalog,
    );
    if (!mounted || target == null) return;
    _position = target;
    _paged.restore(target);
  }

  late final _paged = widget.viewportController ?? PagedReaderController();
  final _chrome = ValueNotifier(true);
  final _readingPosition = ValueNotifier<ReaderPosition?>(null);
  ReaderPosition? _latestReadingPosition;
  Timer? _positionLabelTimer;
  bool _announcedReady = false;
  void _sample(ReaderPosition position, bool completed) {
    if (!_announcedReady) {
      _announcedReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onReady?.call();
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    _latestReadingPosition = position;
    // Display is bounded to 4Hz; persistence still receives every sample.
    _positionLabelTimer ??= Timer(const Duration(milliseconds: 250), () {
      _positionLabelTimer = null;
      _readingPosition.value = _latestReadingPosition;
    });
    widget.session?.sampleProgress(position, completed);
  }

  ReaderPosition? _position;
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
  @override
  void dispose() {
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
      value: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
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
    final theme = Theme.of(context);
    final bodyTypography = theme.platform == TargetPlatform.windows
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
                const SingleActivator(LogicalKeyboardKey.arrowRight): () {
                  if (_usesPresentation) {
                    widget.onNextChapter?.call();
                  } else {
                    _paged.next();
                  }
                },
                const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
                  if (_usesPresentation) {
                    widget.onPreviousChapter?.call();
                  } else {
                    _paged.previous();
                  }
                },
              },
              child: Focus(
                autofocus: true,
                child: SafeArea(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Stable gutters keep showing/hiding controls from repaginating content.
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(margin, 56, margin, 64),
                          child: Align(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: spreadFor(pageBounds)
                                    ? 2 * readerMaxPageWidth + readerColumnGap
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
                                    scaler: MediaQuery.textScalerOf(context),
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
                                                    repository: widget.images!,
                                                  ),
                                              block: block,
                                              repository: widget.images!,
                                              captionHeight: geometry.caption,
                                              onIntrinsicSize: (size) {
                                                if (block.width == size.width &&
                                                    block.height ==
                                                        size.height) {
                                                  return;
                                                }
                                                _dimensions(block.media, size);
                                              },
                                            ),
                                    );
                                  }

                                  final presentation =
                                      widget.session?.pagePresentation;
                                  if (_usesPresentation) {
                                    return EpubLayoutPage(
                                      html: presentation!,
                                      onFailed: () {
                                        if (mounted) {
                                          setState(
                                            () => _failedPresentation =
                                                presentation,
                                          );
                                        }
                                      },
                                      onCenterTap: _toggle,
                                      onPrevious: widget.onPreviousChapter,
                                      onNext: () {
                                        final last =
                                            widget.content.blocks.length - 1;
                                        _sample(
                                          ReaderPosition(
                                            contentRevision:
                                                widget.content.contentRevision,
                                            blockKey: widget
                                                .content
                                                .blocks[last]
                                                .blockKey,
                                            blockIndex: last,
                                            blockFraction: 1,
                                            chapterFraction: 1,
                                          ),
                                          true,
                                        );
                                        widget.onNextChapter?.call();
                                      },
                                      onReady: () {
                                        final position = ReaderPosition(
                                          contentRevision:
                                              widget.content.contentRevision,
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
                                        _sample(position, false);
                                      },
                                    );
                                  }
                                  return PagedReaderViewport(
                                    columns: spreadFor(pageBounds) ? 2 : 1,
                                    images: widget.images,
                                    content: widget.content,
                                    pageSize: pageBounds.biggest,
                                    contentOrigin: Offset(
                                      (pageBounds.maxWidth - bounds.maxWidth) /
                                          2,
                                      pageInsets.top + 56,
                                    ),
                                    onTurnVisual: (progress, direction) {
                                      _paperTurn.value = (progress, direction);
                                    },
                                    startAtEnd:
                                        (widget.session?.startAtEnd ?? false) &&
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
                                        widget.session?.contentLinks.toList() ??
                                        const [],
                                    initialPosition: _position,
                                    textStyle: style,
                                    paragraphSpacing:
                                        _settings.paragraphSpacing,
                                    onCenterTap: _toggle,
                                    onBoundary: (direction) {
                                      if (direction > 0) {
                                        widget.onNextChapter?.call();
                                      } else {
                                        widget.onPreviousChapter?.call();
                                      }
                                    },
                                    imageBuilder: image,
                                    imageExtent: (block) =>
                                        extent(block).height,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _chrome,
                        builder: (context, visible, _) => ListenableBuilder(
                          listenable: _preferences,
                          builder: (context, _) => _controls(context, visible),
                        ),
                      ),
                      if (_hintVisible)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 72,
                          child: Material(
                            elevation: 2,
                            borderRadius: BorderRadius.circular(12),
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
                                          setState(() => _hintVisible = false);
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

  Future<void> _progressPanel(BuildContext context) async {
    final l = AppLocalizations.of(context);
    var fraction = (_latestReadingPosition?.chapterFraction ?? 0).clamp(
      0.0,
      1.0,
    );
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.readerChapterProgress((fraction * 100).round())),
              Slider(
                value: fraction,
                onChanged: (v) => update(() => fraction = v),
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
                  _position = target;
                  _paged.restore(target);
                },
              ),
              if (widget.onCatalog != null)
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
    if (!visible) {
      return IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: readerHorizontalMargin(
                _settings,
                MediaQuery.textScalerOf(context),
                Directionality.of(context),
              ),
              right: readerHorizontalMargin(
                _settings,
                MediaQuery.textScalerOf(context),
                Directionality.of(context),
              ),
              height: 48,
              child: Center(
                child: Text(
                  widget.runningTitle ?? widget.content.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              child: ValueListenableBuilder<ReaderPosition?>(
                valueListenable: _readingPosition,
                builder: (context, position, _) => Text(
                  l.readerChapterProgress(
                    ((position ?? _position)?.chapterFraction ?? 0) * 100 ~/ 1,
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
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
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 56,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
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
                  child: Text(
                    widget.content.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
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
          bottom: 0,
          left: 0,
          right: 0,
          height: 64,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message:
                        widget.content.key.novelKey.sourceId ==
                            LocalBookIdentity.sourceId
                        ? l.localBookContents
                        : l.articleContents,
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
                        '${l.readerProgressLabel} ${((position?.chapterFraction ?? 0) * 100).round()}%',
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
