import 'package:html/dom.dart' as dom;
import '../../../domain/contracts/local_book_decoder.dart';
import '../../../domain/models/models.dart';

/// Import-time evidence only; neither document titles nor image-only pages
/// alone partition ordinary body files into new chapters.
final class EpubFrontMatter {
  const EpubFrontMatter(this.kind, this.title, {this.generated = false});
  final LocalNavigationLabel kind;
  final String title;
  final bool generated;
  bool get grouped =>
      kind == LocalNavigationLabel.illustrations ||
      kind == LocalNavigationLabel.contents;

  static EpubFrontMatter? label(String title) {
    final value = _normalize(title);
    final kind = switch (value) {
      'cover' || '封面' || '表紙' => LocalNavigationLabel.cover,
      'titlepage' ||
      'title-page' ||
      '扉页' ||
      '扉頁' => LocalNavigationLabel.titlePage,
      'credits' ||
      'copyright' ||
      'copyrightpage' ||
      'colophon' ||
      '制作信息' ||
      '製作信息' ||
      '版权页' ||
      '版權頁' => LocalNavigationLabel.credits,
      'synopsis' ||
      'summary' ||
      '简介' ||
      '簡介' ||
      '内容简介' ||
      '內容簡介' ||
      'あらすじ' => LocalNavigationLabel.synopsis,
      'abouttheauthor' ||
      'authorbio' ||
      '作者简介' ||
      '作者簡介' ||
      '作者介绍' ||
      '作者介紹' => LocalNavigationLabel.author,
      'abouttheillustrator' ||
      'illustratorbio' ||
      '画师简介' ||
      '畫師簡介' ||
      '画师介绍' ||
      '畫師介紹' => LocalNavigationLabel.illustrator,
      'illustrations' ||
      'colorillustrations' ||
      'colourillustrations' ||
      '彩插' ||
      '彩页' ||
      '彩頁' ||
      '口絵' => LocalNavigationLabel.illustrations,
      'contents' ||
      'tableofcontents' ||
      '目录' ||
      '目錄' ||
      '目次' => LocalNavigationLabel.contents,
      'preface' || 'foreword' || '序言' || '前言' => LocalNavigationLabel.preface,
      'dedication' || '献辞' || '獻辭' => LocalNavigationLabel.dedication,
      _ => null,
    };
    return kind == null ? null : EpubFrontMatter(kind, title.trim());
  }

  static EpubFrontMatter? semantic(String type, String title) {
    final fallback = switch (type) {
      'cover' => 'Cover',
      'titlepage' || 'title-page' => 'Title page',
      'copyright-page' || 'colophon' || 'credits' => 'Credits',
      'abstract' || 'summary' || 'synopsis' => 'Synopsis',
      'contributors' || 'biographical' => 'About the author',
      'loi' => 'Illustrations',
      'toc' => 'Contents',
      'preface' || 'foreword' => 'Preface',
      'dedication' => 'Dedication',
      _ => null,
    };
    if (fallback == null) return null;
    return EpubFrontMatter(
      label(fallback)!.kind,
      _generic(title) ? fallback : title.trim(),
      generated: _generic(title),
    );
  }
}

Set<String> epubStructuralTypes(dom.Element node) {
  final result = <String>{};
  for (final entry in node.attributes.entries) {
    final parts = entry.key.toString().split(':');
    if (parts.length != 2 || parts.last != 'type') continue;
    String? namespace;
    for (dom.Element? parent = node; parent != null; parent = parent.parent) {
      namespace = parent.attributes['xmlns:${parts.first}'];
      if (namespace != null) break;
    }
    if (namespace == 'http://www.idpf.org/2007/ops' ||
        namespace == null && parts.first == 'epub') {
      result.addAll(entry.value.split(RegExp(r'\s+')));
    }
  }
  for (final role in (node.attributes['role'] ?? '').split(RegExp(r'\s+'))) {
    if (role.startsWith('doc-')) result.add(role.substring(4));
  }
  return result;
}

final class EpubFrontMatterDocument {
  const EpubFrontMatterDocument({
    this.matter,
    this.body = false,
    this.imageOnly = false,
    this.genericTitle = false,
    this.titlePage = false,
  });
  final EpubFrontMatter? matter;
  final bool body, imageOnly, genericTitle, titlePage;
}

