"""Internal, cross-job verification receipts; never uploaded to a Release."""

import hashlib
import json
from pathlib import Path


def file_record(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 2 * 1024**3:
        raise ValueError("Invalid release package")
    with path.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    return dict(name=path.name, size=path.stat().st_size, sha256=digest)


def write_receipt(assets, platform, expected, paths, **properties):
    directory = assets / "receipts"
    directory.mkdir(parents=True, exist_ok=True)
    value = dict(schemaVersion=1, identity=expected, platform=platform,
                 packages=[file_record(path) for path in paths], **properties)
    (directory / f"{platform}.json").write_text(
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
