import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../domain/contracts/import_source.dart';

/// Desktop file selection and an application-owned, durable inbox.
/// The owner supplies an environment-specific directory and closes this source.
/// Use one instance per inbox within a process (POSIX locks are per-process).
class DesktopImportSource implements ImportSource {
  DesktopImportSource({
    required Directory inbox,
    Future<List<XFile>> Function()? selectFiles,
    Stream<List<XFile>>? droppedFiles,
    this.maxFiles = 64,
    this.maxFileBytes = 128 * 1024 * 1024,
    this.maxBatchBytes = 512 * 1024 * 1024,
  }) : _root = Directory(p.normalize(inbox.absolute.path)),
       _selectFiles = selectFiles ?? _openFiles,
       _droppedFiles = droppedFiles {
    if (maxFiles < 1 ||
        maxFiles > 64 ||
        maxFileBytes < 1 ||
        maxFileBytes > 128 * 1024 * 1024 ||
        maxBatchBytes < 1 ||
        maxBatchBytes > 512 * 1024 * 1024) {
      throw ArgumentError('Inbox limits must be within the supported bounds.');
    }
  }

  final Directory _root;
  final Future<List<XFile>> Function() _selectFiles;
  final Stream<List<XFile>>? _droppedFiles;
  StreamSubscription<List<XFile>>? _dropSubscription;
  final int maxFiles, maxFileBytes, maxBatchBytes;
  late final _events = StreamController<ImportSourceEvent>.broadcast(
    onListen: () {
      _dropSubscription ??= _droppedFiles?.listen(
        (files) => unawaited(_receiveDrop(files)),
        onError: _dropError,
      );
    },
  );
  final _random = Random.secure();
  Future<void> _tail = Future.value();
  Future<void>? _picking, _closing;
  Completer<void>? _cancellation;
  bool _closed = false;

  static const _uuid =
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  static final _itemName = RegExp('^item-[0-9]{4}-$_uuid\$');
  static final _trashName = RegExp('^ack-trash-$_uuid\$');
  static final _id = RegExp('^$_uuid\$');
  Directory get _pending => Directory(p.join(_root.path, 'pending'));
  Directory get _working => Directory(p.join(_root.path, 'working'));