EpubFrontMatterDocument inspectEpubFrontMatter(
  dom.Document doc,
  ChapterContent chapter, {
  required String bookTitle,
  required Iterable<String> authors,
}) {
  // A semantic marker on an inner paragraph must not classify a mixed body
  // document. Inspect only the document and its sole enclosing containers.
  final types = <String>{};
  if (doc.documentElement case final root?) {
    types.addAll(epubStructuralTypes(root));
  }
  dom.Element? node = doc.body;
  for (var depth = 0; node != null && depth < 32; depth++) {
    types.addAll(epubStructuralTypes(node));
    final children = node.children
        .where((e) => !{'script', 'style'}.contains(e.localName))
        .toList();
    if (children.length != 1 ||
        node.nodes.whereType<dom.Text>().any((e) => e.text.trim().isNotEmpty) ||
        !{
          'section',
          'article',
          'div',
          'nav',
        }.contains(children.single.localName)) {
      break;
    }
    node = children.single;
  }
  final body = types.any(
    {'bodymatter', 'chapter', 'prologue', 'epilogue', 'part'}.contains,
  );
  final texts = chapter.blocks
      .map(
        (b) => switch (b) {
          ParagraphBlock(:final text) ||
          HeadingBlock(:final text) => text.trim(),
          _ => '',
        },
      )
      .where((t) => t.isNotEmpty)
      .toList();
  final length = texts.fold(0, (n, t) => n + t.runes.length);
  final imageOnly = texts.isEmpty && chapter.blocks.any((b) => b is ImageBlock);
  final genericTitle =
      _generic(chapter.title) ||
      _normalize(chapter.title) == _normalize(bookTitle);
  final authoredTitle =
      doc.querySelector('title')?.text ??
      chapter.blocks.whereType<HeadingBlock>().firstOrNull?.text ??
      '';
  EpubFrontMatter? matter;
  if (!body) {
    for (final type in types) {
      matter ??= EpubFrontMatter.semantic(type, authoredTitle);
    }
    if (doc
        .querySelectorAll('meta')
        .any(
          (e) =>
              e.attributes['name'] == 'calibre:cover' &&
              e.attributes['content'] == 'true',
        )) {
      matter = EpubFrontMatter.semantic('cover', authoredTitle);
    }
    if (length <= 4096 && chapter.blocks.length <= 128) {
      for (final title in [authoredTitle, if (texts.isNotEmpty) texts.first]) {
        final hint = EpubFrontMatter.label(title);
        if (hint?.kind == LocalNavigationLabel.cover && !imageOnly) continue;
        matter ??= hint;
      }
    }
  }
  // Some exporters use a generic title for the printed title page. Require
  // both publication title and author, and later require a preceding cover.
  final series = bookTitle.replaceFirst(
    RegExp(r'\s*[0-9０-９]+(?:\s*[-–~～]\s*[0-9０-９]+)?\s*卷?\s*$'),
    '',
  );
  final text = length <= 512 ? _normalize(texts.join()) : '';
  final titlePage =
      !body &&
      !imageOnly &&
      _normalize(series).length >= 4 &&
      text.startsWith(_normalize(series)) &&
      authors.any((a) => a.trim().isNotEmpty && text.contains(_normalize(a)));
  return EpubFrontMatterDocument(
    matter: matter,
    body: body,
    imageOnly: imageOnly,
    genericTitle: genericTitle,
    titlePage: titlePage,
  );
}

