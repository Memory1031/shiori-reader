import 'package:drift/native.dart';
import '../../../domain/contracts/contracts.dart';
import '../files/app_paths.dart';
import '../managed_local_books.dart';
import 'user_database.dart';
import 'cache_database.dart';

/// One owner, one background connection per lifetime. No cross-file transactions.
class LocalDatabases {
  LocalDatabases._(this.users, this.cache, this.localBooks);
  final UserDatabase users;
  final CacheDatabase cache;
  final ManagedLocalBooks localBooks;
  static Future<Result<LocalDatabases>> open(AppPaths paths) async {
    UserDatabase? users;
    CacheDatabase? cache;
    try {
      await paths.prepare();
      users = UserDatabase(
        NativeDatabase.createInBackground(paths.userDatabase),
      );
      // Finish native opening before spawning the second connection.
      await users.customSelect('SELECT 1').get();
      cache = CacheDatabase(
        NativeDatabase.createInBackground(paths.cacheDatabase),
      );
      await cache.customSelect('SELECT 1').get();
      final imported = await ManagedLocalBooks.open(paths, users);
      if (imported case Success<ManagedLocalBooks>(:final value)) {
        return Success(LocalDatabases._(users, cache, value));
      }
      throw StateError('Local book storage unavailable');
    } catch (_) {
      await users?.close();
      await cache?.close();
      // Preserve every file, including corrupt or future-version databases.
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.libraryRead,
        ),
      );
    }
  }

  Future<void> close() async {
    await localBooks.close();
    await users.close();
    await cache.close();
  }
}
