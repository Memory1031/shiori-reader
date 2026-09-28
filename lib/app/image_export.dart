import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/local/files/app_paths.dart';
import '../data/media/export/image_export_operation.dart';
import '../data/media/export/platform_image_export.dart';
import '../domain/contracts/image_export.dart';

ImageExporter createImageExporter(AppPaths paths) => ImageExportOperation(
  stagingRoot: () async => Directory(
    p.join((await getTemporaryDirectory()).path, 'shiori-image-export'),
  ),
  destination: Platform.isWindows
      ? FileImageExportDestination(
          protectedRoots: [paths.root.parent, paths.temporary.parent],
        )
      : const NativeImageExportDestination(),
);
