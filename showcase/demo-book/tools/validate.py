#!/usr/bin/env python3
"""Independent ZIP/XML/reference/manuscript checks; EPUBCheck is complementary."""

from __future__ import annotations

import collections
import hashlib
import io
import json
import posixpath
import re
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NS = {"opf": "http://www.idpf.org/2007/opf", "dc": "http://purl.org/dc/elements/1.1/",
      "h": "http://www.w3.org/1999/xhtml", "c": "urn:oasis:names:tc:opendocument:xmlns:container"}
EPUB = "{http://www.idpf.org/2007/ops}"


def resolve(source: str, reference: str) -> tuple[str, str]:
    uri = urllib.parse.urlsplit(reference)
    assert not uri.scheme and not uri.netloc, f"External reference: {reference}"
    path = urllib.parse.unquote(uri.path)
    assert not path.startswith("/") and "\\" not in path
    target = posixpath.normpath(posixpath.join(posixpath.dirname(source), path)) if path else source
    assert not target.startswith("../"), reference
    return target, urllib.parse.unquote(uri.fragment)


def validate(language: str, metadata: dict) -> dict:
    output = ROOT / "dist" / f"shiori-demo-{language}.epub"
    lang = "zh-CN" if language == "zh" else "en"
    with zipfile.ZipFile(output) as z:
        entries = z.infolist()
        names = z.namelist()
        assert len(names) == len(set(names))
        assert entries[0].filename == "mimetype" and entries[0].compress_type == zipfile.ZIP_STORED
        assert z.read("mimetype") == b"application/epub+zip" and z.testzip() is None
        assert all(not p.startswith("/") and ".." not in p.split("/") for p in names)
        container = ET.fromstring(z.read("META-INF/container.xml"))
        package_name = container.find("c:rootfiles/c:rootfile", NS).attrib["full-path"]
        package = ET.fromstring(z.read(package_name))
        assert package.attrib["version"] == "3.0"
        assert package.find("opf:metadata/dc:language", NS).text == lang
        assert package.find("opf:metadata/dc:title", NS).text == metadata["title"][lang]
        uid = package.attrib["unique-identifier"]
        assert package.find(f"opf:metadata/dc:identifier[@id='{uid}']", NS) is not None
        items = {e.attrib["id"]: e.attrib for e in package.findall("opf:manifest/opf:item", NS)}
        assert sum("nav" in i.get("properties", "").split() for i in items.values()) == 1
        assert sum("cover-image" in i.get("properties", "").split() for i in items.values()) == 1
        manifested = {resolve(package_name, i["href"])[0] for i in items.values()}
        assert manifested == set(names) - {"mimetype", "META-INF/container.xml", package_name}
        spine = [i.attrib["idref"] for i in package.findall("opf:spine/opf:itemref", NS)]
        chapters = [r["id"] for r in metadata["chapters"]]
        assert [i for i in spine if i.startswith("chapter-")] == chapters
        assert all(i in items for i in spine) and len(spine) == len(set(spine))
        docs, ids = {}, {}
        image_count, link_count, paragraph_count = 0, 0, 0
        for name in names:
            if name.endswith((".xhtml", ".xml", ".opf")):
                data = z.read(name)
                assert b"<!ENTITY" not in data
                doc = ET.fromstring(data)
                docs[name] = doc
                identifiers = [e.attrib["id"] for e in doc.iter() if "id" in e.attrib]
                assert len(identifiers) == len(set(identifiers)), name
                ids[name] = set(identifiers)
                assert not any(e.tag.rsplit("}", 1)[-1] in {"script", "iframe", "object"} for e in doc.iter())
                if name.endswith(".xhtml"):
                    assert doc.attrib["{http://www.w3.org/XML/1998/namespace}lang"] == lang
                    assert doc.find("h:head/h:title", NS).text
            if name.endswith(".jpg"):
                with Image.open(io.BytesIO(z.read(name))) as image:
                    assert image.size == (1024, 1536) and image.format == "JPEG"
                    image.verify()
                image_count += 1
        for name, doc in docs.items():
            for element in doc.iter():
                for attribute in ("href", "src"):
                    if attribute not in element.attrib:
                        continue
                    target, fragment = resolve(name, element.attrib[attribute])
                    assert target in names, (name, target)
                    if fragment:
                        assert fragment in ids.get(target, set()), (target, fragment)
                    if element.tag == "{" + NS["h"] + "}a":
                        link_count += 1
                if element.tag == "{" + NS["h"] + "}img":
                    assert element.attrib.get("alt", "").strip()
        assert image_count == 4
        nav = docs["OEBPS/text/nav.xhtml"]
        toc = next(e for e in nav.findall(".//h:nav", NS) if e.attrib.get(EPUB + "type") == "toc")
        toc_links = toc.findall(".//h:a", NS)
        assert len(toc_links) == 7
        assert [e.text for e in toc_links] == [r[language] for r in metadata["chapters"]]
        all_paragraphs = []
        for row in metadata["chapters"]:
            source = (ROOT / "story" / language / f'{row["id"]}.txt').read_text("utf-8")
            title, prose = source.split("\n", 1)
            paragraphs = [p.strip() for p in prose.strip().split("\n\n") if p.strip()]
            doc = docs[f'OEBPS/text/{row["id"]}.xhtml']
            assert doc.find(".//h:h1", NS).text == title
            rendered = ["".join(e.itertext()) for e in doc.findall(".//h:p", NS)]
            assert rendered == paragraphs, f"Missing, reordered or altered prose: {row['id']}"
            paragraph_count += len(paragraphs)
            all_paragraphs += paragraphs
        duplicates = [p for p, n in collections.Counter(all_paragraphs).items() if n > 1 and len(p) >= 50]
        assert not duplicates, "Repeated long paragraphs"
        css = z.read("OEBPS/styles/book.css").decode("utf-8")
        assert not re.search(r"@import|url\(|@font-face|position\s*:", css, re.I)
        assert not any(n.lower().endswith((".ttf", ".otf", ".woff", ".js")) for n in names)
        text = "".join(all_paragraphs)
        counts = {"paragraphs": paragraph_count, "nonWhitespaceCharacters": len(re.sub(r"\s", "", text))}
        if language == "zh":
            counts["hanCharacters"] = len(re.findall(r"[\u3400-\u9fff]", text))
            assert 15000 <= counts["hanCharacters"] <= 22000
        else:
            counts["words"] = len(re.findall(r"\b[\w]+(?:['’-][\w]+)*\b", text))
            assert counts["words"] > 7000
        for term in metadata["search_terms"][lang]:
            assert sum(term in p for p in all_paragraphs) >= 3
        return {"language": lang, "chapters": 7, "images": image_count, "links": link_count,
                **counts, "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}


def main() -> None:
    metadata = json.loads((ROOT / "metadata.json").read_text("utf-8"))
    for language in ("zh", "en"):
        print(json.dumps(validate(language, metadata), ensure_ascii=False))
    for line in (ROOT / "dist/SHA256SUMS.txt").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        assert hashlib.sha256((ROOT / "dist" / name).read_bytes()).hexdigest() == digest
    print("ZIP, XML, OPF, navigation, every reference, every source paragraph, images and checksums passed.")


if __name__ == "__main__":
    main()
