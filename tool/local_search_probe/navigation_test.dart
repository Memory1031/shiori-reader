import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import '../../test/widgets/reader/link_return_test.dart' as fixture;
import 'matcher.dart';

void main() {
  for (final target in ['same', 'main', 'auxiliary']) {
    testWidgets(
      'probe source hit follows existing $target navigation and returns',
      (tester) async {
        final reader = await fixture.mount(tester);
        final origin = reader.position(tester);
        final source = reader.view(tester).content;
        final targetKey = target == 'same'
            ? source.key
            : target == 'main'
            ? reader.key('b')
            : reader.book.auxiliaryChapters.first.key;
        final progressBefore = await reader.library.getProgress(
          source.key.novelKey,
          cancellation: CancellationSource().token,
        );
        final hits = scan(snapshot(reader.book), 'Readable fixture').hits;
        final hit = hits.lastWhere((h) => h.chapter == targetKey);
        final progressAfter = await reader.library.getProgress(
          source.key.novelKey,
          cancellation: CancellationSource().token,
        );
        expect(
          (progressAfter as Success<ReadingProgress?>).value,
          (progressBefore as Success<ReadingProgress?>).value,
        );
        LocalContentLink link() => LocalContentLink(
          source: source.key,
          sourceBlockKey: source.blocks.first.blockKey,
          label: 'Synthetic probe target',
          target: hit.chapter,
          targetBlockKey: hit.blockKey,
          targetOffset: hit.start,
        );
        if (target == 'main') {
          reader.repository
            ..blocked = targetKey
            ..fail = true;
          reader.view(tester).actions.contentLink!(link());
          await tester.pumpAndSettle();
          expect(reader.view(tester).content.key, source.key);
          expect(reader.position(tester), origin);
          reader.repository.fail = false;
        }
        reader.view(tester).actions.contentLink!(link());
        await tester.pumpAndSettle();
        expect(reader.view(tester).content.key, targetKey);
        expect(reader.position(tester).blockKey, hit.blockKey);
        final b =
            reader.view(tester).content.blocks[hit.blockIndex]
                as ParagraphBlock;
        expect(
          reader.position(tester).blockFraction,
          closeTo(hit.start / b.text.runes.length, 1e-9),
        );
        if (target == 'auxiliary') {
          reader.view(tester).actions.leave!();
          await tester.pumpAndSettle();
        } else {
          await reader.back(tester);
        }
        expect(reader.view(tester).content.key, source.key);
        expect(reader.position(tester), origin);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
