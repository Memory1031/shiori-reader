"""Real-process tests for shiori-updater.exe, built by test_windows_updater.ps1."""

import argparse
import ctypes
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from update_manifest import (  # noqa: E402
    encoded,
    key_from_private,
    openssl,
    sign_manifest,
)

if sys.platform == "win32":
    from ctypes import wintypes

    from test_update_transaction import Event, kernel  # noqa: E402

    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE

SYNCHRONIZE = 0x00100000
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

# Build number compiled into the test updater; signed test releases use 6.
BUILD = 5
ENVIRONMENT = {**os.environ, "SHIORI_UPDATER_QUIET": "1"}


def prepare(output):
    output.mkdir(parents=True, exist_ok=True)
    private = output / "key.pem"
    private.write_bytes(
        openssl("genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:3072")
    )
    key = key_from_private(private)
    (output / "key.json").write_bytes(encoded(key))
    (output / "updater_test_key.h").write_text(
        f'#define SHIORI_UPDATE_MODULUS "{key["modulus"]}"\n'
        f"#define SHIORI_UPDATE_BUILD {BUILD}\n",
        encoding="ascii",
    )


def tree(root):
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in root.rglob("*")
        if path.is_file()
    }


@unittest.skipUnless(sys.platform == "win32", "Windows process test")
class UpdaterTest(unittest.TestCase):
    binaries = None

    def setUp(self):
        if self.binaries is None:
            self.skipTest("Run test_windows_updater.ps1 to compile the updater")
        self.secret = (self.binaries / "key.pem").read_bytes()
        self.key = json.loads((self.binaries / "key.json").read_bytes())
        temporary = tempfile.TemporaryDirectory(prefix="更新 测试 ", dir=self.binaries)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.install = self.root / "Shiori 阅读"
        self.workspace = self.root / "Shiori 阅读.update"
        self.payload = self.workspace / "payload"
        updater = (self.binaries / "shiori-updater.exe").read_bytes()
        self.old = self.write(self.install, {
            "shiori.exe": (self.binaries / "old-app.exe").read_bytes(),
            "shiori-updater.exe": updater,
            "runtime.bin": b"1",
            "data/app.so": b"old",
            "obsolete.dll": b"old only",
        })
        self.new = self.write(self.payload, {
            "shiori.exe": (self.binaries / "new-app.exe").read_bytes(),
            "shiori-updater.exe": updater,
            "runtime.bin": b"2",
            "data/app.so": b"new",
            "data/新 文件.txt": "新增".encode(),
        })
        # The app runs a copy from the workspace so the installed one can be replaced.
        (self.workspace / "shiori-updater.exe").write_bytes(updater)
        self.sign()

    def write(self, root, files):
        names = sorted([*files, "program-files.txt"])
        files = {**files, "program-files.txt": "".join(n + "\n" for n in names).encode()}
        for name, data in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        return files

    def sign(self, build=BUILD + 1, edit=None):
        files = [
            {
                "path": name,
                "size": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            }
            for name, data in sorted(tree(self.payload).items())
        ]
        manifest = {
            "schemaVersion": 1,
            "algorithm": "rsa3072-pkcs1-sha256",
            "applicationId": "dev.shiori.reader",
            "tag": f"v1.0.0-beta.{build}",
            "version": "1.0.0",
            "build": build,
            "channel": "beta",
            "commit": "a" * 40,
            "keyId": self.key["keyId"],
            "assets": [
                {"platform": "android", "name": "a.apk", "size": 1, "sha256": "0" * 64},
                {
                    "platform": "windows-x64",
                    "name": "w.zip",
                    "size": 1,
                    "sha256": "0" * 64,
                    "updaterProtocol": 1,
                    "minimumSystem": "10.0.17763",
                    "files": files,
                },
            ],
        }
        if edit:
            edit(manifest)
        raw = encoded(manifest)
        (self.workspace / "update-manifest.json").write_bytes(raw)
        (self.workspace / "update-manifest.sig").write_bytes(
            sign_manifest(raw, self.secret, self.key)
        )

    def run_updater(self, *args, handles=(), wait=True):
        startup = subprocess.STARTUPINFO()
        startup.lpAttributeList = {"handle_list": list(handles)}
        command = [str(self.workspace / "shiori-updater.exe"), *map(str, args)]
        process = subprocess.Popen(
            command, env=ENVIRONMENT, close_fds=True, startupinfo=startup
        )
        return process.wait(timeout=60) if wait else process

    def check(self, workspace=None):
        return self.run_updater(
            "check", workspace or self.workspace, self.install, os.getpid()
        )

    def recover(self):
        return self.run_updater("recover", self.workspace, self.install)

    def apply(self, parent_seconds=0.3, wait=True):
        parent = subprocess.Popen(
            [sys.executable, "-c", f"import time; time.sleep({parent_seconds})"]
        )
        self.addCleanup(parent.wait)
        # The same rights windows/runner/flutter_window.cpp duplicates for the updater.
        handle = kernel.OpenProcess(
            SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, True, parent.pid
        )
        self.assertTrue(handle)
        self.addCleanup(kernel.CloseHandle, handle)
        return self.run_updater(
            "apply", self.workspace, self.install, handle, handles=[handle], wait=wait
        )

    def launched(self, version):
        marker = self.install / "launched.txt"
        for _ in range(200):
            if marker.exists() and marker.read_text() == str(version):
                time.sleep(0.05)
                marker.unlink()
                return
            time.sleep(0.05)
        self.fail(f"Version {version} was not launched")

    def result(self):
        return int((self.workspace / "result").read_text().split("\n")[0])

    def assert_installed(self, files):
        self.assertEqual(tree(self.install), files)

    def test_check_accepts_signed_release_without_changes(self):
        self.assertEqual(self.check(), 0)
        self.assert_installed(self.old)

    def test_apply_installs_and_relaunches_new_version(self):
        self.assertEqual(self.apply(), 0)
        self.launched(2)
        self.assert_installed(self.new)
        self.assertEqual(self.result(), 0)
        self.assertEqual(self.recover(), 0)
        self.assertIn("result 0", (self.workspace / "updater.log").read_text("utf-8"))

    def test_rejects_tampered_signature(self):
        signature = self.workspace / "update-manifest.sig"
        data = bytearray(signature.read_bytes())
        data[10] ^= 1
        signature.write_bytes(data)
        self.assertEqual(self.check(), 32)

    def test_rejects_payload_changed_after_signing(self):
        (self.payload / "data/app.so").write_bytes(b"NEW")
        self.assertEqual(self.check(), 32)

    def test_rejects_release_not_newer(self):
        self.sign(build=BUILD)
        self.assertEqual(self.check(), 32)

    def test_rejects_unsupported_protocol(self):
        self.sign(edit=lambda m: m["assets"][1].update(updaterProtocol=2))
        self.assertEqual(self.check(), 32)

    def test_rejects_program_list_that_differs_from_manifest(self):
        (self.payload / "extra.dll").write_bytes(b"unlisted")
        self.sign()
        self.assertEqual(self.check(), 32)

    def test_rejects_release_without_updater(self):
        (self.payload / "shiori-updater.exe").unlink()
        self.write(self.payload, {n: d for n, d in self.new.items()
                                  if n not in ("shiori-updater.exe", "program-files.txt")})
        self.sign()
        self.assertEqual(self.check(), 32)

    def test_installation_without_program_list_is_unsupported(self):
        (self.install / "program-files.txt").unlink()
        self.assertEqual(self.check(), 33)

    def test_foreign_workspace_is_refused(self):
        other = self.root / "elsewhere"
        other.mkdir()
        self.assertEqual(self.check(other), 10)

    def test_read_only_program_file_is_storage_problem(self):
        target = self.install / "data/app.so"
        target.chmod(stat.S_IREAD)
        self.addCleanup(target.chmod, stat.S_IREAD | stat.S_IWRITE)
        self.assertEqual(self.check(), 31)

    def test_other_instance_blocks_update(self):
        ready, stop = Event(), Event()
        self.addCleanup(ready.close)
        self.addCleanup(stop.close)
        instance = subprocess.Popen(
            [str(self.install / "shiori.exe"), ready.name, stop.name], cwd=self.install
        )
        try:
            ready.wait()
            self.assertEqual(self.check(), 30)
        finally:
            stop.signal()
            instance.wait(timeout=10)
        self.assertEqual(self.check(), 0)

    def test_second_updater_reports_busy(self):
        updater = self.apply(parent_seconds=3, wait=False)
        log = self.workspace / "updater.log"
        for _ in range(100):
            if log.exists() and "waiting" in log.read_text("utf-8"):
                break
            time.sleep(0.05)
        self.assertEqual(self.check(), 20)
        self.assertEqual(self.recover(), 20)
        self.assertEqual(updater.wait(timeout=60), 0)
        self.launched(2)

    def test_refused_apply_relaunches_old_version_and_reports(self):
        (self.payload / "data/app.so").write_bytes(b"NEW")
        self.assertEqual(self.apply(), 32)
        self.launched(1)
        self.assert_installed(self.old)
        self.assertEqual(self.recover(), 32)

    def test_locked_file_rolls_back_and_relaunches_old_version(self):
        # Readable but not replaceable: preflight passes, publishing cannot.
        handle = kernel.CreateFileW(
            str(self.install / "data/app.so"), 0x80000000, 1, None, 3, 0x80, None
        )
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        try:
            self.assertEqual(self.apply(), 1)
        finally:
            kernel.CloseHandle(handle)
        self.launched(1)
        self.assert_installed(self.old)
        self.assertEqual(self.recover(), 1)

    def test_recover_without_transaction_reports_none(self):
        self.assertEqual(self.recover(), 21)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path)
    parser.add_argument("--prepare", type=Path)
    args = parser.parse_args()
    if args.prepare:
        prepare(args.prepare)
        sys.exit(0)
    UpdaterTest.binaries = args.bin_dir.resolve() if args.bin_dir else None
    unittest.main(argv=[sys.argv[0]], verbosity=2)
