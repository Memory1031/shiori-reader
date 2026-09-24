import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from publish_assets import publish, validate_history
from release_android import ReleaseCheckError
from update_manifest import (
    ALGORITHM,
    APPLICATION_ID,
    IDENTITY_ASSET,
    create_manifest,
    encoded,
    identity,
    key_from_private,
    openssl,
    safe_path,
    sha,
    sign_manifest,
)


class UpdateManifestTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key_dir = tempfile.TemporaryDirectory(prefix="shiori-update-test-key-")
        cls.addClassCleanup(cls.key_dir.cleanup)
        private = Path(cls.key_dir.name) / "private.pem"
        private.write_bytes(
            openssl("genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:3072")
        )
        cls.secret = private.read_bytes()
        cls.key = key_from_private(private)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="shiori-update-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.assets = self.root / "assets"
        self.assets.mkdir()
        (self.root / "pubspec.yaml").write_text("version: 1.2.1+11\n")
        self.tag, self.commit = "v1.2.1-beta.1", "a" * 40
        self.expected = identity("version: 1.2.1+11", self.tag, self.commit)
        self.bundled = encoded(
            {"schemaVersion": 1, "identity": self.expected, "publicKey": self.key}
        )
        for platform, suffix, metadata in [
            ("android", "android.apk", "release-info.json"),
            ("windows-x64", "windows-x64.zip", "release-info-windows-x64.json"),
        ]:
            name = f"shiori-reader-{self.tag}-{suffix}"
            with zipfile.ZipFile(self.assets / name, "w") as package:
                if platform == "android":
                    package.writestr(
                        "assets/flutter_assets/" + IDENTITY_ASSET, self.bundled
                    )
                else:
                    package.writestr("shiori.exe", b"synthetic exe")
                    package.writestr("data/app.so", b"synthetic aot")
                    package.writestr(
                        "data/flutter_assets/" + IDENTITY_ASSET, self.bundled
                    )
            value = {
                "tag": self.tag,
                "commit": self.commit,
                "versionName": "1.2.1",
                "versionCode": 11,
                "sha256": sha(self.assets / name),
            }
            if platform == "android":
                value.update(
                    apk=name, applicationId=APPLICATION_ID, certificateSha256="b" * 64
                )
            else:
                value.update(archive=name, platform=platform)
            (self.assets / metadata).write_bytes(encoded(value))

    def manifest(self):
        return create_manifest(self.root, self.assets, self.tag, self.commit, self.key)

    def test_complete_manifest_binds_identity_assets_and_files(self):
        raw = self.manifest()
        manifest = json.loads(raw)
        self.assertEqual(manifest["build"], 11)
        self.assertEqual(manifest["channel"], "beta")
        self.assertEqual(manifest["algorithm"], ALGORITHM)
        self.assertEqual(manifest["assets"][1]["files"][0]["path"], "data/app.so")
        self.assertEqual(raw, self.manifest())
        signature = sign_manifest(raw, self.secret, self.key)
        self.assertEqual(len(signature), 384)
        self.assertEqual(signature, sign_manifest(raw, self.secret, self.key))
        (self.root / "manifest.json").write_bytes(raw)
        (self.root / "manifest.sig").write_bytes(signature)
        private = Path(self.key_dir.name) / "private.pem"
        public = self.root / "public.pem"
        public.write_bytes(openssl("pkey", "-in", private, "-pubout"))
        openssl(
            "dgst",
            "-sha256",
            "-verify",
            public,
            "-signature",
            self.root / "manifest.sig",
            self.root / "manifest.json",
        )
        (self.root / "manifest.json").write_bytes(raw + b" ")
        with self.assertRaises(ReleaseCheckError):
            openssl(
                "dgst",
                "-sha256",
                "-verify",
                public,
                "-signature",
                self.root / "manifest.sig",
                self.root / "manifest.json",
            )

    def test_missing_asset_stale_metadata_and_wrong_key_rejected(self):
        metadata = self.assets / "release-info.json"
        original = metadata.read_bytes()
        value = json.loads(original)
        for field, replacement in [
            ("versionCode", 10),
            ("commit", "c" * 40),
            ("sha256", "d" * 64),
            ("applicationId", "other.app"),
        ]:
            metadata.write_bytes(encoded({**value, field: replacement}))
            with self.subTest(field=field), self.assertRaises(ReleaseCheckError):
                self.manifest()
        metadata.write_bytes(original)
        with self.assertRaises(ReleaseCheckError):
            sign_manifest(self.manifest(), self.secret, {**self.key, "keyId": "0" * 64})
        metadata.unlink()
        with self.assertRaises(OSError):
            self.manifest()

    def test_zip_paths_and_embedded_identity_checked(self):
        for path in [
            "../shiori.exe",
            "/shiori.exe",
            "C:/shiori.exe",
            "con.txt",
            "x\\y",
            "a:b",
            "a./b",
            "x/NUL",
        ]:
            self.assertFalse(safe_path(path), path)
        archive = self.assets / f"shiori-reader-{self.tag}-windows-x64.zip"
        original = archive.read_bytes()
        metadata = self.assets / "release-info-windows-x64.json"
        info = json.loads(metadata.read_bytes())
        for bad in ["../escape", "SHIORI.EXE", "data"]:
            archive.write_bytes(original)
            with zipfile.ZipFile(archive, "a") as package:
                package.writestr(bad, "bad")
            metadata.write_bytes(encoded({**info, "sha256": sha(archive)}))
            with self.subTest(path=bad), self.assertRaises(ReleaseCheckError):
                self.manifest()
        archive.write_bytes(original)
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("shiori.exe", b"exe")
            package.writestr("data/app.so", b"aot")
            package.writestr(
                "data/flutter_assets/" + IDENTITY_ASSET,
                b'{"schemaVersion":1,"development":true}',
            )
        metadata.write_bytes(encoded({**info, "sha256": sha(archive)}))
        with self.assertRaises(ReleaseCheckError):
            self.manifest()

    def test_build_history_and_immutable_reruns(self):
        manifest = json.loads(self.manifest())
        file = self.assets / "release-info.json"
        files = {file.name: file}
        previous = {
            "tag_name": "v1.2.1",
            "draft": False,
            "assets": [{"name": "release-info.json", "id": 1, "size": 200}],
        }
        for number in [11, 12, "10", True]:
            with self.assertRaises(ReleaseCheckError):
                validate_history(
                    manifest,
                    [previous],
                    files,
                    lambda *args, number=number: encoded({"versionCode": number}),
                )
        validate_history(
            manifest, [previous], files, lambda *args: encoded({"versionCode": 10})
        )
        current = {
            "tag_name": self.tag,
            "draft": False,
            "assets": [
                {
                    "name": file.name,
                    "id": 2,
                    "size": file.stat().st_size,
                    "digest": "sha256:" + sha(file),
                }
            ],
        }
        self.assertEqual(validate_history(manifest, [current], files)[1], {})
        current["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaises(ReleaseCheckError):
            validate_history(manifest, [current], files)

    def test_publisher_draft_upload_then_publish_and_rerun_no_overwrite(self):
        raw = self.manifest()
        notes = self.root / "docs/release/notes" / f"{self.tag}.md"
        notes.parent.mkdir(parents=True)
        notes.write_text("# Release notes\n")
        (self.assets / "update-manifest.json").write_bytes(raw)
        (self.assets / "update-manifest.sig").write_bytes(
            sign_manifest(raw, self.secret, self.key)
        )
        for name in ["SHA256SUMS.txt", "SHA256SUMS-windows-x64.txt"]:
            (self.assets / name).write_text("synthetic sums")
        calls = []

        def run(*args):
            calls.append(args)
            return b"[[]]" if args[0] == "api" else b""

        publish(self.root, self.assets, self.tag, self.commit, self.key, run)
        self.assertEqual(
            [args[:2] for args in calls[1:]],
            [("release", "create"), ("release", "upload"), ("release", "edit")],
        )
        self.assertIn("--draft", calls[1])
        self.assertEqual(calls[1][calls[1].index("--notes-file") + 1], str(notes))
        self.assertIn("--latest=false", calls[-1])
        self.assertFalse(any("--clobber" in args for args in calls))
        release = {
            "tag_name": self.tag,
            "draft": False,
            "assets": [
                {"name": p.name, "size": p.stat().st_size, "digest": "sha256:" + sha(p)}
                for p in self.assets.iterdir()
            ],
        }
        calls.clear()

        def rerun(*args):
            calls.append(args)
            return encoded([[release]]) if args[0] == "api" else b""

        publish(self.root, self.assets, self.tag, self.commit, self.key, rerun)
        self.assertFalse(any(args[:2] == ("release", "upload") for args in calls))
        (self.assets / "update-manifest.sig").write_bytes(b"0" * 384)
        calls.clear()
        with self.assertRaises(ReleaseCheckError):
            publish(self.root, self.assets, self.tag, self.commit, self.key, rerun)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
