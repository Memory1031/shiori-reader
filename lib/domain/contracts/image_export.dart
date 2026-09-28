import '../models/models.dart';
import 'cancellation.dart';
import 'media.dart';

/// Success names describe the destination actually committed by the platform.
enum ImageExportResult {
  savedPhotos,
  savedFile,
  cancelled,
  permissionDenied,
  unsupportedFormat,
  invalidFormat,
  storageFailure,
  sourceUnavailable,
  destinationExists,
  unavailable,
}

abstract interface class ImageExporter {
  Future<ImageExportResult> save({
    required ImageRepository repository,
    required MediaRef media,
    required CancellationToken cancellation,
    bool asFile = false,
  });
}
