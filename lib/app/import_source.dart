import 'dart:io';

import '../data/import/desktop_import_source.dart';
import '../data/import/platform_import_source.dart';
import '../data/import/windows_file_drop.dart';
import '../data/local/files/app_paths.dart';
import '../domain/contracts/import_source.dart';

/// The caller transfers ownership to ImportController, which closes the source.
/// Use the host OS, independent of UI theme/platform overrides.
ImportSource createImportSource(AppPaths paths, {String? operatingSystem}) =>
    switch (operatingSystem ?? Platform.operatingSystem) {
      'android' || 'ios' => PlatformImportSource(),
      'windows' => DesktopImportSource(
        inbox: paths.importInbox,
        droppedFiles: windowsDroppedFiles(),
      ),
      'macos' => DesktopImportSource(inbox: paths.importInbox),
      final platform => throw UnsupportedError(
        'Import is unavailable on $platform',
      ),
    };
