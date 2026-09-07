import 'package:flutter/material.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';
import 'reader_controller.dart';
import 'viewport/paged_reader_viewport.dart';
import 'viewport/reader_viewport.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({
    super.key,
    required this.chapter,
    required this.repository,
  });
  final ChapterKey chapter;
  final NovelRepository repository;

  @override
  Widget build(BuildContext context) => ControllerScope<ReaderController>(
    key: ValueKey((chapter, repository)),
    create: () => ReaderController(repository: repository, chapter: chapter),
    builder: (context, controller) {
      final strings = AppLocalizations.of(context);
      if (controller.status == ReaderStatus.ready) {
        return ReaderContentView(content: controller.content!);
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
/// Session-only mode selection; durable settings arrive in READER-004.
class ReaderContentView extends StatefulWidget {
  const ReaderContentView({super.key, required this.content});
  final ChapterContent content;
  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

class _ReaderContentViewState extends State<ReaderContentView> {
  final _paged = PagedReaderController();
  final _scroll = ReaderViewportController();
  final _chrome = ValueNotifier(true);
  bool _isPaged = true;
  ReaderPosition? _position;
  void _toggle() => _chrome.value = !_chrome.value;
  void _mode(bool paged) {
    if (paged == _isPaged) return;
    _position = _isPaged ? _paged.capture() : _scroll.capture();
    setState(() => _isPaged = paged);
  }

  @override
  void dispose() {
    _chrome.dispose();
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
    final strings = AppLocalizations.of(context);
    final style = TextStyle(
      fontSize: 20,
      height: 1.7,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Stable gutters keep showing/hiding controls from repaginating content.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 64),
                child: _isPaged
                    ? PagedReaderViewport(
                        content: widget.content,
                        controller: _paged,
                        initialPosition: _position,
                        textStyle: style,
                        onCenterTap: _toggle,
                        imageBuilder: _image,
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggle,
                        child: ReaderViewport(
                          content: widget.content,
                          controller: _scroll,
                          initialPosition: _position,
                          textStyle: style,
                          imageBuilder: (context, image) => SizedBox(
                            height: 180,
                            child: _image(context, image),
                          ),
                        ),
                      ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _chrome,
              builder: (context, visible, _) => visible
                  ? Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 56,
                          child: Material(
                            child: Row(
                              children: [
                                const BackButton(),
                                Expanded(
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      widget.content.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _toggle,
                                  tooltip: strings.hideReaderControls,
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
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  ChoiceChip(
                                    label: Text(strings.pagedReading),
                                    selected: _isPaged,
                                    onSelected: (_) => _mode(true),
                                  ),
                                  const SizedBox(width: 12),
                                  ChoiceChip(
                                    label: Text(strings.scrollReading),
                                    selected: !_isPaged,
                                    onSelected: (_) => _mode(false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        onPressed: _toggle,
                        tooltip: strings.showReaderControls,
                        icon: const Icon(Icons.expand_more),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
