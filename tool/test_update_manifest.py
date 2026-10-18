import base64
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from publish_assets import publish, validate_history
from test_release_ios import fixture_app, package as package_ios
from release_android import ReleaseCheckError
from release_receipt import write_receipt
from update_manifest import (ALGORITHM, APPLICATION_ID, IDENTITY_ASSET, ENVELOPE_NAME,
    PACKAGE_SUFFIXES, create_manifest, encoded, envelope, identity,
    key_from_private, openssl, read_envelope, safe_path, sha, sign_manifest)


class UpdateManifestTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key_dir = tempfile.TemporaryDirectory(prefix="shiori-update-test-key-")
        cls.addClassCleanup(cls.key_dir.cleanup)
        private = Path(cls.key_dir.name) / "private.pem"
        private.write_bytes(openssl("genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:3072"))
        cls.secret, cls.key = private.read_bytes(), key_from_private(private)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="shiori-update-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.commit = "a" * 40
        (self.root / "pubspec.yaml").write_text("version: 1.2.1+11\n", encoding="utf-8")
        self.prepare("v1.2.1-beta.1")

    def prepare(self, tag):
        self.tag = tag
        self.assets = self.root / tag
        self.assets.mkdir()
        self.expected = identity("version: 1.2.1+11", self.tag, self.commit)
        self.bundled = encoded(dict(schemaVersion=1, identity=self.expected, publicKey=self.key))
        for platform in ["android", "windows-x64-portable"]:
            with zipfile.ZipFile(self.path(platform), "w") as package:
                if platform == "android":
                    package.writestr("assets/flutter_assets/" + IDENTITY_ASSET, self.bundled)
                else:
                    package.writestr("shiori.exe", b"synthetic exe")
                    package.writestr("data/app.so", b"synthetic aot")
                    package.writestr("data/flutter_assets/" + IDENTITY_ASSET, self.bundled)
        # Unit fixtures stand in for artifacts verified by native build jobs.
        self.path("windows-x64-setup").write_bytes(b"MZ synthetic setup fixture")
        self.path("macos-universal").write_bytes(b"synthetic DMG fixture")
        self.receipts()
        fixture_root = self.root / ("fixture-" + tag)
        fixture_root.mkdir()
        package_ios(self.root, fixture_app(fixture_root, self.expected), self.assets, self.tag, self.commit)

    def path(self, platform):
        return self.assets / f"shiori-reader-{self.tag}-{PACKAGE_SUFFIXES[platform]}"

    def receipts(self):
        write_receipt(self.assets, "android", self.expected, [self.path("android")], certificateSha256="b" * 64)
        write_receipt(self.assets, "windows-x64", self.expected,
                      [self.path("windows-x64-portable"), self.path("windows-x64-setup")])
        write_receipt(self.assets, "macos-universal", self.expected, [self.path("macos-universal")])

    def manifest(self):
        return create_manifest(self.root, self.assets, self.tag, self.commit, self.key)

    def signed(self):
        raw = self.manifest()
        data = envelope(raw, sign_manifest(raw, self.secret, self.key))
        (self.assets / ENVELOPE_NAME).write_bytes(data)
        return data

    def test_complete_envelope_and_raw_byte_signature(self):
        raw, signature, manifest = read_envelope(self.signed(), self.key, self.tag)
        self.assertEqual(manifest["build"], 11)
        self.assertEqual(manifest["channel"], "beta")
        self.assertEqual(manifest["algorithm"], ALGORITHM)
        self.assertEqual([a["platform"] for a in manifest["assets"]],
                         ["android", "windows-x64-portable", "windows-x64-setup", "macos-universal"])
        self.assertEqual(manifest["assets"][1]["files"][0]["path"], "data/app.so")
        self.assertEqual(raw, self.manifest())
        self.assertEqual(len(signature), 384)
        self.assertEqual(signature, sign_manifest(raw, self.secret, self.key))
        value = json.loads(self.signed())
        for edit in [dict(manifest=base64.b64encode(raw + b" ").decode()),
                     dict(signature=base64.b64encode(b"0" * 384).decode()),
                     dict(schemaVersion=1), dict(manifest="bad")]:
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                read_envelope(encoded({**value, **edit}), self.key, self.tag)
        with self.assertRaises(ValueError):
            read_envelope(self.signed().replace(b'"schemaVersion":2', b'"schemaVersion":2,"schemaVersion":2'), self.key)
        with self.assertRaises(ValueError):
            read_envelope(self.signed(), self.key, "v1.2.2")

    def test_missing_asset_stale_receipt_and_wrong_key_rejected(self):
        receipt = self.assets / "receipts/android.json"
        value = json.loads(receipt.read_bytes())
        for field, replacement in [("identity", {**self.expected, "build": 10}),
                                   ("certificateSha256", "invalid"), ("packages", [])]:
            receipt.write_bytes(encoded({**value, field: replacement}))
            with self.subTest(field=field), self.assertRaises(ReleaseCheckError):
                self.manifest()
        receipt.write_bytes(encoded(value))
        for platform in PACKAGE_SUFFIXES:
            path = self.path(platform)
            saved = path.read_bytes()
            path.write_bytes(saved + b"tampered")
            with self.subTest(platform=platform), self.assertRaises(ReleaseCheckError):
                self.manifest()
            path.write_bytes(saved)
        with self.assertRaises(ReleaseCheckError):
            sign_manifest(self.manifest(), self.secret, {**self.key, "keyId": "0" * 64})

    def test_zip_paths_and_embedded_identity_checked(self):
        for path in ["../shiori.exe", "/shiori.exe", "C:/shiori.exe", "con.txt", "x\\y", "a:b", "a./b", "x/NUL"]:
            self.assertFalse(safe_path(path), path)
        archive = self.path("windows-x64-portable")
        original = archive.read_bytes()
        for bad in ["../escape", "SHIORI.EXE", "data"]:
            archive.write_bytes(original)
            with zipfile.ZipFile(archive, "a") as package:
                package.writestr(bad, "bad")
            self.receipts()
            with self.subTest(path=bad), self.assertRaises(ReleaseCheckError):
                self.manifest()
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("shiori.exe", b"exe")
            package.writestr("data/app.so", b"aot")
            package.writestr("data/flutter_assets/" + IDENTITY_ASSET, b'{"schemaVersion":1,"development":true}')
        self.receipts()
        with self.assertRaises(ReleaseCheckError):
            self.manifest()

    def test_build_history_and_immutable_reruns(self):
        manifest = json.loads(self.manifest())
        file = self.path("android")
        files = {file.name: file}
        previous = dict(tag_name="v1.2.0", draft=False, assets=[dict(name="release-info.json", id=1, size=200)])
        for number in [11, 21, "10", True]:
            with self.subTest(number=number), self.assertRaises(ReleaseCheckError):
                validate_history(manifest, [previous], files, lambda *args: encoded(dict(versionCode=number)))
        validate_history(manifest, [previous], files, lambda *args: encoded(dict(versionCode=10)))
        historical = {**manifest, "build": 10, "tag": "v1.2.0", "version": "1.2.0", "channel": "stable"}
        raw = encoded(historical)
        data = envelope(raw, sign_manifest(raw, self.secret, self.key))
        previous["assets"] = [dict(name=ENVELOPE_NAME, id=2, size=len(data))]
        validate_history(manifest, [previous], files, lambda *args: data, self.key)
        with self.assertRaises(ValueError):
            validate_history(manifest, [previous], files, lambda *args: data + b"invalid", self.key)
        current = dict(tag_name=self.tag, draft=False, assets=[dict(name=file.name, id=2, size=file.stat().st_size, digest="sha256:" + sha(file))])
        self.assertEqual(validate_history(manifest, [current], files)[1], {})
        current["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaises(ReleaseCheckError):
            validate_history(manifest, [current], files)

    def test_publisher_draft_upload_then_publish_and_rerun_no_overwrite(self):
        self.signed()
        calls = []
        def run(*args):
            calls.append(args)
            return b"[[]]" if args[0] == "api" else b""
        publish(self.root, self.assets, self.tag, self.commit, self.key, run)
        self.assertEqual([args[:2] for args in calls[1:]], [("release", "create"), ("release", "upload"), ("release", "edit")])
        self.assertIn("--draft", calls[1])
        self.assertIn("--latest=false", calls[-1])
        self.assertEqual({Path(x).name for x in calls[2][5:]},
                         {self.path(p).name for p in PACKAGE_SUFFIXES} | {ENVELOPE_NAME})
        self.assertFalse(any("--clobber" in args for args in calls))
        release = dict(tag_name=self.tag, draft=False, assets=[
            dict(name=p.name, size=p.stat().st_size, digest="sha256:" + sha(p))
            for p in self.assets.iterdir() if p.is_file()])
        def rerun(*args):
            calls.append(args)
            return encoded([[release]]) if args[0] == "api" else b""
        calls.clear()
        publish(self.root, self.assets, self.tag, self.commit, self.key, rerun)
        self.assertFalse(any(args[:2] == ("release", "upload") for args in calls))
        ipa = self.path("ios-arm64")
        release["assets"] = [a for a in release["assets"] if a["name"] != ipa.name]
        calls.clear()
        publish(self.root, self.assets, self.tag, self.commit, self.key, rerun)
        self.assertEqual(next(a for a in calls if a[:2] == ("release", "upload"))[-1], str(ipa))
        release["assets"].append(dict(name=ipa.name, size=ipa.stat().st_size, digest="sha256:" + "0" * 64))
        calls.clear()
        with self.assertRaises(ReleaseCheckError):
            publish(self.root, self.assets, self.tag, self.commit, self.key, rerun)
        self.assertFalse(any(a[0] == "release" for a in calls))
        calls.clear()
        def fail_upload(*args):
            calls.append(args)
            if args[:2] == ("release", "upload"):
                raise ReleaseCheckError("Interrupted upload")
            return b"[[]]" if args[0] == "api" else b""
        with self.assertRaises(ReleaseCheckError):
            publish(self.root, self.assets, self.tag, self.commit, self.key, fail_upload)
        self.assertFalse(any(a[:2] == ("release", "edit") for a in calls))
        (self.assets / "SHA256SUMS.txt").write_text("obsolete")
        calls.clear()
        with self.assertRaises(ReleaseCheckError):
            publish(self.root, self.assets, self.tag, self.commit, self.key, run)
        self.assertEqual(calls, [])

    def test_stable_publication_marks_latest_only_after_upload(self):
        self.prepare("v1.2.1")
        _, _, manifest = read_envelope(self.signed(), self.key, self.tag)
        self.assertEqual(manifest["channel"], "stable")
        calls = []
        def run(*args):
            calls.append(args)
            return b"[[]]" if args[0] == "api" else b""
        publish(self.root, self.assets, self.tag, self.commit, self.key, run)
        self.assertEqual([args[:2] for args in calls[1:]], [("release", "create"), ("release", "upload"), ("release", "edit")])
        self.assertNotIn("--prerelease", calls[1])
        self.assertIn("--prerelease=false", calls[-1])
        self.assertIn("--latest", calls[-1])


if __name__ == "__main__":
    unittest.main()
