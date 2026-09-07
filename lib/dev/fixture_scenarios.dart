import '../domain/models/models.dart';

/// Stable enum names are dev scenario IDs; keep them independent of labels.
enum FixtureScenario {
  shortChapter('普通短章', 'Short chapter'),
  longChapter('十万字长章', '100,000-character chapter'),
  extremeParagraph('极端单段', 'Extreme single paragraph'),
  twentyImages('二十张图', 'Twenty images'),
  singleImage('单图章', 'Image-only chapter'),
  slowImage('图片慢加载', 'Slow image'),
  failingImage('图片失败后重试', 'Image failure and retry'),
  unknownImageSize('未知图片比例', 'Unknown image dimensions'),
  longTitle('长标题', 'Long title'),
  typography('空行与多语言排版', 'Whitespace and multilingual typography'),
  multiVolume('多卷与番外', 'Volumes and extras'),
  noVolume('无卷目录', 'Ungrouped catalog'),
  missingVolumeName('缺卷名', 'Unnamed volume'),
  emptySearch('空搜索', 'Empty search'),
  repeatedCursor('分页重复游标', 'Repeated pagination cursor'),
  deletedChapter('章节删除', 'Deleted chapter'),
  revisedContent('正文版本变化', 'Content revision');

  const FixtureScenario(this.labelZh, this.labelEn);
  final String labelZh;
  final String labelEn;
}

final fixtureSourceId = SourceId('dev-fixture');
final fixtureEpoch = DateTime.utc(2026, 9, 7);

NovelKey fixtureNovelKey(FixtureScenario scenario) =>
    NovelKey(sourceId: fixtureSourceId, novelId: scenario.name);
ChapterKey fixtureChapterKey(FixtureScenario scenario, [int index = 0]) =>
    ChapterKey(
      novelKey: fixtureNovelKey(scenario),
      chapterId: 'chapter-$index',
    );
MediaRef fixtureMediaRef(int index) =>
    MediaRef(sourceId: fixtureSourceId, mediaId: 'checker-$index');

/// Lazy content factory: creating a registry does not allocate stress chapters.
final class FixtureData {
  const FixtureData({this.seed = 20260907});
  final int seed;
  NovelSummary summary(FixtureScenario scenario) => NovelSummary(
    key: fixtureNovelKey(scenario),
    title: scenario == FixtureScenario.longTitle
        ? List.filled(12, '星空下的合成阅读实验 Synthetic reading experiment').join('・')
        : '${scenario.labelZh} / ${scenario.labelEn}',
    cover: fixtureMediaRef(0),
    authors: ['Shiori Fixture'],
  );
  NovelDetail detail(FixtureScenario scenario) => NovelDetail(
    summary: summary(scenario),
    synopsis: '自制开发语料，仅用于离线测试。 Self-authored offline test content.',
    tags: ['fixture'],
    status: NovelStatus.completed,
  );
  Catalog catalog(FixtureScenario scenario, {bool deleted = false}) {
    final groups = scenario == FixtureScenario.multiVolume ? 3 : 1;
    var ordinal = 0;
    return Catalog(
      novelKey: fixtureNovelKey(scenario),
      volumes: [
        for (var group = 0; group < groups; group++)
          Volume(
            groupId: 'volume-$group',
            title: switch (scenario) {
              FixtureScenario.noVolume ||
              FixtureScenario.missingVolumeName => null,
              _ => group == 2 ? '番外 / Extras' : '卷 / Volume ${group + 1}',
            },
            isSynthetic: scenario == FixtureScenario.noVolume,
            chapters: [
              for (var chapter = 0; chapter < 3; chapter++)
                if (!(deleted && group == 0 && chapter == 0))
                  Chapter(
                    key: fixtureChapterKey(scenario, group * 3 + chapter),
                    title:
                        '${summary(scenario).title} ${group * 3 + chapter + 1}',
                    ordinal: ordinal++,
                    volumeGroupId: 'volume-$group',
                  ),
            ],
          ),
      ],
    );
  }

  ChapterContent content(
    FixtureScenario scenario, {
    int index = 0,
    int revision = 0,
  }) {
    final imageCount = scenario == FixtureScenario.twentyImages ? 20 : 1;
    final images = {
      FixtureScenario.twentyImages,
      FixtureScenario.singleImage,
      FixtureScenario.slowImage,
      FixtureScenario.failingImage,
      FixtureScenario.unknownImageSize,
    };
    final List<ContentBlock> blocks;
    if (images.contains(scenario)) {
      blocks = [
        for (var i = 0; i < imageCount; i++)
          ImageBlock(
            media: fixtureMediaRef(i),
            width: scenario == FixtureScenario.unknownImageSize
                ? null
                : dimensions(i).$1,
            height: scenario == FixtureScenario.unknownImageSize
                ? null
                : dimensions(i).$2,
            alt: '合成方格 / Synthetic checker $i',
          ),
      ];
    } else if (scenario == FixtureScenario.longChapter) {
      blocks = [
        for (var i = 0; i < 2000; i++) ParagraphBlock(text: _text(i, 50)),
      ];
    } else if (scenario == FixtureScenario.extremeParagraph) {
      blocks = [ParagraphBlock(text: _text(0, 100000))];
    } else if (scenario == FixtureScenario.typography) {
      blocks = [
        HeadingBlock(text: '排版 / Typography'),
        ParagraphBlock(text: '　　全角缩进。「こんにちは」、世界！… — “Hello” 😀'),
        ParagraphBlock(text: ''),
        ParagraphBlock(text: '\n'),
        ParagraphBlock(
          text: '居中 / Center',
          alignment: ParagraphAlignment.center,
        ),
        ParagraphBlock(
          text: '强调保留文字 / Emphasis as plain text',
          leadingIndent: 2,
        ),
        ParagraphBlock(text: '漢字（かんじ）'),
        DividerBlock(),
      ];
    } else {
      blocks = [
        for (var i = 0; i < 8; i++)
          ParagraphBlock(text: _text(index * 8 + i, 50)),
      ];
    }
    if (revision > 0) {
      blocks.insert(0, ParagraphBlock(text: '修订 / Revision $revision'));
    }
    return ChapterContent(
      key: fixtureChapterKey(scenario, index),
      title: '${summary(scenario).title} ${index + 1}',
      blocks: blocks,
    );
  }

  String _text(int paragraph, int length) {
    const chars = '星空山川风雨花草树木日月云海春夏秋冬书页灯火梦境远方';
    return String.fromCharCodes(
      List.generate(
        length,
        (i) => chars.codeUnitAt(((seed + paragraph * 7 + i) % chars.length)),
      ),
    );
  }

  (int, int) dimensions(int index) => (64 + index * 8, 48 + (index * 37) % 240);
}
