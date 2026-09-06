import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../domain/models/models.dart';
import '../l10n/generated/app_localizations.dart';
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
  const ReaderDestination(this.key);
  final ChapterKey key;
  @override
  String get routeName => '/reader';
}

/// Factories capture explicitly injected contracts at the composition root.
/// Missing features stay honest placeholders until their own implementation task.
class AppRoutes {
  const AppRoutes({this.home, this.search, this.novel, this.reader});

  final WidgetBuilder? home;
  final Widget Function(BuildContext, SourceId)? search;
  final Widget Function(BuildContext, NovelKey)? novel;
  final Widget Function(BuildContext, ChapterKey)? reader;

  Widget buildHome(BuildContext context) =>
      home?.call(context) ??
      AppScaffold(
        title: AppLocalizations.of(context).appTitle,
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
      ReaderDestination(:final key) =>
        reader?.call(context, key) ??
            _PendingPage(title: AppLocalizations.of(context).readerTitle),
    };
    // Route names deliberately exclude opaque IDs and potential site locators.
    final settings = RouteSettings(name: destination.routeName);
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => CupertinoPageRoute<void>(
        builder: builder,
        settings: settings,
      ),
      _ => MaterialPageRoute<void>(builder: builder, settings: settings),
    };
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
