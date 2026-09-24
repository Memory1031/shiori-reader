import 'package:flutter/material.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../features/reader/reader_controller.dart';
import '../../features/reader/reader_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/controller_scope.dart';
import '../../shared/widgets/state_views.dart';

/// Development harness: one chapter session without the book-level screen
/// (catalog, chapter switching, completion). Production uses
/// BookReaderScreen.
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
