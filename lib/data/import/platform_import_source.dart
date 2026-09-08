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
  String? _id, _path;
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
  Future<ImportCandidate?> pending() async {
    final value = await _call<Map<Object?, Object?>>('pending');
    if (value == null) return null;
    _id = value['id']! as String;
    _path = value['path'] as String?;
    return ImportCandidate(
      id: _id!,
      name: value['name'] as String? ?? '',
      size: value['size'] as int? ?? 0,
      error: value['error'] == null ? null : _problem(value['error'] as String),
    );
  }

  @override
  Stream<List<int>> read(ImportCandidate candidate) async* {
    if (_id != candidate.id || _path == null) {
      throw const ImportSourceException(ImportProblem.unreadable);
    }
    try {
      yield* File(_path!).openRead();
    } on FileSystemException {
      throw const ImportSourceException(ImportProblem.unreadable);
    }
  }

  @override
  Future<void> acknowledge(String id) async {
    await _call<void>('ack', {'id': id});
    if (_id == id) {
      _id = null;
      _path = null;
    }
  }

  @override
  Future<void> cancelCopy() => _call<void>('cancel');
  @override
  Future<void> close() async {
    await cancelCopy();
  }
}