  static Future<List<XFile>> _openFiles() => openFiles(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'TXT / EPUB', extensions: ['txt', 'epub']),
    ],
  );

  @override
  Stream<ImportSourceEvent> get changes => _events.stream;

  void _checkOpen() {
    if (_closed) throw StateError('Import source is closed.');
  }

  @override
  Future<void> pick() => _receive(_selectFiles);

  void _dropError(Object error) {
    if (_closed) return;
    _events.add(
      ImportSourceEvent(
        problem: error is ImportSourceException
            ? error.problem
            : ImportProblem.unreadable,
      ),
    );
  }

  Future<void> _receiveDrop(List<XFile> files) async {
    if (_closed || files.isEmpty) return;
    if (_picking != null) {
      _dropError(const ImportSourceException(ImportProblem.busy));
      return;
    }
    _events.add(const ImportSourceEvent(copiedBytes: 0));
    try {
      await _receive(() async => files);
    } catch (error) {
      if (error is! ImportSourceException ||
          error.problem != ImportProblem.cancelled) {
        _dropError(error);
      }
      if (!_closed) _events.add(const ImportSourceEvent(completed: true));
    }
  }

  Future<void> _receive(Future<List<XFile>> Function() selectFiles) {
    _checkOpen();
    if (_picking != null) {
      return Future.error(const ImportSourceException(ImportProblem.busy));
    }
    final cancellation = _cancellation = Completer<void>();
    return _picking = _pick(cancellation, selectFiles).whenComplete(() {
      _picking = null;
      _cancellation = null;
    });
  }

  Future<void> _pick(
    Completer<void> cancellation,
    Future<List<XFile>> Function() selectFiles,
  ) async {
    void checkCancelled() {
      if (cancellation.isCompleted) {
        throw const ImportSourceException(ImportProblem.cancelled);
      }
    }

    await _locked(() async {
      await _recover();
      if ((await _inspect()).isNotEmpty) {
        throw const ImportSourceException(ImportProblem.busy);
      }
    });
    checkCancelled();
    final List<XFile> files;
    try {
      // The OS dialog cannot be dismissed by file_selector. Stop waiting on
      // cancellation and ignore any later selection, without starting a copy.
      files = await Future.any([
        selectFiles(),
        cancellation.future.then<List<XFile>>((_) {
          throw const ImportSourceException(ImportProblem.cancelled);
        }),
      ]);
    } on ImportSourceException {
      rethrow;
    } catch (_) {
      throw const ImportSourceException(ImportProblem.unreadable);
    }
    checkCancelled();
    if (files.isEmpty) return; // User dismissed the picker.
    await _locked(() async {
      checkCancelled();
      await _recover();
      if ((await _inspect()).isNotEmpty) {
        throw const ImportSourceException(ImportProblem.busy);
      }
      if (files.length > maxFiles) {
        throw const ImportSourceException(ImportProblem.batchLimit);
      }
      // Validate every input before opening any payload stream.
      var declared = 0;
      for (final file in files) {
        checkCancelled();
        _validateName(file.name);
        final int size;
        try {
          size = await file.length();
        } catch (_) {
          throw const ImportSourceException(ImportProblem.unreadable);
        }
        checkCancelled();
        if (size > maxFileBytes) {
          throw const ImportSourceException(ImportProblem.tooLarge);
        }
        if (size <= 0) {
          throw const ImportSourceException(ImportProblem.unreadable);
        }
        declared += size;
      }
      // The copy still counts actual bytes: a file can grow after length().
      if (declared > maxBatchBytes) {
        throw const ImportSourceException(ImportProblem.batchLimit);
      }
      await _working.create();
      try {
        var total = 0;
        var reported = 0;
        for (var order = 0; order < files.length; order++) {
          checkCancelled();
          final file = files[order];
          final id = _newId();
          final item = Directory(
            p.join(
              _working.path,
              'item-${order.toString().padLeft(4, '0')}-$id',
            ),
          );
          await item.create();
          final output = await File(
            p.join(item.path, 'payload'),
          ).open(mode: FileMode.write);
          StreamIterator<List<int>>? input;
          var size = 0;
          try {
            try {
              input = StreamIterator(file.openRead());
            } catch (_) {
              throw const ImportSourceException(ImportProblem.unreadable);
            }
            while (true) {
              checkCancelled();
              final bool more;
              try {
                more = await Future.any([
                  input.moveNext(),
                  cancellation.future.then((_) => false),
                ]);
              } catch (_) {
                throw const ImportSourceException(ImportProblem.unreadable);
              }
              checkCancelled();
              if (!more) break;
              final bytes = input.current;
              size += bytes.length;
              total += bytes.length;
              if (size > maxFileBytes) {
                throw const ImportSourceException(ImportProblem.tooLarge);
              }
              if (total > maxBatchBytes) {
                throw const ImportSourceException(ImportProblem.batchLimit);
              }
              await output.writeFrom(bytes);
              if (total - reported >= 1024 * 1024) {
                _events.add(ImportSourceEvent(copiedBytes: total));
                reported = total;
              }
            }
            if (size == 0) {
              throw const ImportSourceException(ImportProblem.unreadable);
            }
            await output.flush();
          } finally {
            try {
              await input?.cancel();
            } finally {
              await output.close();
            }
          }
          final metadata = utf8.encode(
            jsonEncode({
              'id': id,
              'name': file.name,
              'size': size,
              'order': order,
            }),
          );
          if (metadata.length > 64 * 1024) {
            throw const ImportSourceException(ImportProblem.unreadable);
          }
          await File(
            p.join(item.path, 'receipt.json'),
          ).writeAsBytes(metadata, flush: true);
        }
        checkCancelled();
        await _working.rename(_pending.path);
        // After publication pending belongs to the consumer, even if cancelled.
        _events.add(const ImportSourceEvent(completed: true));
      } finally {
        await _deleteOwned(_working);
      }
    });
  }

  @override
  Future<List<ImportCandidate>> pending() {
    _checkOpen();
    return _locked(() async {
      await _recover();
      return List.unmodifiable((await _inspect()).map((r) => r.candidate));
    });
  }

  @override
  Stream<List<int>> read(ImportCandidate candidate) async* {
    _checkOpen();
    // Resolve opaque IDs through validated receipts, never through a path join.
    final payload = await _locked(() async {
      final receipts = await _inspect();
      for (final receipt in receipts) {
        if (receipt.candidate.id == candidate.id) {
          return File(p.join(receipt.directory.path, 'payload'));
        }
      }
      throw const ImportSourceException(ImportProblem.unreadable);
    });
    try {
      yield* payload.openRead();
    } on FileSystemException {
      throw const ImportSourceException(ImportProblem.unreadable);
    }
  }

  @override
  Future<void> acknowledge(String id) {
    _checkOpen();
    return _locked(() async {
      await _recover();
      for (final receipt in await _inspect()) {
        if (receipt.candidate.id != id) continue;
        final trash = await receipt.directory.rename(
          p.join(_root.path, 'ack-trash-${_newId()}'),
        );
        // Detaching the item is the commit point. Trash cleanup is recoverable.
        try {
          await _deleteOwned(trash);
          await _removeEmptyPending();
        } on FileSystemException {
          // Retry on the next inbox access.
        }
        return;
      }
    });
  }

  @override
  Future<void> cancelCopy() async {
    final cancellation = _cancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    try {
      await _picking;
    } on ImportSourceException catch (error) {
      if (error.problem == ImportProblem.storage) rethrow;
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    try {
      await _dropSubscription?.cancel();
      await cancelCopy();
      await _tail;
    } finally {
      await _events.close();
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _tail.then((_) async {
      try {
        await _root.create(recursive: true);
        await _requireType(_root, FileSystemEntityType.directory);
        final lockFile = File(p.join(_root.path, 'lock'));
        final type = await FileSystemEntity.type(
          lockFile.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound) {
          await _requireType(lockFile, FileSystemEntityType.file);
        }
        final handle = await lockFile.open(mode: FileMode.append);
        try {
          try {
            await handle.lock(FileLock.exclusive, 0, 1);
          } on FileSystemException {
            throw const ImportSourceException(ImportProblem.busy);
          }
          try {
            return await action();
          } finally {
            await handle.unlock(0, 1);
          }
        } finally {
          await handle.close();
        }
      } on FileSystemException {
        throw const ImportSourceException(ImportProblem.storage);
      } on FormatException {
        throw const ImportSourceException(ImportProblem.storage);
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _recover() async {
    await _deleteOwned(_working);
    await for (final entry in _root.list(followLinks: false)) {
      if (_trashName.hasMatch(p.basename(entry.path))) {
        await _deleteOwned(entry);
      }
    }
    await _removeEmptyPending();
  }

  Future<void> _removeEmptyPending() async {
    if (await FileSystemEntity.type(_pending.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    await _requireType(_pending, FileSystemEntityType.directory);
    if (await _pending.list(followLinks: false).isEmpty) {
      await _pending.delete();
    }
  }

  Future<List<_Receipt>> _inspect() async {
    if (await FileSystemEntity.type(_pending.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return [];
    }
    await _requireType(_pending, FileSystemEntityType.directory);
    final receipts = <_Receipt>[];
    final ids = <String>{};
    final orders = <int>{};
    var total = 0;
    await for (final entry in _pending.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (!_itemName.hasMatch(name) || receipts.length >= maxFiles) _corrupt();
      await _requireType(entry, FileSystemEntityType.directory);
      final metadata = File(p.join(entry.path, 'receipt.json'));
      final payload = File(p.join(entry.path, 'payload'));
      await _requireType(metadata, FileSystemEntityType.file);
      await _requireType(payload, FileSystemEntityType.file);
      if (await metadata.length() > 64 * 1024) _corrupt();
      final value = jsonDecode(await metadata.readAsString());
      if (value is! Map<String, dynamic>) _corrupt();
      final id = value['id'], displayName = value['name'];
      final size = value['size'], order = value['order'];
      if (id is! String ||
          !_id.hasMatch(id) ||
          !ids.add(id) ||
          displayName is! String ||
          !_supportedName(displayName) ||
          size is! int ||
          size <= 0 ||
          size > maxFileBytes ||
          order is! int ||
          order < 0 ||
          order >= maxFiles ||
          !orders.add(order)) {
        _corrupt();
      }
      if (name != 'item-${order.toString().padLeft(4, '0')}-$id' ||
          await payload.length() != size) {
        _corrupt();
      }
      total += size;
      if (total > maxBatchBytes) _corrupt();
      receipts.add(
        _Receipt(
          Directory(entry.path),
          ImportCandidate(id: id, name: displayName, size: size),
          order,
        ),
      );
    }
    receipts.sort((a, b) => a.order.compareTo(b.order));
    return receipts;
  }

  static Never _corrupt() =>
      throw const ImportSourceException(ImportProblem.storage);

  Future<void> _requireType(
    FileSystemEntity entry,
    FileSystemEntityType type,
  ) async {
    if (await FileSystemEntity.type(entry.path, followLinks: false) != type) {
      _corrupt();
    }
  }

  Future<void> _deleteOwned(FileSystemEntity entry) async {
    final name = p.basename(entry.path);
    if (!p.equals(p.dirname(entry.path), _root.path) ||
        (name != 'working' && !_trashName.hasMatch(name))) {
      _corrupt();
    }
    final type = await FileSystemEntity.type(entry.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) _corrupt();
    final resolvedRoot = await _root.resolveSymbolicLinks();
    final resolvedEntry = await entry.resolveSymbolicLinks();
    if (!p.equals(p.dirname(resolvedEntry), resolvedRoot)) _corrupt();
    // Dart's recursive directory deletion unlinks nested links without following
    // them. Only a verified inbox staging/trash directory reaches this operation.
    await Directory(resolvedEntry).delete(recursive: true);
  }

  static bool _supportedName(String name) =>
      name.isNotEmpty &&
      !name.contains(RegExp(r'[/\\\x00]')) &&
      ['.txt', '.epub'].contains(p.extension(name).toLowerCase());

  static void _validateName(String name) {
    if (!_supportedName(name)) {
      throw const ImportSourceException(ImportProblem.unsupported);
    }
  }

  String _newId() {
    final bytes = List.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

final class _Receipt {
  const _Receipt(this.directory, this.candidate, this.order);
  final Directory directory;
  final ImportCandidate candidate;
  final int order;
}
