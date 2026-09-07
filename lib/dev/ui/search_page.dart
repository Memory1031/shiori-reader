import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../features/search/search_screen.dart';
import '../../features/novel_detail/detail_screen.dart';
import '../../features/reader/book_reader_screen.dart';
import '../fixtures.dart';

/// Offline route composition; none of these fixtures are imported by release.
class DevSearchPage extends StatefulWidget {
  const DevSearchPage({super.key});

  @override
  State<DevSearchPage> createState() => _DevSearchPageState();
}

class _DevSearchPageState extends State<DevSearchPage> {
  final _environment = FixtureEnvironment();

  @override
  void dispose() {
    unawaited(_environment.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SearchScreen(
    repository: _environment.novels,
    sourceId: fixtureSourceId,
    routes: _routes,
  );
  late final AppRoutes _routes = AppRoutes(
    novel: (_, key) => DetailScreen(
      novel: key,
      repository: _environment.novels,
      images: _environment.images,
      onChapter: (chapter) => _routes.open(context, ReaderDestination(chapter)),
    ),
    reader: (_, key) => BookReaderScreen(
      chapter: key,
      repository: _environment.novels,
      images: _environment.images,
      library: _environment.library,
      settings: _environment.settings,
    ),
  );
}
