import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/media/export/image_export_operation.dart';
import 'package:shiori/data/media/export/platform_image_export.dart';
import 'package:shiori/data/media/media_format.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/image_export.dart';
import 'package:shiori/domain/models/models.dart';

class ExportLease implements MediaLease {
  ExportLease(this.data);
  @override
  final MediaData data;
  @override
  bool isClosed = false;
  int closes = 0;
  @override
  MediaPersistence get persistence => data is LocalMedia
      ? MediaPersistence.persistedLocal
      : MediaPersistence.memoryOnly;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  Future<void> close() async {
    isClosed = true;
    closes++;
  }
}

class ExportRepository implements ImageRepository {
  ExportRepository(this.data);
  final MediaData data;
  final leases = <ExportLease>[];
  final modes = <ReadMode>[];
  Completer<void>? gate;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    modes.add(mode);
    await gate?.future;
    final lease = ExportLease(data);
    leases.add(lease);
    return Success(
      LoadResult(
        value: lease,
        origin: LoadOrigin.local,
        fetchedAt: DateTime.utc(2026),
      ),
    );
  }
}

class ExportDestination implements ImageExportDestination {
  final entered = Completer<void>();
  Completer<ImageExportResult>? gate;
  ImageExportResult result = ImageExportResult.savedPhotos;
  PreparedImageExport? prepared;
  List<int>? bytes;
  int calls = 0;
  bool throws = false;
  void Function()? onSave;
  @override
  Future<ImageExportResult> save(
    PreparedImageExport image, {
    required bool asFile,
    required CancellationToken cancellation,
  }) async {
    calls++;
    onSave?.call();
    prepared = image;
    bytes = await File(image.path).readAsBytes();
    if (!entered.isCompleted) entered.complete();
    if (throws) throw StateError('private-path/credentials');
    return gate == null ? result : await gate!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory staging;
  late ExportDestination destination;
  late ImageExportOperation operation;
  final png = fixturePng(32, 24, 1);
  ExportRepository memory([List<int>? bytes]) => ExportRepository(
    MemoryMedia(
      bytes: Uint8List.fromList(bytes ?? png),
      info: MediaInfo(format: MediaFormat.unknown),
    ),
  );
  Future<ImageExportResult> save(
    ExportRepository repo, {
    CancellationSource? cancel,
  }) => operation.save(
    repository: repo,
    media: fixtureMediaRef(0),
    cancellation: (cancel ?? CancellationSource()).token,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shiori-export-test-');
    staging = Directory('${root.path}/shiori-image-export');
    destination = ExportDestination();
    operation = ImageExportOperation(
      stagingRoot: () async => staging,
      destination: destination,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'memory original bytes, signature, MIME and independent lease',
    () async {
      final repo = memory();
      expect(await save(repo), ImageExportResult.savedPhotos);
      expect(destination.bytes, png);
      expect(destination.prepared!.mime, 'image/png');
      expect(
        destination.prepared!.name,
        matches(r'^shiori-[a-f0-9]{12}-\d+\.png$'),
      );
      expect(repo.modes, [ReadMode.cacheFirst]);
      expect(repo.leases.single.closes, 1);
      expect(await staging.list().toList(), isEmpty);
    },
  );
  test(
    'local unknown format copies encoded file without modifying source',
    () async {
      final original = await File('${root.path}/book-image').writeAsBytes(png);
      final repo = ExportRepository(
        LocalMedia(
          path: original.path,
          info: MediaInfo(format: MediaFormat.unknown),
        ),
      );
      expect(await save(repo), ImageExportResult.savedPhotos);
      expect(destination.bytes, png);
      expect(await original.readAsBytes(), png);
      expect(repo.leases.single.isClosed, isTrue);
    },
  );
  test('JPEG PNG animated GIF WebP AVIF remain byte-identical', () async {
    // Encoded signature fixtures include arbitrary payload. No decoder or
    // first-frame conversion is involved in this byte-preservation contract.
    final signatures = <MediaFormat, List<int>>{
      MediaFormat.jpeg: [255, 216, 255, 224, 1, 2, 3],
      MediaFormat.png: png,
      MediaFormat.gif: [...'GIF89a'.codeUnits, ...List.generate(100, (i) => i)],
      MediaFormat.webp: [
        ...'RIFF'.codeUnits,
        20,
        0,
        0,
        0,
        ...'WEBPVP8X'.codeUnits,
      ],
      MediaFormat.avif: [
        0,
        0,
        0,
        24,
        ...'ftypavif'.codeUnits,
        0,
        0,
        0,
        0,
        ...'avifmif1'.codeUnits,
      ],
    };
    for (final entry in signatures.entries) {
      expect(detectMediaFormat(entry.value), entry.key);
      final repo = memory(entry.value);
      expect(await save(repo), ImageExportResult.savedPhotos);
      expect(destination.bytes, entry.value);
      expect(destination.prepared!.mime, imageEncoding(entry.key).mime);
      expect(
        destination.prepared!.name,
        endsWith('.${imageEncoding(entry.key).extension}'),
      );
    }
  });
  for (final result in [
    ImageExportResult.cancelled,
    ImageExportResult.permissionDenied,
    ImageExportResult.storageFailure,
    ImageExportResult.unsupportedFormat,
  ]) {
    test('$result cleans staging and lease', () async {
      destination.result = result;
      final repo = memory();
      expect(await save(repo), result);
      expect(repo.leases.single.closes, 1);
      expect(await staging.list().toList(), isEmpty);
    });
  }
  test('unrecognized and mismatched format never opens destination', () async {
    expect(await save(memory([1, 2, 3, 4])), ImageExportResult.invalidFormat);
    final repo = ExportRepository(
      MemoryMedia(
        bytes: png,
        info: MediaInfo(format: MediaFormat.jpeg),
      ),
    );
    expect(await save(repo), ImageExportResult.invalidFormat);
    expect(repo.leases.single.isClosed, isTrue);
    expect(destination.calls, 0);
  });
  test(
    'close during preparation releases late lease and never opens system UI',
    () async {
      final repo = memory()..gate = Completer<void>();
      final cancel = CancellationSource();
      final pending = save(repo, cancel: cancel);
      cancel.cancel();
      repo.gate!.complete();
      expect(await pending, ImageExportResult.cancelled);
      expect(destination.calls, 0);
      expect(repo.leases.single.isClosed, isTrue);
    },
  );
  test(
    'native owns staging until actual completion, even after cancellation',
    () async {
      destination.gate = Completer<ImageExportResult>();
      final repo = memory();
      final cancel = CancellationSource();
      final pending = save(repo, cancel: cancel);
      await destination.entered.future;
      final file = File(destination.prepared!.path);
      cancel.cancel();
      expect(await file.exists(), isTrue);
      expect(repo.leases.single.isClosed, isFalse);
      destination.gate!.complete(ImageExportResult.savedPhotos);
      expect(await pending, ImageExportResult.savedPhotos);
      expect(await file.exists(), isFalse);
      expect(repo.leases.single.closes, 1);
    },
  );
  test(
    'handoff errors after close never pretend a submitted write was cancelled',
    () async {
      final cancel = CancellationSource();
      destination.onSave = cancel.cancel;
      destination.throws = true;
      final repo = memory();
      expect(
        await save(repo, cancel: cancel),
        ImageExportResult.storageFailure,
      );
      expect(repo.leases.single.closes, 1);
      expect(await staging.list().toList(), isEmpty);
    },
  );
  test('adapter exception is controlled and still cleans resources', () async {
    destination.throws = true;
    final repo = memory();
    expect(await save(repo), ImageExportResult.storageFailure);
    expect(repo.leases.single.closes, 1);
    expect(await staging.list().toList(), isEmpty);
  });
  test(
    'file adapter writes actual bytes; exported copy outlives source/cache',
    () async {
      final user = await Directory('${root.path}/user').create();
      final target = File('${user.path}/copy.png');
      operation = ImageExportOperation(
        stagingRoot: () async => staging,
        destination: FileImageExportDestination(
          protectedRoots: [staging],
          select: (_) async => target.path,
        ),
      );
      expect(await save(memory()), ImageExportResult.savedFile);
      await staging.delete(recursive: true);
      expect(await target.readAsBytes(), png);
    },
  );
  test(
    'file picker cancellation is silent; existing files never overwritten',
    () async {
      final target = await File('${root.path}/copy.png').writeAsString('keep');
      operation = ImageExportOperation(
        stagingRoot: () async => staging,
        destination: FileImageExportDestination(
          protectedRoots: [],
          select: (_) async => null,
        ),
      );
      expect(await save(memory()), ImageExportResult.cancelled);
      operation = ImageExportOperation(
        stagingRoot: () async => staging,
        destination: FileImageExportDestination(
          protectedRoots: [],
          select: (_) async => target.path,
        ),
      );
      expect(await save(memory()), ImageExportResult.destinationExists);
      expect(await target.readAsString(), 'keep');
    },
  );
  test('reject managed destination and link into managed directory', () async {
    final managed = await Directory('${root.path}/books').create();
    final alias = await Link('${root.path}/alias').create(managed.path);
    for (final folder in [managed.path, alias.path]) {
      operation = ImageExportOperation(
        stagingRoot: () async => staging,
        destination: FileImageExportDestination(
          protectedRoots: [managed],
          select: (_) async => '$folder/image.png',
        ),
      );
      expect(await save(memory()), ImageExportResult.storageFailure);
    }
    expect(await managed.list().toList(), isEmpty);
  });
  test(
    'late picker result after close cannot write; wrong extension rejected',
    () async {
      final cancel = CancellationSource();
      final target = File('${root.path}/copy.png');
      operation = ImageExportOperation(
        stagingRoot: () async => staging,
        destination: FileImageExportDestination(
          protectedRoots: [],
          select: (_) async {
            cancel.cancel();
            return target.path;
          },
        ),
      );
      expect(await save(memory(), cancel: cancel), ImageExportResult.cancelled);
      expect(await target.exists(), isFalse);
      operation = ImageExportOperation(
        stagingRoot: () async => staging,
        destination: FileImageExportDestination(
          protectedRoots: [],
          select: (_) async => '${root.path}/copy.jpg',
        ),
      );
      expect(await save(memory()), ImageExportResult.invalidFormat);
    },
  );
  test(
    'native channel cancellation waits for real callback and maps result',
    () async {
      const channel = MethodChannel('dev.shiori.reader/image_export');
      final calls = <MethodCall>[];
      final gate = Completer<String>();
      final arrived = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'cancel') return null;
        arrived.complete();
        return gate.future;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      operation = ImageExportOperation(
        stagingRoot: () async => staging,
        destination: const NativeImageExportDestination(),
      );
      final cancel = CancellationSource();
      final pending = save(memory(), cancel: cancel);
      await arrived.future;
      final path = (calls.first.arguments as Map)['path'] as String;
      cancel.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((c) => c.method), ['save', 'cancel']);
      expect(await File(path).exists(), isTrue);
      gate.complete('savedPhotos');
      expect(await pending, ImageExportResult.savedPhotos);
      expect(await File(path).exists(), isFalse);
    },
  );
}