/// Keep authored tree order, nesting and fragment targets. New entries are
/// inserted beside the next target in physical reading order; they do not
/// replace or sort the publisher's navigation.
List<LocalNavigationEntry> supplementEpubFrontMatter({
  required List<ChapterContent> chapters,
  required List<LocalNavigationEntry> navigation,
  required Iterable<ChapterKey> readingOrder,
  required Map<ChapterKey, EpubFrontMatterDocument> documents,
  required Map<ChapterKey, EpubFrontMatter> structural,
  required void Function() onAdd,
}) {
  final ordinals = {
    for (var i = 0; i < chapters.length; i++) chapters[i].key: i,
  };
  final existing = <ChapterKey>{};
  final primary = readingOrder.toSet();
  final targets = <(LocalNavigationEntry, int, int)>[];
  final labels = <ChapterKey, EpubFrontMatter>{};
  void collect(List<LocalNavigationEntry> entries) {
    for (final entry in entries) {
      existing.add(entry.chapterKey);
      final at = ordinals[entry.chapterKey];
      if (at != null) {
        final block = entry.blockKey == null
            ? 0
            : chapters[at].blocks.indexWhere(
                (b) => b.blockKey == entry.blockKey,
              );
        if (block >= 0) {
          targets.add((entry, at, block));
          if (block == 0) {
            final matter = EpubFrontMatter.label(entry.title);
            if (matter != null) labels[entry.chapterKey] = matter;
          }
        }
      }
      collect(entry.children);
    }
  }

  collect(navigation);
  final additions = <LocalNavigationEntry>[];
  EpubFrontMatter? previous;
  for (final chapter in chapters) {
    final doc = documents[chapter.key];
    var matter = doc?.body == true
        ? null
        : structural[chapter.key] ?? labels[chapter.key] ?? doc?.matter;
    if (matter == null &&
        doc?.titlePage == true &&
        previous?.kind == LocalNavigationLabel.cover) {
      matter = EpubFrontMatter.semantic('titlepage', '');
    }
    if (matter == null) {
      if (primary.contains(chapter.key) &&
          !existing.contains(chapter.key) &&
          doc?.body != true &&
          doc?.imageOnly == true &&
          doc?.genericTitle == true &&
          previous?.kind == LocalNavigationLabel.illustrations) {
        continue;
      }
      previous = null;
      continue;
    }
    if (!existing.contains(chapter.key) &&
        !(primary.contains(chapter.key) &&
            previous?.kind == matter.kind &&
            (matter.grouped ||
                !{
                      LocalNavigationLabel.cover,
                      LocalNavigationLabel.titlePage,
                    }.contains(matter.kind) &&
                    _normalize(previous!.title) == _normalize(matter.title)))) {
      onAdd();
      additions.add(
        LocalNavigationEntry(
          title: matter.title,
          chapterKey: chapter.key,
          generatedLabel: matter.generated ? matter.kind : null,
        ),
      );
    }
    previous = primary.contains(chapter.key) ? matter : null;
  }
  if (additions.isEmpty) return navigation;
  // List.sort is not stable: retain traversal order at identical targets.
  final sequence = {for (var i = 0; i < targets.length; i++) targets[i].$1: i};
  targets.sort((a, b) {
    final order = a.$2.compareTo(b.$2);
    if (order != 0) return order;
    final block = a.$3.compareTo(b.$3);
    return block != 0 ? block : sequence[a.$1]!.compareTo(sequence[b.$1]!);
  });
  final before = <LocalNavigationEntry, List<LocalNavigationEntry>>{};
  final trailing = <LocalNavigationEntry>[];
  for (final entry in additions) {
    final ordinal = ordinals[entry.chapterKey]!;
    var lo = 0, hi = targets.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (targets[mid].$2 < ordinal) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == targets.length) {
      trailing.add(entry);
    } else {
      before.putIfAbsent(targets[lo].$1, () => []).add(entry);
    }
  }
  List<LocalNavigationEntry> merge(List<LocalNavigationEntry> entries) => [
    for (final entry in entries) ...[
      ...?before[entry],
      if (entry.children.isEmpty)
        entry
      else
        LocalNavigationEntry(
          title: entry.title,
          chapterKey: entry.chapterKey,
          blockKey: entry.blockKey,
          generatedLabel: entry.generatedLabel,
          children: merge(entry.children),
        ),
    ],
  ];
  return [...merge(navigation), ...trailing];
}

bool _generic(String title) =>
    {'', '未知', 'unknown', 'untitled'}.contains(_normalize(title)) ||
    RegExp(r'^(part|section|chapter)[0-9]+$').hasMatch(_normalize(title));

String _normalize(String text) => String.fromCharCodes(
  text.runes.map((r) => r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r),
).toLowerCase().replaceAll(RegExp(r'[\s\u3000。．.!！:：·・❤]'), '');
