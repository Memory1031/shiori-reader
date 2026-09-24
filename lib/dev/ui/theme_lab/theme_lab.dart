import 'package:flutter/material.dart';
import '../../../app/theme/shiori_theme.dart';
import '../../../domain/models/models.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../features/reader/reader_preferences.dart';
import '../../../features/reader/settings_panel.dart';
import '../../../features/reader/reader_theme.dart';
import '../../../features/reader/viewport/paged_reader_viewport.dart';
import '../../viewport/reader_viewport.dart';
import '../../fixture_scenarios.dart';
import 'lab_cover.dart';

enum LabState { content, longTitle, missing, empty, loading, error }

class ThemeLab extends StatefulWidget {
  const ThemeLab({super.key});
  @override
  State<ThemeLab> createState() => _ThemeLabState();
}

class _ThemeLabState extends State<ThemeLab> {
  bool _dark = false;
  Locale _locale = const Locale('zh');
  double _width = 390, _scale = 1;
  LabState _state = LabState.content;
  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    locale: _locale,
    child: Theme(
      data: shioriTheme(_dark ? Brightness.dark : Brightness.light),
      child: Builder(
        builder: (context) {
          final l = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text(l.labTitle),
              actions: [
                IconButton(
                  tooltip: l.labNight,
                  onPressed: () => setState(() => _dark = !_dark),
                  icon: Icon(
                    _dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _locale = Locale(
                      _locale.languageCode == 'zh' ? 'en' : 'zh',
                    ),
                  ),
                  child: const Text('中 / EN'),
                ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l.labNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      DropdownButton<LabState>(
                        value: _state,
                        items: [
                          for (final state in LabState.values)
                            DropdownMenuItem(
                              value: state,
                              child: Text(switch (state) {
                                LabState.content => l.labNormal,
                                LabState.longTitle => l.labLong,
                                LabState.missing => l.labMissing,
                                LabState.empty => l.labEmptyState,
                                LabState.loading => l.labLoading,
                                LabState.error => l.labError,
                              }),
                            ),
                        ],
                        onChanged: (v) => setState(() => _state = v!),
                      ),
                      const SizedBox(width: 24),
                      DropdownButton<double>(
                        value: _width,
                        hint: Text(l.labSize),
                        items: [
                          for (final w in [320.0, 390.0, 840.0])
                            DropdownMenuItem(
                              value: w,
                              child: Text('${l.labSize} ${w.toInt()}'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _width = v!),
                      ),
                      const SizedBox(width: 24),
                      DropdownButton<double>(
                        value: _scale,
                        items: [
                          for (final scale in [1.0, 1.3, 2.0])
                            DropdownMenuItem(
                              value: scale,
                              child: Text('${l.labScale} ×$scale'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _scale = v!),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < 3; index++)
                          Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: SizedBox(
                              width: _width,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          [
                                            l.labShelf,
                                            l.labDetail,
                                            l.labReader,
                                          ][index],
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: l.labFullscreen,
                                        icon: const Icon(
                                          Icons.open_in_full,
                                          size: 18,
                                        ),
                                        onPressed: () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => Localizations.override(
                                              context: context,
                                              locale: _locale,
                                              child: Theme(
                                                data: Theme.of(context),
                                                child: Builder(
                                                  builder: (context) => MediaQuery(
                                                    data: MediaQuery.of(context)
                                                        .copyWith(
                                                          textScaler:
                                                              TextScaler.linear(
                                                                _scale,
                                                              ),
                                                        ),
                                                    child: switch (index) {
                                                      0 => LabShelf(
                                                        state: _state,
                                                      ),
                                                      1 => LabDetail(
                                                        state: _state,
                                                      ),
                                                      _ => LabReader(
                                                        state: _state,
                                                      ),
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: MediaQuery(
                                        data: MediaQuery.of(context).copyWith(
                                          size: Size(
                                            _width,
                                            MediaQuery.sizeOf(context).height,
                                          ),
                                          padding: EdgeInsets.zero,
                                          textScaler: TextScaler.linear(_scale),
                                          platformBrightness: _dark
                                              ? Brightness.dark
                                              : Brightness.light,
                                        ),
                                        child: RepaintBoundary(
                                          key: ValueKey('lab-$index'),
                                          child: switch (index) {
                                            0 => LabShelf(state: _state),
                                            1 => LabDetail(state: _state),
                                            _ => LabReader(state: _state),
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

String bookTitle(AppLocalizations l, int i, LabState state) =>
    state == LabState.longTitle
    ? l.labLongTitle
    : [l.labBook1, l.labBook2, l.labBook3, l.labBook4][i % 4];
void previewAction(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).labPreviewAction)),
    );
Widget? stateBody(BuildContext context, LabState state, VoidCallback retry) {
  final l = AppLocalizations.of(context);
  if (state == LabState.loading) {
    return Center(
      child: SizedBox(
        width: 180,
        child: LinearProgressIndicator(semanticsLabel: l.labLoading),
      ),
    );
  }
  if (state == LabState.empty || state == LabState.error) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              state == LabState.empty
                  ? Icons.bookmark_border
                  : Icons.cloud_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              state == LabState.empty ? l.labEmpty : l.connectionFailureMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state == LabState.error
                  ? retry
                  : () => previewAction(context),
              child: Text(
                state == LabState.error ? l.retryAction : l.labSearch,
              ),
            ),
            if (state == LabState.empty)
              TextButton(
                onPressed: () => previewAction(context),
                child: Text(l.labImport),
              ),
          ],
        ),
      ),
    );
  }
  return null;
}

class LabShelf extends StatefulWidget {
  const LabShelf({super.key, required this.state});
  final LabState state;
  @override
  State<LabShelf> createState() => _LabShelfState();
}

class _LabShelfState extends State<LabShelf> {
  bool _retried = false;
  @override
  void didUpdateWidget(LabShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _retried = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shiori'),
        actions: [
          IconButton(
            tooltip: l.labSearch,
            onPressed: () => previewAction(context),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: l.labImport,
            onPressed: () => previewAction(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) => previewAction(context),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.bookmark_outline),
            selectedIcon: const Icon(Icons.bookmark),
            label: l.labShelf,
          ),
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            label: l.labDiscover,
          ),
        ],
      ),
      body:
          stateBody(
            context,
            _retried ? LabState.content : widget.state,
            () => setState(() => _retried = true),
          ) ??
          LayoutBuilder(
            builder: (context, bounds) {
              final count =
                  (bounds.maxWidth /
                          (MediaQuery.textScalerOf(context).scale(96) + 16))
                      .floor()
                      .clamp(2, 6);
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(ShioriSpace.page),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.labContinue, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 86,
                                child: ExcludeSemantics(
                                  child: LabCover(
                                    title: bookTitle(l, 0, widget.state),
                                    missing: widget.state == LabState.missing,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      bookTitle(l, 0, widget.state),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l.labChapter,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    Text(
                                      l.labProgress,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    TextButton(
                                      onPressed: () => previewAction(context),
                                      child: Text('${l.labContinue} →'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          Text(l.labMyBooks, style: theme.textTheme.titleLarge),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 20,
                        mainAxisExtent:
                            ((bounds.maxWidth - 40 - (count - 1) * 14) /
                                    count) *
                                1.5 +
                            MediaQuery.textScalerOf(context).scale(14) * 3 +
                            14,
                      ),
                      itemCount: 8,
                      itemBuilder: (context, i) => InkWell(
                        onTap: () => previewAction(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: LabCover(
                                title: bookTitle(l, i, widget.state),
                                index: i,
                                missing: widget.state == LabState.missing,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              bookTitle(l, i, widget.state),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }
}

class LabDetail extends StatefulWidget {
  const LabDetail({super.key, required this.state});
  final LabState state;
  @override
  State<LabDetail> createState() => _LabDetailState();
}

class _LabDetailState extends State<LabDetail> {
  bool _saved = false, _retried = false;
  @override
  void didUpdateWidget(LabDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _retried = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), theme = Theme.of(context);
    return Scaffold(
      body:
          stateBody(
            context,
            _retried ? LabState.content : widget.state,
            () => setState(() => _retried = true),
          ) ??
          ListView(
            children: [
              ColoredBox(
                color: theme.colorScheme.primary.withValues(alpha: .07),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: l.backAction,
                          onPressed: () => previewAction(context),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                      SizedBox(
                        width: 158,
                        child: ExcludeSemantics(
                          child: LabCover(
                            title: bookTitle(l, 0, widget.state),
                            missing: widget.state == LabState.missing,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        bookTitle(l, 0, widget.state),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(l.labAuthor, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: () => previewAction(context),
                      child: Text(l.labContinue),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _saved = !_saved),
                      icon: Icon(
                        _saved ? Icons.bookmark : Icons.bookmark_border,
                      ),
                      label: Text(_saved ? l.labSaved : l.labSave),
                    ),
                    const SizedBox(height: 24),
                    Text(l.labSynopsis, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 32),
                    Text(l.labCatalog, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.labChapter),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => previewAction(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}

class LabReader extends StatefulWidget {
  const LabReader({super.key, required this.state});
  final LabState state;
  @override
  State<LabReader> createState() => _LabReaderState();
}

class _LabReaderState extends State<LabReader> {
  final _paged = PagedReaderController();
  final _scroll = ReaderViewportController();
  final _preferences = ReaderPreferences(null);
  ReaderPosition? _position;
  bool _chrome = true, _retried = false;
  bool _wasPaged = true;
  @override
  void initState() {
    super.initState();
    _preferences.addListener(_changed);
  }

  void _changed() {
    _position = _wasPaged ? _paged.capture() : _scroll.capture();
    setState(() => _wasPaged = _preferences.value.mode == ReaderMode.paged);
  }

  @override
  void didUpdateWidget(LabReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _retried = false;
  }

  @override
  void dispose() {
    _preferences.removeListener(_changed);
    _preferences.dispose();
    super.dispose();
  }

  Future<void> _settings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .8,
      child: ReaderSettingsPanel(preferences: _preferences),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final brightness = switch (_preferences.value.themeMode) {
      ReaderThemeMode.system => Theme.of(context).brightness,
      ReaderThemeMode.light => Brightness.light,
      ReaderThemeMode.dark => Brightness.dark,
    };
    return Theme(
      data: readerTheme(_preferences.value, brightness),
      child: Builder(builder: _body),
    );
  }

  Widget _body(BuildContext context) {
    final l = AppLocalizations.of(context), settings = _preferences.value;
    final content = ChapterContent(
      key: fixtureChapterKey(FixtureScenario.typography),
      title: l.labChapter,
      blocks: [
        HeadingBlock(text: l.labChapter),
        for (var i = 0; i < 12; i++) ...[
          ParagraphBlock(text: l.labParagraph),
          if (i == 1)
            ImageBlock(
              media: fixtureMediaRef(0),
              width: 400,
              height: 260,
              alt: l.labIllustration,
            ),
        ],
      ],
    );
    final style = TextStyle(
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final state = stateBody(
      context,
      _retried ? LabState.content : widget.state,
      () => setState(() => _retried = true),
    );
    return Scaffold(
      body: SafeArea(
        child:
            state ??
            Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      settings.horizontalPadding,
                      60,
                      settings.horizontalPadding,
                      64,
                    ),
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        final imageHeight = (bounds.maxWidth * .65).clamp(
                          48.0,
                          bounds.maxHeight,
                        );
                        Widget illustration(
                          BuildContext context,
                          ImageBlock block,
                        ) => Semantics(
                          image: true,
                          label: l.labIllustration,
                          child: SizedBox(
                            height: imageHeight,
                            child: CustomPaint(painter: const CoverArtwork(0)),
                          ),
                        );
                        return _wasPaged
                            ? PagedReaderViewport(
                                content: content,
                                controller: _paged,
                                initialPosition: _position,
                                textStyle: style,
                                paragraphSpacing: settings.paragraphSpacing,
                                imageBuilder: illustration,
                                imageExtent: (_) => imageHeight,
                                onCenterTap: () =>
                                    setState(() => _chrome = !_chrome),
                              )
                            : GestureDetector(
                                onTap: () => setState(() => _chrome = !_chrome),
                                child: ReaderViewport(
                                  content: content,
                                  controller: _scroll,
                                  initialPosition: _position,
                                  textStyle: style,
                                  paragraphSpacing: settings.paragraphSpacing,
                                  imageBuilder: illustration,
                                ),
                              );
                      },
                    ),
                  ),
                ),
                if (_chrome) ...[
                  Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: l.backAction,
                            onPressed: () => previewAction(context),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          Expanded(
                            child: Text(
                              l.labChapter,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: l.hideReaderControls,
                            onPressed: () => setState(() => _chrome = false),
                            icon: const Icon(Icons.expand_less),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      height: 64,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            tooltip: l.labCatalog,
                            onPressed: () => previewAction(context),
                            icon: const Icon(Icons.format_list_bulleted),
                          ),
                          Expanded(
                            child: Text(
                              l.labNotice,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          IconButton(
                            tooltip: l.labSettings,
                            onPressed: _settings,
                            icon: const Icon(Icons.text_fields),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      tooltip: l.showReaderControls,
                      onPressed: () => setState(() => _chrome = true),
                      icon: const Icon(Icons.expand_more),
                    ),
                  ),
              ],
            ),
      ),
    );
  }
}
