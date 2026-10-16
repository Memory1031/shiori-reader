#!/usr/bin/env python3
"""Build both reflowable EPUBs from the complete manuscripts and PNG masters."""

from __future__ import annotations

import argparse
import hashlib
import html
import io
import json
import re
import uuid
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, features, __version__ as pillow_version

ROOT = Path(__file__).resolve().parents[1]
STAMP = (2026, 10, 16, 0, 0, 0)
XHTML = "http://www.w3.org/1999/xhtml"
EPUB = "http://www.idpf.org/2007/ops"


def escape(value: str) -> str:
    return html.escape(value, quote=True)


def document(title: str, lang: str, body: str) -> bytes:
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
        f'<html xmlns="{XHTML}" xmlns:epub="{EPUB}" '
        f'lang="{lang}" xml:lang="{lang}"><head>'
        f'<title>{escape(title)}</title>'
        '<link rel="stylesheet" type="text/css" href="../styles/book.css"/>'
        f'</head><body>{body}</body></html>\n'
    ).encode("utf-8")


def jpeg(image: Image.Image) -> bytes:
    out = io.BytesIO()
    image.convert("RGB").save(out, "JPEG", quality=92, subsampling=0, optimize=False)
    return out.getvalue()


def letter_cover(master: Path, language: str, typography: dict, font_path: Path, index: int) -> bytes:
    # Only the explicitly requested cover typography is added. The PNG stays intact.
    with Image.open(master) as source:
        cover = source.convert("RGB")
    draw = ImageDraw.Draw(cover)
    scale = cover.width / 1024
    # Actual Japanese vertical shaping, including the long vowel mark in カード.
    # Columns read from right to left and remain to the right of the heroine's face.
    for column, line in enumerate(typography["columns"]):
        size = 105 if column == 0 else 119
        font = ImageFont.truetype(str(font_path), round(size * scale), index=index)
        x = round((940 - column * 132) * scale)
        y = round((62 + column * 205) * scale)
        style = dict(font=font, anchor="mt", direction="ttb", language="ja",
                     features=["vert", "vrt2"])
        # A dark offset edge and a broad ivory keyline keep the logo readable
        # against the detailed shop, even at bookshelf-thumbnail size.
        draw.text(
            (x + round(4 * scale), y + round(6 * scale)), line, **style,
            fill="#163b59", stroke_width=max(1, round(10 * scale)),
            stroke_fill="#163b59",
        )
        draw.text(
            (x, y), line, **style,
            fill="#173f63" if column == 0 else "#167fba",
            stroke_width=max(1, round(7 * scale)), stroke_fill="#fffdf4",
        )
    return jpeg(cover)


def chapter(metadata: dict, artwork: dict, row: dict, language: str) -> bytes:
    lang = "zh-CN" if language == "zh" else "en"
    text = (ROOT / "story" / language / f'{row["id"]}.txt').read_text("utf-8")
    title, prose = text.split("\n", 1)
    if title != row[language]:
        raise ValueError(f'Chapter title mismatch: {language}/{row["id"]}')
    paragraphs = [p.strip() for p in prose.strip().split("\n\n") if p.strip()]
    body = [f'<section epub:type="chapter" id="start"><h1>{escape(title)}</h1>']
    inserted = set()
    images = [a for a in artwork["images"] if a.get("chapter") == int(row["id"][-2:])]
    for number, paragraph in enumerate(paragraphs, 1):
        anchor = f"p{number:03}"
        if row["id"] == "chapter-01" and (
            "四角磨成" in paragraph or paragraph.startswith("She drew a piece of blue card")
        ):
            anchor = "first-card"
        content = escape(paragraph)
        # An unobtrusive, meaningful return to the card first examined in chapter 1.
        if row["id"] == "chapter-05" and (
            "手机里的蓝色借书卡" in paragraph
            or "blue library card's picture beside it" in paragraph
        ):
            phrase = "蓝色借书卡" if language == "zh" else "blue library card"
            target = f'<a href="chapter-01.xhtml#first-card">{escape(phrase)}</a>'
            content = content.replace(escape(phrase), target, 1)
        css = ' class="dialogue"' if paragraph.startswith(("“", '"')) else ""
        body.append(f'<p id="{anchor}"{css}>{content}</p>')
        for image in images:
            if image["after"][language] in paragraph:
                name = image["id"]
                body.append(
                    f'<figure id="{name}"><img src="../images/{name}.jpg" '
                    f'alt="{escape(image["alt"][language])}" width="1024" height="1536"/></figure>'
                )
                inserted.add(name)
    if inserted != {a["id"] for a in images}:
        raise ValueError(f'Illustration placement missing: {language}/{row["id"]}')
    body.append("</section>")
    return document(title, lang, "".join(body))


