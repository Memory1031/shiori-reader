import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/production_app.dart';
import 'package:shiori/data/local/files/app_paths.dart';

class _Paths extends AppPaths {
  _Paths()
    : super(
        support: Directory('unused-startup-exit'),
        temporary: Directory('unused-startup-exit'),
        environment: StorageEnvironment.development,
      );
  bool prepared = false;
  @override
  Future<void> prepare() async {
    prepared = true;
    throw StateError('Storage must not open after exit starts');
  }
}

void main() {
  testWidgets(
    'exit joins startup and does not open storage after exit starts',
    (tester) async {
      final resolving = Completer<AppPaths>();
      final paths = _Paths();
      try {
        await tester.pumpWidget(
          ProductionApp(resolvePaths: () => resolving.future),
        );
        var closed = false;
        final closing = tester
            .widget<ShioriApp>(find.byType(ShioriApp))
            .shutdown!()
            .then((_) => closed = true);
        await tester.pump();
        expect(closed, isFalse, reason: 'Exit must await the in-flight opener');
        resolving.complete(paths);
        await tester.pump();
        await closing;
        expect(closed, isTrue);
        expect(paths.prepared, isFalse);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      } finally {
        if (!resolving.isCompleted) resolving.complete(paths);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
