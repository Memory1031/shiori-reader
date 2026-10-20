import base64
from copy import deepcopy
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

from publish_altstore import (BRANCH, SOURCE_FILES, api, empty_source,
                              main, publish_source, release_entry, update_source)
from publish_assets import REPOSITORY
from release_android import ReleaseCheckError
from release_receipt import file_record
from test_release_ios import fixture_app, package
from update_manifest import encoded, identity


class AltStoreTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="shiori-altstore-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "pubspec.yaml").write_text("version: 1.2.1+11\n")
        self.assets = self.root / "assets"
        self.tag, self.commit = "v1.2.1-beta.1", "a" * 40
        expected = identity("version: 1.2.1+11", self.tag, self.commit)
        app = fixture_app(self.root, expected)
        path = app / "Info.plist"
        info = plistlib.loads(path.read_bytes())
        info["NSPhotoLibraryAddUsageDescription"] = "Save illustrations."
        path.write_bytes(plistlib.dumps(info))
        package(self.root, app, self.assets, self.tag, self.commit)
        self.path = self.assets / f"shiori-reader-{self.tag}-ios-arm64-unsigned.ipa"
        self.record = file_record(self.path)
        self.release = dict(tag_name=self.tag, draft=False, prerelease=True,
                            published_at="2026-10-20T01:00:00Z", body="Release notes", assets=[{
                                "id": 123, "name": self.path.name, "size": self.record["size"],
                                "digest": "sha256:" + self.record["sha256"],
                                "browser_download_url": f"https://github.com/{REPOSITORY}/releases/download/{self.tag}/{self.path.name}",
                            }])

    def entry(self):
        return release_entry(self.root, self.assets, self.tag, self.commit, self.release)

    def test_verified_ipa_metadata_and_permissions(self):
        channel, entry, permissions = self.entry()
        self.assertEqual(channel, "beta")
        self.assertEqual((entry["version"], entry["buildVersion"], entry["minOSVersion"]),
                         ("1.2.1", "11", "15.0"))
        self.assertEqual(entry["size"], self.path.stat().st_size)
        self.assertEqual(entry["sha256"], self.record["sha256"])
        self.assertEqual(permissions["privacy"], {"NSPhotoLibraryAddUsageDescription": "Save illustrations."})
        source = update_source(empty_source(channel), channel, entry, permissions)
        self.assertEqual(source["apps"][0]["versions"], [entry])

    def test_incomplete_wrong_channel_or_modified_public_asset_rejected(self):
        for changes in [dict(draft=True), dict(prerelease=False), dict(tag_name="v1.2.0"),
                        dict(assets=[]), dict(published_at="invalid")]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                release_entry(self.root, self.assets, self.tag, self.commit, {**self.release, **changes})
        asset = self.release["assets"][0]
        for changes in [dict(size=1), dict(digest="sha256:" + "0" * 64),
                        dict(browser_download_url="https://example.com/other.ipa")]:
            with self.subTest(changes=changes), self.assertRaises(ReleaseCheckError):
                release_entry(self.root, self.assets, self.tag, self.commit,
                              {**self.release, "assets": [{**asset, **changes}]})
        self.path.write_bytes(self.path.read_bytes() + b"changed")
        with self.assertRaises(ReleaseCheckError):
            self.entry()

    def test_stable_release_is_available_to_both_sources(self):
        self.tag = "v1.2.1"
        package(self.root, self.root / "Runner.app", self.assets, self.tag, self.commit)
        self.path = self.assets / f"shiori-reader-{self.tag}-ios-arm64-unsigned.ipa"
        record = file_record(self.path)
        self.release.update(tag_name=self.tag, prerelease=False, assets=[{
            "id": 124, "name": self.path.name, "size": record["size"],
            "digest": "sha256:" + record["sha256"],
            "browser_download_url": f"https://github.com/{REPOSITORY}/releases/download/{self.tag}/{self.path.name}",
        }])
        channel, entry, permissions = self.entry()
        self.assertEqual(channel, "stable")
        source = update_source(empty_source(channel), channel, entry, permissions)
        self.assertEqual(source["apps"][0]["versions"][0]["marketingVersion"], "1.2.1")
        beta = update_source(empty_source("beta"), "beta", entry, permissions)
        self.assertEqual(beta["apps"][0]["versions"], source["apps"][0]["versions"])

    def test_publish_command_routes_releases_to_subscribed_channels(self):
        _, entry, permissions = self.entry()
        for channel, targets in [("stable", ["stable", "beta"]), ("beta", ["beta"])]:
            with self.subTest(channel=channel), patch.dict(os.environ, {
                "GITHUB_REF_NAME": self.tag, "GITHUB_SHA": self.commit,
            }), patch("sys.argv", ["publish_altstore.py", "--publish"]), \
                    patch("publish_altstore.gh", return_value=b"{}"), \
                    patch("publish_altstore.release_entry", return_value=(channel, entry, permissions)), \
                    patch("publish_altstore.publish_source") as publish:
                main()
                self.assertEqual([call.args[0] for call in publish.call_args_list], targets)

    def test_missing_github_digest_checks_remote_bytes(self):
        self.release["assets"][0].pop("digest")
        channel, entry, _ = release_entry(self.root, self.assets, self.tag, self.commit,
                                         self.release, run=lambda *args: self.path.read_bytes())
        self.assertEqual((channel, entry["sha256"]), ("beta", self.record["sha256"]))
        with self.assertRaises(ReleaseCheckError):
            release_entry(self.root, self.assets, self.tag, self.commit,
                          self.release, run=lambda *args: b"different remote IPA")

    def test_retry_is_idempotent_and_older_build_cannot_become_latest(self):
        channel, entry, permissions = self.entry()
        source = update_source(empty_source(channel), channel, entry, permissions)
        source = update_source(source, channel, entry, permissions)
        self.assertEqual(len(source["apps"][0]["versions"]), 1)
        newer = {**entry, "buildVersion": "12", "marketingVersion": "1.2.1-beta.2"}
        source = update_source(source, channel, newer, permissions)
        source = update_source(source, channel, entry, permissions)
        self.assertEqual([v["buildVersion"] for v in source["apps"][0]["versions"]], ["12", "11"])
        with self.assertRaises(ReleaseCheckError):
            update_source(source, channel, {**entry, "sha256": "0" * 64}, permissions)

    def test_channels_and_checked_in_sources_match(self):
        for channel, name in SOURCE_FILES.items():
            source = json.loads(Path(name).read_text(encoding="utf-8"))
            for key in ("name", "identifier", "sourceURL"):
                self.assertEqual(source[key], empty_source(channel)[key])
            self.assertLessEqual(len(source["apps"]), 1)
            for app in source["apps"]:
                self.assertEqual(app["bundleIdentifier"], "dev.shiori.reader")
                versions = app["versions"]
                builds = [int(v["buildVersion"]) for v in versions]
                self.assertEqual(builds, sorted(set(builds), reverse=True))
                for version in versions:
                    if channel == "stable":
                        self.assertNotIn("-beta.", version["marketingVersion"])
                    self.assertGreater(version["size"], 0)
                    self.assertRegex(version["sha256"], r"^[0-9a-f]{64}$")
        channel, entry, permissions = self.entry()
        with self.assertRaises(ReleaseCheckError):
            update_source(empty_source("stable"), channel, entry, permissions)

    def test_branch_publication_preserves_latest_tree_and_retries_conflict(self):
        channel, entry, permissions = self.entry()
        calls, trees, commits = [], [], []
        source = empty_source(channel)
        attempts = 0

        def request(endpoint, payload=None, method=None):
            nonlocal attempts, source
            calls.append((endpoint, payload, method))
            if endpoint == f"git/ref/heads/{BRANCH}":
                return {"object": {"sha": f"head-{attempts}"}}
            if endpoint.startswith(f"contents/{SOURCE_FILES[channel]}?ref="):
                return {"content": base64.b64encode(encoded(source)).decode()}
            if endpoint.startswith("git/commits/head-"):
                return {"tree": {"sha": f"base-{attempts}"}}
            if endpoint == "git/trees":
                trees.append(deepcopy(payload))
                return {"sha": "new-tree"}
            if endpoint == "git/commits":
                commits.append(payload)
                return {"sha": "new-commit"}
            if endpoint == f"git/refs/heads/{BRANCH}":
                self.assertEqual(payload, {"sha": "new-commit", "force": False})
                attempts += 1
                if attempts == 1:
                    # A concurrent source update must survive our retry too.
                    source = update_source(source, channel, {**entry, "buildVersion": "12"}, permissions)
                    return None
                return {"ref": f"refs/heads/{BRANCH}"}
            self.fail(endpoint)

        publish_source(channel, entry, permissions, request)
        self.assertEqual([tree["base_tree"] for tree in trees], ["base-0", "base-1"])
        self.assertEqual([commit["parents"] for commit in commits], [["head-0"], ["head-1"]])
        self.assertEqual([t["tree"][0]["path"] for t in trees], [SOURCE_FILES[channel]] * 2)
        result = json.loads(trees[-1]["tree"][0]["content"])
        self.assertEqual([v["buildVersion"] for v in result["apps"][0]["versions"]], ["12", "11"])
        self.assertFalse(any(SOURCE_FILES["stable"] in endpoint for endpoint, _, _ in calls))
        source = result
        calls.clear()
        publish_source(channel, entry, permissions, request)
        self.assertFalse(any(payload is not None for _, payload, _ in calls))

    def test_branch_rejection_is_bounded(self):
        channel, entry, permissions = self.entry()
        def request(endpoint, payload=None, method=None):
            if endpoint.startswith("git/ref/"):
                return {"object": {"sha": "head"}}
            if endpoint.startswith("contents/"):
                return {"content": base64.b64encode(encoded(empty_source(channel))).decode()}
            if endpoint == "git/commits/head":
                return {"tree": {"sha": "base"}}
            return None if method == "PATCH" else {"sha": "created"}
        with self.assertRaises(ReleaseCheckError):
            publish_source(channel, entry, permissions, request)

    def test_api_uses_structured_input_and_never_force_pushes(self):
        with patch("publish_altstore.subprocess.run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = b'{"ref":"refs/heads/develop"}'
            api("git/refs/heads/develop", {"sha": "a" * 40, "force": False}, "PATCH")
            self.assertEqual(json.loads(run.call_args.kwargs["input"])["force"], False)
            run.return_value.returncode = 1
            run.return_value.stderr = b"Update is not a fast forward (HTTP 422)"
            self.assertIsNone(api("git/refs/heads/develop", {}, "PATCH"))
            run.return_value.stderr = b"Protected branch update failed (HTTP 403)"
            with self.assertRaises(ReleaseCheckError):
                api("git/refs/heads/develop", {}, "PATCH")


if __name__ == "__main__":
    unittest.main()
