import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../domain/contracts/import_source.dart';

/// Only this adapter sees the application-owned native inbox path.
class PlatformImportSource implements ImportSource {
  PlatformImportSource({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel('dev.shiori.reader/import'),
      _events = events ?? const EventChannel('dev.shiori.reader/import_events');
  final MethodChannel _channel;
  final EventChannel _events;
  // Android and iOS return ordered lists; legacy map/null remains readable.
  // Paths stay in this adapter, bound independently to each opaque receipt id.
  final _paths = <String, String>{};
  @override
  late final Stream<ImportSourceEvent> changes = _events
      .receiveBroadcastStream()
      .map((event) {
        final value = event as Map;
        return ImportSourceEvent(
          copiedBytes: value['bytes'] as int?,
          completed: value['done'] == true,
          problem: value['error'] == null
              ? null
              : _problem(value['error'] as String),
        );
      });
  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw ImportSourceException(_problem(e.code));
    }
  }

  static ImportProblem _problem(String? code) =>
      ImportProblem.values.firstWhere(
        (p) => p.name == code,
        orElse: () => ImportProblem.unreadable,
      );
  @override
  Future<void> pick() => _call<void>('pick');
  @override
  Future<List<ImportCandidate>> pending() async {
    final response = await _call<Object?>('pending');
    final List<Object?> values = switch (response) {
      null => const [],
      Map<Object?, Object?> value => [value],
      List<Object?> values => values,
      _ => throw const ImportSourceException(ImportProblem.storage),
    };
    final nextCandidates = <ImportCandidate>[];
    final nextPaths = <String, String>{};
    final ids = <String>{};
    for (final value in values) {
      if (value is! Map<Object?, Object?>) {
        throw const ImportSourceException(ImportProblem.storage);
      }
      final id = value['id'];
      final name = value['name'];
      final size = value['size'];
      final path = value['path'];
      final error = value['error'];
      if (id is! String ||
          id.isEmpty ||
          !ids.add(id) ||
          name is! String ||
          size is! int ||
          size < 0 ||
          (error != null && error is! String) ||
          (path != null && (path is! String || path.isEmpty)) ||
          (error == null && path == null)) {
        throw const ImportSourceException(ImportProblem.storage);
      }
      if (path is String) nextPaths[id] = path;
      nextCandidates.add(
        ImportCandidate(
          id: id,
          name: name,
          size: size,
          error: error == null ? null : _problem(error as String),
        ),
      );
    }
    // A malformed later item must not replace even part of the old bindings.
    _paths
      ..clear()
      ..addAll(nextPaths);
    return List.unmodifiable(nextCandidates);
  }

  @override
  Stream<List<int>> read(ImportCandidate candidate) async* {
    final path = _paths[candidate.id];
    if (path == null) {
      throw const ImportSourceException(ImportProblem.unreadable);
    }
    try {
      yield* File(path).openRead();
    } on FileSystemException {
      throw const ImportSourceException(ImportProblem.unreadable);
    }
  }

  @override
  Future<void> acknowledge(String id) async {
    await _call<void>('ack', {'id': id});
    _paths.remove(id);
  }

  @override
  Future<void> cancelCopy() => _call<void>('cancel');
  @override
  Future<void> close() async {
    await cancelCopy();
  }
}
