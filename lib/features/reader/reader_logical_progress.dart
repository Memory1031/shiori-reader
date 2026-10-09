import '../../domain/local_chapter_progress.dart';

/// One immutable metadata generation, shared by all chapter-progress surfaces.
final class ReaderLogicalProgress {
  const ReaderLogicalProgress({
    this.index,
    this.loading = false,
    required this.navigate,
  });
  final LocalChapterProgressIndex? index;
  final bool loading;
  final Future<void> Function(
    LocalChapterSection section,
    LocalChapterTarget target,
  )
  navigate;
}
