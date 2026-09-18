import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/contracts/import_source.dart';

/// Native paths stay in data; DesktopImportSource stages the same durable batch
/// used by the picker. Listening enables drops, cancelling disables them.
Stream<List<XFile>> windowsDroppedFiles() =>
    const EventChannel('dev.shiori.reader/file_drop')
        .receiveBroadcastStream()
        .map((event) {
          if (event is! List ||
              event.any((path) => path is! String || !p.isAbsolute(path))) {
            throw const ImportSourceException(ImportProblem.unreadable);
          }
          return event
              .cast<String>()
              .map((path) => XFile(p.normalize(path)))
              .toList();
        })
        .handleError((Object error) {
          if (error is PlatformException) {
            throw ImportSourceException(
              error.code == 'batchLimit'
                  ? ImportProblem.batchLimit
                  : ImportProblem.unreadable,
            );
          }
          throw error;
        });
