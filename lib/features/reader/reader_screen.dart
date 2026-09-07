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
import 'settings_panel.dart';
import 'reader_image.dart';
import 'viewport/paged_reader_viewport.dart';
import 'viewport/reader_viewport.dart';

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
    this.images,
    this.settings,
    this.session,
    this.initialPosition,
    this.onCatalog,
    this.onPreviousChapter,
    this.onNextChapter,
  });
  final ImageRepository? images;
  final ChapterContent content;
  final ReaderController? session;
  final ReaderPosition? initialPosition;
  final SettingsStore? settings;
  final VoidCallback? onCatalog, onPreviousChapter, onNextChapter;
  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

class _ReaderContentViewState extends State<ReaderContentView>
    with WidgetsBindingObserver {
  late final ReaderPreferences _preferences;
  ReaderSettings _settings = ReaderSettings();
  bool _settingsReady = false;
  bool _hintVisible = false;
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
    _position = (_isPaged ? _paged.capture() : _scroll.capture()) ?? _position;
    setState(() {
      _settings = _preferences.value;
      _isPaged = _settings.mode == ReaderMode.paged;
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

  final _paged = PagedReaderController();
  final _scroll = ReaderViewportController();
  final _chrome = ValueNotifier(true);
  final _readingPosition = ValueNotifier<ReaderPosition?>(null);
  void _sample(ReaderPosition position, bool completed) {
    _readingPosition.value = position;
    widget.session?.sampleProgress(position, completed);
  }

  bool _isPaged = true;
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
    _position = _isPaged ? _paged.capture() : _scroll.capture();
    setState(() {
      _sizes.addAll(_pendingSizes);
      _pendingSizes.clear();
    });
  }

  bool _notification(ScrollNotification event) {
    if (event is ScrollStartNotification && event.dragDetails != null) {
      _dragging = true;
    }
    if (event is ScrollEndNotification) {
      _dragging = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applySizes());
    }
    return false;
  }

  void _toggle() => _chrome.value = !_chrome.value;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferences.removeListener(_changed);
    _preferences.dispose();
    _chrome.dispose();
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
        data: readerTheme(_settings, MediaQuery.platformBrightnessOf(context)),
        child: Builder(builder: _body),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (!_settingsReady) {
      return const Scaffold(body: SafeArea(child: LoadingView()));
    }
    final style = TextStyle(
      fontSize: _settings.fontSize,
      height: _settings.lineHeight,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f2): _toggle,
          if (_isPaged)
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              _paged.next();
            },
          if (_isPaged)
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              _paged.previous();
            },
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Stack(
              children: [
                // Stable gutters keep showing/hiding controls from repaginating content.
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      _settings.horizontalPadding,
                      56,
                      _settings.horizontalPadding,
                      64,
                    ),
                    child: Align(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: LayoutBuilder(
                          builder: (context, bounds) {
                            final maxHeight =
                                bounds.maxHeight * (_isPaged ? 1 : 2);
                            ({double height, double caption}) extent(
                              ImageBlock block,
                            ) => readerImageExtent(
                              block,
                              width: bounds.maxWidth,
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

                            return NotificationListener<ScrollNotification>(
                              onNotification: _notification,
                              child: _isPaged
                                  ? PagedReaderViewport(
                                      content: widget.content,
                                      onPosition: _sample,
                                      onRestoreStart:
                                          widget.session?.restoringProgress,
                                      controller: _paged,
                                      initialPosition: _position,
                                      textStyle: style,
                                      paragraphSpacing:
                                          _settings.paragraphSpacing,
                                      onCenterTap: _toggle,
                                      imageBuilder: image,
                                      imageExtent: (block) =>
                                          extent(block).height,
                                    )
                                  : GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: _toggle,
                                      child: ReaderViewport(
                                        content: widget.content,
                                        onPosition: _sample,
                                        onRestoreStart:
                                            widget.session?.restoringProgress,
                                        controller: _scroll,
                                        initialPosition: _position,
                                        textStyle: style,
                                        paragraphSpacing:
                                            _settings.paragraphSpacing,
                                        imageBuilder: image,
                                      ),
                                    ),
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
                          maxHeight: MediaQuery.sizeOf(context).height * .4,
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
    );
  }

  Widget _controls(BuildContext context, bool visible) {
    final l = AppLocalizations.of(context);
    final failedRead = widget.session?.restoreFailure != null;
    final unsaved =
        widget.session?.progressFailure != null ||
        widget.session?.progress?.unsaved == true;
    final failedSettings = _preferences.failure != null;
    Widget status() => IconButton(
      onPressed: failedRead || unsaved
          ? widget.session?.retryProgress
          : () => _panel(context),
      tooltip: failedRead
          ? l.readerRestoreReadFailed
          : unsaved
          ? l.readerProgressUnsaved
          : l.readerSettingsFailure,
      icon: Icon(failedRead ? Icons.history : Icons.sync_problem),
    );
    if (!visible) {
      return Align(
        alignment: Alignment.topRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (failedRead || unsaved || failedSettings)
              Semantics(liveRegion: true, child: status()),
            IconButton(
              onPressed: _toggle,
              tooltip: l.showReaderControls,
              icon: const Icon(Icons.more_horiz),
            ),
          ],
        ),
      );
    }
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
                const BackButton(),
                if (widget.onCatalog != null)
                  IconButton(
                    onPressed: widget.onCatalog,
                    tooltip: l.catalogTitle,
                    icon: const Icon(Icons.list),
                  ),
                Expanded(
                  child: Text(
                    widget.content.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (failedRead || unsaved || failedSettings) status(),
                IconButton(
                  onPressed: () => _panel(context),
                  tooltip: l.readerSettings,
                  icon: const Icon(Icons.text_fields),
                ),
                IconButton(
                  onPressed: _toggle,
                  tooltip: l.hideReaderControls,
                  icon: const Icon(Icons.expand_less),
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
                if (widget.onCatalog != null)
                  IconButton(
                    onPressed: widget.onPreviousChapter,
                    tooltip: l.previousChapter,
                    icon: const Icon(Icons.skip_previous),
                  ),
                if (_isPaged)
                  IconButton(
                    onPressed: _paged.previous,
                    tooltip: l.readerPreviousPage,
                    icon: const Icon(Icons.chevron_left),
                  ),
                Expanded(
                  child: ValueListenableBuilder<ReaderPosition?>(
                    valueListenable: _readingPosition,
                    builder: (context, position, _) => Text(
                      l.readerChapterProgress(
                        ((position?.chapterFraction ?? 0) * 100).round(),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                if (_isPaged)
                  IconButton(
                    onPressed: _paged.next,
                    tooltip: l.readerNextPage,
                    icon: const Icon(Icons.chevron_right),
                  ),
                if (widget.onCatalog != null)
                  IconButton(
                    onPressed: widget.onNextChapter,
                    tooltip: l.nextChapter,
                    icon: const Icon(Icons.skip_next),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
