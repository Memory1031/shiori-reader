import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum StorageEnvironment { production, development }

/// Platform roots and fixed local names only, never Source IDs or URLs.
class AppPaths {
  AppPaths({
    required Directory support,
    required Directory temporary,
    required this.environment,
  }) : root = Directory(
         p.join(support.absolute.path, 'shiori', environment.name),
       ),
       temporary = Directory(
         p.join(temporary.absolute.path, 'shiori', environment.name),
       );
  final StorageEnvironment environment;
  final Directory root;
  final Directory temporary;
  Directory get users => Directory(p.join(root.path, 'users'));
  Directory get localBooks => Directory(p.join(users.path, 'books'));
  Directory get localImportStaging =>
      Directory(p.join(users.path, 'import-staging'));
  Directory get disposable => Directory(p.join(root.path, 'disposable'));
  Directory get staging => Directory(p.join(disposable.path, 'staging'));
  Directory get images => Directory(p.join(disposable.path, 'images'));
  Directory get chapters => Directory(p.join(disposable.path, 'chapters'));
  File get userDatabase => File(p.join(users.path, 'users.sqlite'));
  File get cacheDatabase => File(p.join(disposable.path, 'cache.sqlite'));
  String get settingsKey => 'shiori.${environment.name}.readerSettings';
  String get appSettingsKey => 'shiori.${environment.name}.appSettings';
  static Future<AppPaths> resolve(StorageEnvironment environment) async =>
      AppPaths(
        support: await getApplicationSupportDirectory(),
        temporary: await getTemporaryDirectory(),
        environment: environment,
      );
  Future<void> prepare() async {
    for (final dir in [
      users,
      disposable,
      staging,
      images,
      chapters,
      temporary,
    ]) {
      await dir.create(recursive: true);
    }
  }
}
