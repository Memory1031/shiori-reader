"""Publish verified assets without replacing the contents of an existing release."""

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path

from release_android import ReleaseCheckError
from update_manifest import create_manifest, read_json, sha, verify_signature

REPOSITORY = "Memory1031/shiori-reader"


def gh(*args):
    result = subprocess.run(["gh", *args], capture_output=True, check=False)
    if result.returncode:
        raise ReleaseCheckError(
            "GitHub release operation failed; inspect remote state before retrying"
        )
    return result.stdout


def asset_bytes(asset, run=gh):
    return run(
        "api",
        f"repos/{REPOSITORY}/releases/assets/{asset['id']}",
        "-H",
        "Accept: application/octet-stream",
    )


def validate_history(manifest, releases, files, run=gh):
    current = None
    for release in releases:
        if release["tag_name"] == manifest["tag"]:
            current = release
            continue
        if release["draft"]:
            continue
        metadata = next(
            (
                asset
                for asset in release["assets"]
                if asset["name"] == "release-info.json"
            ),
            None,
        )
        if metadata is None or metadata["size"] > 65536:
            raise ReleaseCheckError("Cannot establish published build history")
        previous = read_json(asset_bytes(metadata, run))
        number = previous.get("versionCode")
        if type(number) is not int or number >= manifest["build"]:
            raise ReleaseCheckError(
                "Build must be greater than every previously published build"
            )
    missing = dict(files)
    if current:
        for asset in current["assets"]:
            name = asset["name"]
            if name not in files:
                raise ReleaseCheckError("Existing release contains unexpected assets")
            path = files[name]
            digest = asset.get("digest")
            if not digest:
                digest = "sha256:" + hashlib.sha256(asset_bytes(asset, run)).hexdigest()
            if asset["size"] != path.stat().st_size or digest != "sha256:" + sha(path):
                raise ReleaseCheckError(
                    "Published asset differs: allocate a new build and tag"
                )
            missing.pop(name)
    return current, missing


def publish(root, assets, tag, commit, key, run=gh):
    raw = (assets / "update-manifest.json").read_bytes()
    verify_signature(raw, (assets / "update-manifest.sig").read_bytes(), key)
    if raw != create_manifest(root, assets, tag, commit, key):
        raise ReleaseCheckError("Signed manifest differs from prepared assets")
    manifest = read_json(raw)
    if manifest["tag"] != tag or manifest["commit"] != commit:
        raise ReleaseCheckError("Publish identity mismatch")
    names = {item["name"] for item in manifest["assets"]} | {
        "release-info.json",
        "release-info-windows-x64.json",
        "SHA256SUMS.txt",
        "SHA256SUMS-windows-x64.txt",
        "update-manifest.json",
        "update-manifest.sig",
    }
    files = {path.name: path for path in assets.iterdir() if path.is_file()}
    if set(files) != names or any(path.is_symlink() for path in files.values()):
        raise ReleaseCheckError("Unexpected or missing publish assets")
    pages = json.loads(
        run("api", "--paginate", "--slurp", f"repos/{REPOSITORY}/releases?per_page=100")
    )
    releases = [release for page in pages for release in page]
    current, missing = validate_history(manifest, releases, files, run)
    if current is None:
        notes = root / "docs/release/notes" / f"{tag}.md"
        run(
            "release",
            "create",
            tag,
            "--repo",
            REPOSITORY,
            "--verify-tag",
            "--draft",
            "--title",
            tag,
            *(
                ["--prerelease", "--latest=false"]
                if manifest["channel"] == "beta"
                else []
            ),
            *(["--notes-file", str(notes)] if notes.exists() else ["--generate-notes"]),
        )
    if missing:
        run("release", "upload", tag, "--repo", REPOSITORY, *map(str, missing.values()))
    # Publishing last makes a partially uploaded release invisible to update clients.
    run(
        "release",
        "edit",
        tag,
        "--repo",
        REPOSITORY,
        "--draft=false",
        *(
            ["--prerelease", "--latest=false"]
            if manifest["channel"] == "beta"
            else ["--prerelease=false", "--latest"]
        ),
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, default=Path("build/release-assets"))
    args = parser.parse_args()
    try:
        publish(
            Path.cwd(),
            args.assets,
            os.environ["GITHUB_REF_NAME"],
            os.environ["GITHUB_SHA"],
            read_json(os.environ.get("UPDATE_PUBLIC_KEY_JSON", "{}")),
        )
    except (ValueError, OSError, KeyError, TypeError):
        raise SystemExit(
            "Release publication stopped. Check build ordering and existing asset digests; assets were not overwritten."
        )
