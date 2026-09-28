import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../domain/contracts/contracts.dart';
import '../../../domain/contracts/image_export.dart';
import '../../../domain/models/models.dart';
import '../media_format.dart';

const imageExportMaxBytes = 20 * 1024 * 1024;

/// The operation owns this file until the destination's real completion.
class PreparedImageExport {
  const PreparedImageExport({
    required this.path,
    required this.name,
    required this.format,
    required this.byteLength,
  });
  final String path, name;
  final MediaFormat format;
  final int byteLength;
  String get mime => imageEncoding(format).mime;
}

({String extension, String mime}) imageEncoding(MediaFormat format) =>
    switch (format) {
      MediaFormat.jpeg => (extension: 'jpg', mime: 'image/jpeg'),
      MediaFormat.png => (extension: 'png', mime: 'image/png'),
      MediaFormat.gif => (extension: 'gif', mime: 'image/gif'),
      MediaFormat.webp => (extension: 'webp', mime: 'image/webp'),
      MediaFormat.avif => (extension: 'avif', mime: 'image/avif'),
      MediaFormat.unknown => throw const FormatException(),
    };

abstract interface class ImageExportDestination {
  /// Cancellation before submission prevents UI/writes. Once committed, wait
  /// for the actual result; never complete early while native still reads path.
  Future<ImageExportResult> save(
    PreparedImageExport image, {
    required bool asFile,
    required CancellationToken cancellation,
  });
}

class ImageExportOperation implements ImageExporter {
  ImageExportOperation({required this.stagingRoot, required this.destination});
  final Future<Directory> Function() stagingRoot;
  final ImageExportDestination destination;

  @override
  Future<ImageExportResult> save({
    required ImageRepository repository,
    required MediaRef media,
    required CancellationToken cancellation,
    bool asFile = false,
  }) async {
    MediaLease? lease;
    Directory? owned;
    var submitted = false;
    try {
      if (cancellation.isCancelled) return ImageExportResult.cancelled;
      final loaded = await repository.load(
        media,
        mode: ReadMode.cacheFirst,
        cancellation: cancellation,
      );
      if (loaded case Failure(:final failure)) {
        return failure.isCancellation || cancellation.isCancelled
            ? ImageExportResult.cancelled
            : ImageExportResult.sourceUnavailable;
      }
      lease = (loaded as Success<LoadResult<MediaLease>>).value.value;
      if (cancellation.isCancelled) return ImageExportResult.cancelled;
      final root = await stagingRoot();
      await root.create(recursive: true);
      owned = await Directory(
        await root.resolveSymbolicLinks(),
      ).createTemp('export-');
      final data = lease.data;
      final file = File(p.join(owned.path, 'original'));
      final output = await file.open(mode: FileMode.writeOnly);
      var size = 0;
      final header = BytesBuilder(copy: false);
      try {
        final stream = switch (data) {
          MemoryMedia(:final bytes) => _chunks(bytes),
          LocalMedia(:final path) => File(path).openRead(),
        };
        await for (final chunk in stream) {
          if (cancellation.isCancelled) return ImageExportResult.cancelled;
          size += chunk.length;
          if (size > imageExportMaxBytes) {
            return ImageExportResult.invalidFormat;
          }
          if (header.length < 4096) {
            header.add(
              chunk.sublist(0, min(chunk.length, 4096 - header.length)),
            );
          }
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      final format = detectMediaFormat(header.takeBytes());
      if (size == 0 ||
          format == MediaFormat.unknown ||
          (data.info.byteLength != null && data.info.byteLength != size) ||
          (data.info.format != MediaFormat.unknown &&
              data.info.format != format)) {
        return ImageExportResult.invalidFormat;
      }
      if (cancellation.isCancelled) return ImageExportResult.cancelled;
      final id = List.generate(
        6,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final name =
          'shiori-$id-${DateTime.now().millisecondsSinceEpoch}.${imageEncoding(format).extension}';
      final prepared = await file.rename(p.join(owned.path, name));
      if (cancellation.isCancelled) return ImageExportResult.cancelled;
      submitted = true;
      return await destination.save(
        PreparedImageExport(
          path: prepared.path,
          name: name,
          format: format,
          byteLength: size,
        ),
        asFile: asFile,
        cancellation: cancellation,
      );
    } catch (_) {
      return !submitted && cancellation.isCancelled
          ? ImageExportResult.cancelled
          : ImageExportResult.storageFailure;
    } finally {
      await lease?.close();
      // Cleanup failure must not turn an already committed save into failure.
      try {
        await owned?.delete(recursive: true);
      } catch (_) {}
    }
  }

  Stream<List<int>> _chunks(Uint8List bytes) async* {
    for (var offset = 0; offset < bytes.length; offset += 64 * 1024) {
      yield Uint8List.sublistView(
        bytes,
        offset,
        min(offset + 64 * 1024, bytes.length),
      );
    }
  }
}
