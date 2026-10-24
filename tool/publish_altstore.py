"""Publish AltStore Classic sources on develop after a complete public Release."""

import argparse
import base64
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import zipfile

from publish_assets import REPOSITORY, asset_bytes, gh
from release_android import ReleaseCheckError
from release_ios import PREFIX, verify_assets
from release_receipt import file_record
from update_manifest import APPLICATION_ID, encoded, identity, read_json

BRANCH = "develop"
SOURCE_FILES = {"stable": "alt_store.json", "beta": "alt_store_beta.json"}
RAW_URL = f"https://raw.githubusercontent.com/{REPOSITORY}/{BRANCH}"


def source_bytes(source):
    return (json.dumps(source, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def empty_source(channel):
    return {
        "name": "Shiori" + (" Beta" if channel == "beta" else ""),
        "identifier": f"{APPLICATION_ID}.altstore.{channel}",
        "sourceURL": f"{RAW_URL}/{SOURCE_FILES[channel]}",
        "apps": [],
        "news": [],
    }


def release_entry(root, assets, tag, commit, release, run=gh):
    expected = identity((root / "pubspec.yaml").read_text(encoding="utf-8"), tag, commit)
    names = verify_assets(root, assets, tag, commit)
    path = assets / names.pop()
    record = file_record(path)
    if (release.get("draft") is not False or release.get("tag_name") != tag
            or release.get("prerelease") is not (expected["channel"] == "beta")):
        raise ReleaseCheckError("AltStore requires a public Release in the correct channel")
    datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
    matches = [a for a in release["assets"] if a["name"] == path.name]
    url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{path.name}"
    if (len(matches) != 1 or matches[0]["size"] != record["size"]
            or matches[0]["browser_download_url"] != url):
        raise ReleaseCheckError("Public IPA does not match the verified package")
    digest = matches[0].get("digest")
    if not digest:
        digest = "sha256:" + hashlib.sha256(asset_bytes(matches[0], run)).hexdigest()
    if digest != "sha256:" + record["sha256"]:
        raise ReleaseCheckError("Public IPA digest does not match the verified package")
    with zipfile.ZipFile(path) as archive:
        info = plistlib.loads(archive.read(PREFIX + "Info.plist"))
        privacy = {}
        for name in archive.namelist():
            if name == PREFIX + "Info.plist" or (name.startswith(PREFIX + "PlugIns/")
                                                 and name.endswith(".appex/Info.plist")):
                for key, value in plistlib.loads(archive.read(name)).items():
                    if key.startswith("NS") and key.endswith("UsageDescription"):
                        privacy[key] = value
    entry = {
        "version": info["CFBundleShortVersionString"],
        "buildVersion": info["CFBundleVersion"],
        "marketingVersion": tag.removeprefix("v"),
        "date": release["published_at"],
        "localizedDescription": release.get("body") or tag,
        "downloadURL": url,
        "size": record["size"],
        "sha256": record["sha256"],
        "minOSVersion": info["MinimumOSVersion"],
    }
    # Signing material is removed from the IPA. Declare the sharing capability
    # used by Runner and ShareExtension; the sideloading tool owns re-signing.
    permissions = {"entitlements": ["com.apple.security.application-groups"], "privacy": privacy}
    return expected["channel"], entry, permissions


def update_source(source, channel, entry, permissions):
    if any(source.get(key) != value for key, value in empty_source(channel).items()
           if key not in {"apps", "news"}):
        raise ReleaseCheckError("Unexpected AltStore source identity")
    if len(source["apps"]) > 1:
        raise ReleaseCheckError("Unexpected AltStore application list")
    app = source["apps"][0] if source["apps"] else {
        "name": source["name"],
        "bundleIdentifier": APPLICATION_ID,
        "developerName": "Memory1031",
        "iconURL": f"{RAW_URL}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png",
        "localizedDescription": "开源轻小说阅读器 / Open-source EPUB and TXT reader. "
                                "Install and update with AltStore Classic.",
        "versions": [],
        "appPermissions": {"entitlements": [], "privacy": {}},
    }
    if app["bundleIdentifier"] != APPLICATION_ID:
        raise ReleaseCheckError("Unexpected AltStore bundle identifier")
    versions = app["versions"]
    for previous in versions:
        if previous["buildVersion"] == entry["buildVersion"]:
            # Release descriptions may be edited, but package identity is immutable.
            fields = {"version", "buildVersion", "downloadURL", "size", "sha256", "minOSVersion"}
            if any(previous.get(key) != entry[key] for key in fields):
                raise ReleaseCheckError("AltStore build already references a different package")
    versions = [v for v in versions if v["buildVersion"] != entry["buildVersion"]] + [entry]
    # Build numbers are globally increasing. Retrying an older tag must not
    # move it to the front: AltStore treats array order as update priority.
    app["versions"] = sorted(versions, key=lambda v: int(v["buildVersion"]), reverse=True)
    app["appPermissions"]["entitlements"] = sorted(set(
        app["appPermissions"]["entitlements"] + permissions["entitlements"]))
    app["appPermissions"]["privacy"].update(permissions["privacy"])
    source["apps"] = [app]
    return source


def api(endpoint, payload=None, method=None):
    args = ["gh", "api", f"repos/{REPOSITORY}/{endpoint}"]
    if method:
        args += ["--method", method]
    if payload is not None:
        args += ["--input", "-"]
    result = subprocess.run(args, input=encoded(payload) if payload is not None else None,
                            capture_output=True, check=False)
    if result.returncode:
        # Non-fast-forward updates are retried from the latest develop tree.
        if method == "PATCH" and b"HTTP 422" in result.stderr:
            return None
        raise ReleaseCheckError("AltStore GitHub operation failed; inspect branch permissions and remote state")
    return read_json(result.stdout)


def publish_source(channel, entry, permissions, request=api):
    for _ in range(3):
        head = request(f"git/ref/heads/{BRANCH}")["object"]["sha"]
        content = request(f"contents/{SOURCE_FILES[channel]}?ref={head}")
        raw = base64.b64decode(content["content"])
        source = update_source(read_json(raw), channel, entry, permissions)
        updated = source_bytes(source)
        if raw == updated:
            return
        base = request(f"git/commits/{head}")["tree"]["sha"]
        tree = request("git/trees", {"base_tree": base, "tree": [{
            "path": SOURCE_FILES[channel], "mode": "100644", "type": "blob",
            "content": updated.decode("utf-8"),
        }]})["sha"]
        commit = request("git/commits", {
            "message": f"chore: update AltStore {channel} source\n\n- iOS: publish {entry['marketingVersion']} ({entry['buildVersion']})",
            "tree": tree, "parents": [head],
        })["sha"]
        if request(f"git/refs/heads/{BRANCH}", {"sha": commit, "force": False}, "PATCH") is not None:
            return
        if request(f"git/ref/heads/{BRANCH}")["object"]["sha"] == head:
            raise ReleaseCheckError("AltStore branch update rejected; inspect develop branch protections")
    raise ReleaseCheckError("Develop changed during AltStore publication; retry the workflow")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, default=Path("build/release-assets"))
    parser.add_argument("--publish", action="store_true", help="Update the source on develop (otherwise preview only)")
    args = parser.parse_args()
    tag, commit = os.environ["GITHUB_REF_NAME"], os.environ["GITHUB_SHA"]
    release = json.loads(gh("api", f"repos/{REPOSITORY}/releases/tags/{tag}"))
    channel, entry, permissions = release_entry(Path.cwd(), args.assets, tag, commit, release)
    if args.publish:
        for target in (["stable", "beta"] if channel == "stable" else ["beta"]):
            publish_source(target, entry, permissions)
    else:
        print(source_bytes(update_source(empty_source(channel), channel, entry, permissions)).decode("utf-8"), end="")


if __name__ == "__main__":
    try:
        main()
    except ReleaseCheckError as error:
        raise SystemExit(f"AltStore publication stopped: {error}. The GitHub Release remains available.")
    except (ValueError, OSError, KeyError, TypeError):
        raise SystemExit("AltStore publication stopped; the GitHub Release remains available. Inspect the source and retry.")
