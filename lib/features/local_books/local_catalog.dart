import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';

Future<LocalNavigationEntry?> openLocalCatalog(
  BuildContext context, {
  required NovelKey novel,
  required LocalNavigationRepository repository,
  ChapterKey? current,
}) {
  Widget builder(BuildContext context) => LocalCatalogScreen(
    novel: novel,
    repository: repository,
    current: current,
  );
  const settings = RouteSettings(name: '/local-catalog');
  return Navigator.of(context).push<LocalNavigationEntry>(
    Theme.of(context).platform == TargetPlatform.iOS
        ? CupertinoPageRoute(builder: builder, settings: settings)
        : MaterialPageRoute(builder: builder, settings: settings),
  );
}

class LocalCatalogScreen extends StatefulWidget {
  const LocalCatalogScreen({
    super.key,
    required this.novel,
    required this.repository,
    this.current,
  });
  final NovelKey novel;
  final LocalNavigationRepository repository;
  final ChapterKey? current;
  @override
  State<LocalCatalogScreen> createState() => _LocalCatalogScreenState();
}

class _LocalCatalogScreenState extends State<LocalCatalogScreen> {
  final _request = CancellationSource();
  late Future<Result<List<LocalNavigationEntry>>> _result = _load();
  Future<Result<List<LocalNavigationEntry>>> _load() => widget.repository
      .loadNavigation(widget.novel, cancellation: _request.token);
  @override
  void dispose() {
    _request.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).localBookContents)),
    body: SafeArea(
      child: FutureBuilder(
        future: _result,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LoadingView();
          final result = snapshot.data!;
          if (result case Failure(:final failure)) {
            return FailureView(
              failure: failure,
              onRetry: () => setState(() => _result = _load()),
            );
          }
          return LocalNavigationView(
            entries: (result as Success<List<LocalNavigationEntry>>).value,
            current: widget.current,
            onSelect: (target) => Navigator.pop(context, target),
          );
        },
      ),
    ),
  );
}

class LocalNavigationView extends StatelessWidget {
  const LocalNavigationView({
    super.key,
    required this.entries,
    required this.onSelect,
    this.current,
  });
  final List<LocalNavigationEntry> entries;
  final ValueChanged<LocalNavigationEntry> onSelect;
  final ChapterKey? current;
  @override
  Widget build(BuildContext context) {
    final rows = <(LocalNavigationEntry, int)>[];
    void flatten(List<LocalNavigationEntry> list, int depth) {
      for (final item in list) {
        rows.add((item, depth));
        flatten(item.children, depth + 1);
      }
    }

    flatten(entries, 0);
    if (rows.isEmpty) {
      return EmptyView(message: AppLocalizations.of(context).catalogEmpty);
    }
    Widget buildRow(BuildContext context, int index) {
      final (entry, depth) = rows[index];
      return ListTile(
        key: ValueKey(('local-toc', index)),
        contentPadding: EdgeInsetsDirectional.only(
          start: 16 + depth.clamp(0, 4) * 16,
          end: 16,
        ),
        selected: entry.chapterKey == current,
        leading: Icon(
          entry.chapterKey == current
              ? Icons.bookmark
              : entry.children.isEmpty
              ? Icons.article_outlined
              : Icons.folder_outlined,
        ),
        title: Text(entry.title, maxLines: 3, overflow: TextOverflow.ellipsis),
        onTap: () => onSelect(entry),
      );
    }

    final match = rows.indexWhere((row) => row.$1.chapterKey == current);
    final anchor = match < 0 ? 0 : match;
    const center = ValueKey('local-toc-anchor');
    // Start at the current chapter without measuring the unseen prefix. Rows
    // before the center grow upwards, retaining variable-height, lazy layout.
    return CustomScrollView(
      key: ValueKey((current, anchor)),
      center: center,
      semanticChildCount: rows.length,
      slivers: [
        if (anchor > 0)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => buildRow(context, anchor - index - 1),
              childCount: anchor,
              semanticIndexCallback: (_, index) => anchor - index - 1,
            ),
          ),
        SliverList(
          key: center,
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildRow(context, anchor + index),
            childCount: rows.length - anchor,
            semanticIndexOffset: anchor,
          ),
        ),
      ],
    );
  }
}
