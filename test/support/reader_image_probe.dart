import 'package:flutter/material.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/shared/source_image.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = FixtureEnvironment();
  final images = MemoryImageRepository(resolve: (_) => env.source);
  final result = await images.load(
    fixtureMediaRef(0),
    mode: ReadMode.cacheFirst,
    cancellation: CancellationSource().token,
  );
  final lease = (result as Success<LoadResult<MediaLease>>).value.value;
  final decoded = await decodeSourceImage(lease.data, 32);
  if (decoded.image.width != 32 || decoded.image.height != 24) {
    throw StateError('Thumbnail mismatch');
  }
  decoded.image.dispose();
  await lease.close();
  if (images.retainedBytes != 0) throw StateError('Lease retained');
  debugPrint('READER_IMAGE_PASS codec=32x24 intrinsic=64x48 retainedBytes=0');
  runApp(
    ShioriApp(
      locale: const Locale('zh'),
      routes: AppRoutes(
        home: (_) => ReaderContentView(
          images: images,
          content: ChapterContent(
            key: fixtureChapterKey(FixtureScenario.unknownImageSize),
            title: '图片阅读验证 / Image reader',
            blocks: [
              ParagraphBlock(text: '未知尺寸图片加载后，正文和图片说明应保持完整。'),
              ImageBlock(
                media: fixtureMediaRef(0),
                caption: '合成插图 / Synthetic illustration',
              ),
              for (var i = 0; i < 20; i++)
                ParagraphBlock(text: '正文段落 $i：支持左右翻页与上下滚动。'),
            ],
          ),
        ),
      ),
    ),
  );
}
