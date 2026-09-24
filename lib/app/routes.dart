import 'package:flutter/material.dart';

import '../domain/models/models.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/capabilities.dart';
import '../shared/widgets/app_scaffold.dart';
import '../shared/widgets/state_views.dart';

sealed class AppDestination {
  const AppDestination();
  String get routeName;
}

final class SearchDestination extends AppDestination {
  const SearchDestination(this.sourceId);
  final SourceId sourceId;
  @override
  String get routeName => '/search';
}

final class NovelDestination extends AppDestination {
  const NovelDestination(this.key);
  final NovelKey key;
  @override
  String get routeName => '/novel';
}

final class ReaderDestination extends AppDestination {
  const ReaderDestination(this.key, {this.blockKey});
  final String? blockKey;
  final ChapterKey key;
  @override
  String get routeName => '/reader';
}

final class ContinueDestination extends AppDestination {
  const ContinueDestination(this.key);
  final NovelKey key;
  @override
  String get routeName => '/continue';
}

/// Reads from the article cache only, without touching the network.
final class OfflineReaderDestination extends AppDestination {
  const OfflineReaderDestination(this.key);
  final ChapterKey key;
  @override
  String get routeName => '/offline-reader';
}

final class LocalBooksDestination extends AppDestination {
  const LocalBooksDestination();
  @override
  String get routeName => '/local-books';
}

final class CacheDestination extends AppDestination {
  const CacheDestination();
  @override
  String get routeName => '/cache';
}

/// Factories capture explicitly injected contracts at the composition root.
/// Missing features stay honest placeholders until their own implementation task.
class AppRoutes {
  const AppRoutes({
    this.home,
    this.search,
    this.novel,
    this.reader,
    this.readerTarget,
    this.continueReader,
    this.offlineReader,
    this.localBooks,
    this.cache,
  });

  final WidgetBuilder? home;
  final Widget Function(BuildContext, SourceId)? search;
  final Widget Function(BuildContext, NovelKey)? novel;
  final Widget Function(BuildContext, ChapterKey)? reader;
  final Widget Function(BuildContext, ChapterKey, String?)? readerTarget;
  final Widget Function(BuildContext, NovelKey)? continueReader;
  final Widget Function(BuildContext, ChapterKey)? offlineReader;
  final WidgetBuilder? localBooks, cache;

  Widget buildHome(BuildContext context, {VoidCallback? onAppearance}) =>
      home?.call(context) ??
      AppScaffold(
        title: AppLocalizations.of(context).appTitle,
        actions: [
          if (onAppearance != null)
            IconButton(
              onPressed: onAppearance,
              tooltip: AppLocalizations.of(context).appAppearance,
              icon: const Icon(Icons.palette_outlined),
            ),
        ],
        body: EmptyView(
          message: AppLocalizations.of(context).readingFeaturesPending,
        ),
      );

  Route<void> route(BuildContext context, AppDestination destination) {
    Widget builder(BuildContext context) => switch (destination) {
      SearchDestination(:final sourceId) =>
        search?.call(context, sourceId) ??
            _PendingPage(title: AppLocalizations.of(context).searchTitle),
      NovelDestination(:final key) =>
        novel?.call(context, key) ??
            _PendingPage(title: AppLocalizations.of(context).novelDetailsTitle),
      ReaderDestination(:final key, :final blockKey) =>
        readerTarget?.call(context, key, blockKey) ??
            reader?.call(context, key) ??
            _PendingPage(title: AppLocalizations.of(context).readerTitle),
      ContinueDestination(:final key) =>
        continueReader?.call(context, key) ??
            _PendingPage(title: AppLocalizations.of(context).readerTitle),
      OfflineReaderDestination(:final key) =>
        offlineReader?.call(context, key) ??
            _PendingPage(title: AppLocalizations.of(context).readerTitle),
      LocalBooksDestination() =>
        localBooks?.call(context) ??
            _PendingPage(title: AppLocalizations.of(context).localBooksTitle),
      CacheDestination() =>
        cache?.call(context) ??
            _PendingPage(title: AppLocalizations.of(context).cacheTitle),
    };
    // Route names deliberately exclude opaque IDs and potential site locators.
    final settings = RouteSettings(name: destination.routeName);
    return platformPageRoute<void>(
      context,
      builder: builder,
      settings: settings,
    );
  }

  Future<void> open(BuildContext context, AppDestination destination) async {
    await Navigator.of(context).push<void>(route(context, destination));
  }
}

class _PendingPage extends StatelessWidget {
  const _PendingPage({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => AppScaffold(
    title: title,
    body: EmptyView(message: AppLocalizations.of(context).featurePending),
  );
}