def item(identifier: str, href: str, media: str, properties: str = "") -> str:
    extra = f' properties="{properties}"' if properties else ""
    return f'<item id="{identifier}" href="{href}" media-type="{media}"{extra}/>'


def build(language: str, metadata: dict, artwork: dict, font: Path, index: int) -> Path:
    lang = "zh-CN" if language == "zh" else "en"
    title = metadata["title"][lang]
    creator = metadata["creator"][lang]
    contents = "目录" if language == "zh" else "Contents"
    cover_title = "封面" if language == "zh" else "Cover"
    edition_title = "制作与素材说明" if language == "zh" else "Edition and Artwork"
    short = "原创轻小说" if language == "zh" else "An original light novel"
    files = {"mimetype": b"application/epub+zip"}
    files["META-INF/container.xml"] = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>'
    ).encode()
    files["OEBPS/styles/book.css"] = (ROOT / "epub/styles/book.css").read_bytes()
    cover = letter_cover(ROOT / "artwork/cover/cover-master.png", language,
                         artwork["coverTypography"], font, index)
    files["OEBPS/images/cover.jpg"] = cover
    (ROOT / "dist" / f"cover-{language}.jpg").write_bytes(cover)
    for art in artwork["images"]:
        source = ROOT / "artwork" / art["source"]
        if hashlib.sha256(source.read_bytes()).hexdigest() != art["sha256"]:
            raise ValueError(f"Master artwork changed: {source.name}")
        if art["id"] == "cover":
            continue
        with Image.open(source) as image:
            if image.size != (1024, 1536):
                raise ValueError("Unexpected master aspect ratio; never stretch artwork")
            files[f'OEBPS/images/{art["id"]}.jpg'] = jpeg(image)
    files["OEBPS/text/cover.xhtml"] = document(
        title, lang,
        '<section epub:type="cover" class="cover" id="cover">'
        f'<img src="../images/cover.jpg" alt="{escape(title)}" '
        'width="1024" height="1536"/></section>',
    )
    files["OEBPS/text/title.xhtml"] = document(
        title, lang,
        '<section epub:type="titlepage" class="titlepage" id="title">'
        f'<h1>{escape(title)}</h1><p class="center">{short}</p>'
        f'<p class="center">{escape(creator)}</p></section>',
    )
    links = "".join(
        f'<li><a href="{row["id"]}.xhtml#start">{escape(row[language])}</a></li>'
        for row in metadata["chapters"]
    )
    files["OEBPS/text/nav.xhtml"] = document(
        contents, lang,
        f'<nav epub:type="toc" id="toc"><h1>{contents}</h1><ol>{links}</ol></nav>'
        '<nav epub:type="landmarks" hidden="hidden"><h2>Landmarks</h2><ol>'
        f'<li><a epub:type="cover" href="cover.xhtml">{cover_title}</a></li>'
        f'<li><a epub:type="bodymatter" href="chapter-01.xhtml#start">'
        f'{escape(metadata["chapters"][0][language])}</a></li></ol></nav>',
    )
    for row in metadata["chapters"]:
        files[f'OEBPS/text/{row["id"]}.xhtml'] = chapter(metadata, artwork, row, language)
    edition = (
        "本书为 Shiori Reader 的原创示例小说，采用 AI 辅助创作与编辑。"
        "插图由图像生成工具制作，并参考同一女主视觉设定。人物、店铺与汐见町均为虚构。"
        "本书不随阅读器安装，不是第三方出版作品。"
        if language == "zh" else
        "This original Shiori Reader showcase novel was written and edited with AI assistance. "
        "Its generated illustrations share one heroine design. The characters, shop and town of "
        "Shiomicho are fictional. This is not a third-party publication and is not bundled with the reader."
    )
    files["OEBPS/text/edition.xhtml"] = document(
        edition_title, lang,
        '<section epub:type="colophon" id="edition">'
        f'<h1>{edition_title}</h1><p class="note">{escape(edition)}</p>'
        f'<p class="note">{escape(metadata["rights"][lang])}</p></section>',
    )
    manifest = [
        item("css", "styles/book.css", "text/css"),
        item("cover-image", "images/cover.jpg", "image/jpeg", "cover-image"),
        item("cover", "text/cover.xhtml", "application/xhtml+xml"),
        item("title", "text/title.xhtml", "application/xhtml+xml"),
        item("nav", "text/nav.xhtml", "application/xhtml+xml", "nav"),
        item("edition", "text/edition.xhtml", "application/xhtml+xml"),
    ]
    manifest += [item(a["id"], f'images/{a["id"]}.jpg', "image/jpeg")
                 for a in artwork["images"] if a["id"] != "cover"]
    manifest += [item(r["id"], f'text/{r["id"]}.xhtml', "application/xhtml+xml")
                 for r in metadata["chapters"]]
    order = ["cover", "title", "nav", *[r["id"] for r in metadata["chapters"]], "edition"]
    identity = uuid.uuid5(uuid.NAMESPACE_URL, metadata["identifier"] + "/" + lang)
    files["OEBPS/content.opf"] = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        f'<dc:identifier id="book-id">urn:uuid:{identity}</dc:identifier>'
        f'<dc:title>{escape(title)}</dc:title><dc:language>{lang}</dc:language>'
        f'<dc:creator>{escape(creator)}</dc:creator><dc:publisher>Shiori Reader</dc:publisher>'
        f'<dc:description>{escape(metadata["description"][lang])}</dc:description>'
        f'<dc:rights>{escape(metadata["rights"][lang])}</dc:rights>'
        f'<meta property="dcterms:modified">{metadata["modified"]}</meta>'
        '<meta name="cover" content="cover-image"/>'
        '</metadata><manifest>' + "".join(manifest) + '</manifest><spine>'
        + "".join(f'<itemref idref="{i}"/>' for i in order)
        + '</spine></package>'
    ).encode("utf-8")
    output = ROOT / "dist" / f"shiori-demo-{language}.epub"
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in ["mimetype", *sorted(set(files) - {"mimetype"})]:
            info = zipfile.ZipInfo(name, date_time=STAMP)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
            archive.writestr(info, files[name], compress_type=info.compress_type, compresslevel=9)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cover-font", type=Path,
                        default=ROOT / "artwork/fonts/MochiyPopOne-Regular.ttf")
    parser.add_argument("--font-index", type=int, default=0, help="Font collection face index")
    args = parser.parse_args()
    if not args.cover_font.is_file():
        parser.error("Supply a licensed Japanese title font via --cover-font.")
    if not features.check_feature("raqm"):
        parser.error("Pillow requires libraqm for authentic Japanese vertical title shaping.")
    metadata = json.loads((ROOT / "metadata.json").read_text("utf-8"))
    artwork = json.loads((ROOT / "artwork/art-direction.json").read_text("utf-8"))
    (ROOT / "dist").mkdir(exist_ok=True)
    for language in ("zh", "en"):
        result = build(language, metadata, artwork, args.cover_font, args.font_index)
        print(f"Built {result.name}: {result.stat().st_size:,} bytes")
    info = {
        "pillow": pillow_version,
        "coverFontFile": args.cover_font.name,
        "coverFontSha256": hashlib.sha256(args.cover_font.read_bytes()).hexdigest(),
        "fontIndex": args.font_index,
        "raqm": features.version_feature("raqm"),
        "harfbuzz": features.version_feature("harfbuzz"),
        "freetype": features.version_module("freetype2"),
        "zipTimestamp": list(STAMP),
    }
    (ROOT / "dist/build-info.json").write_text(json.dumps(info, indent=2) + "\n", "utf-8")
    sums = [f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}'
            for p in sorted((ROOT / "dist").iterdir())
            if p.is_file() and p.name != "SHA256SUMS.txt"]
    (ROOT / "dist/SHA256SUMS.txt").write_text("\n".join(sums) + "\n", "utf-8")


if __name__ == "__main__":
    main()
