import '../domain/contracts/contracts.dart';
import '../domain/models/models.dart';
import 'fixture_controls.dart';
import 'fixture_library.dart';
import 'fixture_repositories.dart';
import 'fixture_scenarios.dart';
import 'fixture_source.dart';

export 'fixture_controls.dart';
export 'fixture_library.dart';
export 'fixture_repositories.dart';
export 'fixture_scenarios.dart';
export 'fixture_source.dart';

/// Owned by the future dev composition root. Production must not import this.
final class FixtureEnvironment {
  FixtureEnvironment({
    FixtureScenario scenario = FixtureScenario.shortChapter,
    int seed = 20260907,
  }) {
    source = FixtureNovelSource(
      scenario: scenario,
      data: FixtureData(seed: seed),
    );
    novels = FixtureNovelRepository(source);
    images = FixtureImageRepository(source);
  }
  late final FixtureNovelSource source;
  late final FixtureNovelRepository novels;
  late final FixtureImageRepository images;
  final library = FixtureLibraryRepository();
  final settings = FixtureSettingsStore();
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    images.close();
    await Future.wait([novels.close(), library.close()]);
  }
}

final class FixtureSettingsStore implements SettingsStore {
  ReaderSettings _settings = ReaderSettings();
  final controls = FixtureControls();
  @override
  Future<Result<ReaderSettings>> load({
    required CancellationToken cancellation,
  }) async {
    final failure = await controls.before(Operation.settingsRead, cancellation);
    return failure == null ? Success(_settings) : Failure(failure);
  }

  @override
  Future<Result<void>> save(
    ReaderSettings settings, {
    required CancellationToken cancellation,
  }) async {
    final failure = await controls.before(
      Operation.settingsWrite,
      cancellation,
    );
    if (failure != null) return Failure(failure);
    _settings = settings;
    return const Success(null);
  }
}
