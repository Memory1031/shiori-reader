import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../domain/contracts/cancellation.dart';
import '../../../domain/contracts/image_export.dart';
import 'image_export_operation.dart';

class NativeImageExportDestination implements ImageExportDestination {
  const NativeImageExportDestination({
    this.channel = const MethodChannel('dev.shiori.reader/image_export'),
  });
  final MethodChannel channel;
  @override
  Future<ImageExportResult> save(
    PreparedImageExport image, {
    required bool asFile,
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) return ImageExportResult.cancelled;
    // Per-operation id: a late cancellation cannot cancel a subsequent save.
    final id = image.name;
    final subscription = cancellation.whenCancelled.asStream().listen((_) {
      unawaited(
        channel
            .invokeMethod<void>('cancel', {'id': id})
            .catchError((Object _) {}),
      );
    });
    try {
      final value = await channel.invokeMethod<String>('save', {
        'id': id,
        'path': image.path,
        'name': image.name,
        'mime': image.mime,
        'size': image.byteLength,
        'asFile': asFile,
      });
      return ImageExportResult.values.firstWhere(
        (item) => item.name == value,
        orElse: () => ImageExportResult.unavailable,
      );
    } on MissingPluginException {
      return ImageExportResult.unavailable;
    } on PlatformException {
      return ImageExportResult.storageFailure;
    } finally {
      await subscription.cancel();
    }
  }
}

typedef ImageSaveLocation = Future<String?> Function(PreparedImageExport image);

class FileImageExportDestination implements ImageExportDestination {
  FileImageExportDestination({
    required this.protectedRoots,
    ImageSaveLocation? select,
  }) : select = select ?? _select;
  final List<Directory> protectedRoots;
  final ImageSaveLocation select;
  static Future<String?> _select(PreparedImageExport image) async =>
      (await getSaveLocation(
        suggestedName: image.name,
        acceptedTypeGroups: [
          XTypeGroup(
            label: image.mime,
            extensions: [imageEncoding(image.format).extension],
          ),
        ],
      ))?.path;

  @override
  Future<ImageExportResult> save(
    PreparedImageExport image, {
    required bool asFile,
    required CancellationToken cancellation,
  }) async {
    File? owned;
    try {
      if (cancellation.isCancelled) return ImageExportResult.cancelled;
      final path = await select(image);
      if (path == null || cancellation.isCancelled) {
        return ImageExportResult.cancelled;
      }
      // Resolve the parent to reject junctions/symlinks into managed storage.
      final parent = await Directory(p.dirname(path)).resolveSymbolicLinks();
      final target = File(p.join(parent, p.basename(path)));
      if (p.extension(path).toLowerCase() !=
          '.${imageEncoding(image.format).extension}') {
        return ImageExportResult.invalidFormat;
      }
      for (final root in [...protectedRoots, File(image.path).parent.parent]) {
        if (!await root.exists()) continue;
        final canonical = await root.resolveSymbolicLinks();
        if (p.equals(canonical, parent) || p.isWithin(canonical, target.path)) {
          return ImageExportResult.storageFailure;
        }
      }
      if (p.equals(
        await File(image.path).resolveSymbolicLinks(),
        target.path,
      )) {
        return ImageExportResult.storageFailure;
      }
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return ImageExportResult.destinationExists;
      }
      if (cancellation.isCancelled) return ImageExportResult.cancelled;
      // Exclusive creation refuses overwrite even if a file appeared after the
      // picker/check. Only this newly created file may be cleaned on failure.
      await target.create(exclusive: true);
      owned = target;
      final output = await target.open(mode: FileMode.writeOnly);
      try {
        await for (final chunk in File(image.path).openRead()) {
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      owned = null; // Commit: cancellation now cannot undo the user's copy.
      return ImageExportResult.savedFile;
    } catch (_) {
      return ImageExportResult.storageFailure;
    } finally {
      try {
        await owned?.delete();
      } catch (_) {}
    }
  }
}
