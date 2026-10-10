import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/synthetic_audio.dart';

void main() {
  test(
    'audio controls keep order, media, alignment, targets and JSON identity',
    () {
      final parsed = audioEpub(
        '<p>Before 😀</p><p style="text-align:right">'
        '<audio id="sound" controls autoplay><source src="../audio/test.wav" type="audio/wav"/></audio>'
        '</p><p>After</p><a href="#sound">Listen</a>',
      );
      final chapter = parsed.content.chapters.first;
      final audio = chapter.blocks.whereType<AudioBlock>().single;
      expect(audio.format, AudioFormat.wav);
      expect(audio.alignment, ParagraphAlignment.end);
      expect(audio.mediaRefs.single, audio.media);
      expect(
        parsed.media[audio.media!.mediaId.split('/').last],
        syntheticWav(),
      );
      expect(chapter.blocks[0].fieldsJson['text'], 'Before 😀');
      expect(chapter.blocks[1], audio);
      expect(chapter.blocks[2].fieldsJson['text'], 'After');
      expect(parsed.content.links.single.targetBlockKey, audio.blockKey);
      expect(ChapterContent.fromJson(chapter.toJson()), chapter);
    },
  );
  test('source fallback and repeated local instances keep one resource', () {
    final parsed = audioEpub(
      '<audio controls><source src="missing.wav"/>'
      '<source src="../audio/test.wav"/></audio><audio controls src="../audio/test.wav"></audio>',
    );
    final audio = parsed.content.chapters.first.blocks
        .whereType<AudioBlock>()
        .toList();
    expect(audio, hasLength(2));
    expect(audio[0].media, audio[1].media);
    expect(audio[0].blockKey, isNot(audio[1].blockKey));
  });
  test('hidden and non-controls audio do not load resources or autoplay', () {
    final parsed = audioEpub(
      '<audio autoplay src="../audio/test.wav"></audio>'
      '<div hidden><audio controls src="../audio/test.wav"></audio></div>'
      '<audio controls style="display:none" src="../audio/test.wav"></audio>'
      '<audio controls style="visibility:hidden" src="../audio/test.wav"></audio><p>Tail</p>',
    );
    expect(
      parsed.content.chapters.first.blocks.whereType<AudioBlock>(),
      isEmpty,
    );
    expect(
      parsed.media.values.any((b) => b.length == syntheticWav().length),
      isFalse,
    );
  });
  test(
    'visibility-restored audio works and missing/remote/escaping audio remains inert',
    () {
      final parsed = audioEpub(
        '<div style="visibility:hidden"><audio controls style="visibility:visible" src="../audio/test.wav"></audio></div>'
        '<audio controls src="missing.wav"></audio><audio controls src="https://invalid.example/a.mp3"></audio>'
        '<audio controls src="../../../escape.wav"></audio><p>Tail</p>',
      );
      final audio = parsed.content.chapters.first.blocks
          .whereType<AudioBlock>()
          .toList();
      expect(audio[0].media, isNotNull);
      expect(audio.skip(1).map((a) => a.unavailable), [
        AudioUnavailable.missing,
        AudioUnavailable.external,
        AudioUnavailable.unsupported,
      ]);
    },
  );
}
