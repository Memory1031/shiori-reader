"""Opt-in real Inno Setup installation/update/uninstallation in isolated directories."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

from update_manifest import encoded, sign_manifest
import test_windows_updater as portable_tests
from test_windows_updater import tree, ENVIRONMENT

INSTALL_ID = "{317FAF26-80D6-47B9-A5EF-14B3829374B3}"
KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" + INSTALL_ID + "_is1"
if sys.platform == "win32":
    import winreg


def registered():
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as key:
            return winreg.QueryValueEx(key, "InstallLocation")[0]
    except FileNotFoundError:
        return None


@unittest.skipUnless(sys.platform == "win32", "real Windows Setup")
class SetupUpdateTest(unittest.TestCase):
    binaries = None
    compiler = None
    run_updater = portable_tests.UpdaterTest.run_updater
    check = portable_tests.UpdaterTest.check
    recover = portable_tests.UpdaterTest.recover
    apply = portable_tests.UpdaterTest.apply
    launched = portable_tests.UpdaterTest.launched
    test_read_only_program_file_is_storage_problem = portable_tests.UpdaterTest.test_read_only_program_file_is_storage_problem
    test_other_instance_blocks_update = portable_tests.UpdaterTest.test_other_instance_blocks_update

    def setUp(self):
        if self.binaries is None or self.compiler is None:
            self.skipTest("Supply --bin-dir and --compiler to opt into installation")
        if registered() is not None:
            self.skipTest("An existing Shiori installation is registered; never overwrite it")
        temporary = tempfile.TemporaryDirectory(prefix="setup 测试 ", dir=self.binaries)
        self.root = Path(temporary.name).resolve()
        self.install = self.root / "Installed Shiori"
        self.workspace = Path(str(self.install) + ".update")
        self.portable = self.root / "Portable Shiori"
        self.user = self.root / "user-data/reading.sqlite"
        self.user.parent.mkdir()
        self.user.write_bytes(b"user library, bookmarks and preferences")
        self.addCleanup(temporary.cleanup)
        self.addCleanup(self.uninstall)
        self.secret = (self.binaries / "key.pem").read_bytes()
        self.key = json.loads((self.binaries / "key.json").read_bytes())
        self.old, self.new = {}, {}
        self.old_setup = self.make_setup(1, 5, self.old)
        self.new_setup = self.make_setup(2, 6, self.new)
        self.run_setup(self.old_setup)
        self.run_setup(self.old_setup)  # Repeat installation upgrades the same identity.
        self.portable.mkdir()
        for name, raw in self.old.items():
            path = self.portable / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        self.portable_before = tree(self.portable)
        self.workspace.mkdir()
        shutil.copy2(self.binaries / "shiori-updater.exe", self.workspace / "shiori-updater.exe")
        shutil.copy2(self.new_setup, self.workspace / "package.exe")
        self.sign()
        self.addCleanup(self.record)

    def record(self):
        evidence = Path(__file__).resolve().parent.parent / ".tooling/evidence/update-v2/setup" / self._testMethodName
        evidence.mkdir(parents=True, exist_ok=True)
        for path in [self.root / "setup.log", self.workspace / "updater.log", self.workspace / "result"]:
            if path.exists(): shutil.copy2(path, evidence / path.name)
        (evidence / "state.json").write_bytes(encoded(dict(registration=registered(), files={n: hashlib.sha256(raw).hexdigest() for n, raw in tree(self.install).items()}, shortcuts=[str(p) for p in (Path(os.environ["APPDATA"]) / "Microsoft/Windows/Start Menu/Programs").rglob("Shiori.lnk")])))

    def make_setup(self, version, build, files):
        source = self.root / f"payload-{version}"
        files.update({
            "shiori.exe": (self.binaries / ("old-app.exe" if version == 1 else "new-app.exe")).read_bytes(),
            "shiori-updater.exe": (self.binaries / "shiori-updater.exe").read_bytes(),
            "runtime.bin": str(version).encode(),
            "data/app.so": f"version {version}".encode(),
            "obsolete.dll" if version == 1 else "data/new-file.txt": b"owned program file",
        })
        files["program-files.txt"] = "".join(n + "\n" for n in sorted([*files, "program-files.txt"])).encode()
        for name, raw in files.items():
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        name = f"shiori-reader-v1.0.0-beta.{build}-windows-x64-setup"
        repo = Path(__file__).resolve().parent.parent
        command = [str(self.compiler), "/Q", f"/DPayload={source}", f"/DOutput={self.root}",
            f"/DFilename={name}", f"/DGroupName=Shiori Fixture {self.root.name}", f"/DVersion=1.0.0-beta.{build}", f"/DFileVersion=1.0.0.{build}",
            f"/DIcon={repo / 'windows/runner/resources/app_icon.ico'}", str(repo / "windows/installer/shiori.iss")]
        subprocess.run(command, check=True, capture_output=True, timeout=90)
        return self.root / (name + ".exe")

    def run_setup(self, setup):
        subprocess.run([str(setup), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CURRENTUSER",
            f"/DIR={self.install}", f"/GROUP=Shiori Fixture {self.root.name}", f"/LOG={self.root / 'setup.log'}"],
            check=True, timeout=60)

    def uninstall(self):
        if registered() is not None and Path(registered()).resolve() == self.install:
            uninstaller = self.install / "unins000.exe"
            subprocess.run([str(uninstaller), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"],
                           check=True, timeout=60)
            deadline = time.monotonic() + 10
            while registered() is not None and time.monotonic() < deadline:
                time.sleep(.05)
            self.assertIsNone(registered())

    def sign(self):
        manifest = dict(schemaVersion=2, algorithm="rsa3072-pkcs1-sha256",
            applicationId="dev.shiori.reader", tag="v1.0.0-beta.6", version="1.0.0",
            build=6, channel="beta", commit="a"*40, keyId=self.key["keyId"], assets=[
                dict(platform="windows-x64-portable", name="shiori-reader-v1.0.0-beta.6-windows-x64.zip",
                     size=1, sha256="0"*64, updaterProtocol=2, files=[
                         dict(path=n, size=len(raw), sha256=hashlib.sha256(raw).hexdigest())
                         for n, raw in sorted(self.new.items())]),
                dict(platform="windows-x64-setup", name=self.new_setup.name, updaterProtocol=2,
                     size=self.new_setup.stat().st_size, sha256=hashlib.sha256(self.new_setup.read_bytes()).hexdigest())])
        raw = encoded(manifest)
        (self.workspace / "update-manifest.json").write_bytes(raw)
        (self.workspace / "update-manifest.sig").write_bytes(sign_manifest(raw, self.secret, self.key))

    def test_installed_upgrade_retains_inventory_registration_and_user_data(self):
        self.assertEqual(Path(registered()).resolve(), self.install)
        self.assertEqual((self.install / ".shiori-install").read_bytes(), (INSTALL_ID + "\n").encode())
        menu = Path(os.environ["APPDATA"]) / "Microsoft/Windows/Start Menu/Programs" / f"Shiori Fixture {self.root.name}/Shiori.lnk"
        self.assertTrue(menu.is_file())
        personal = self.install / "personal.txt"
        personal.write_text("unmanaged file")
        before = tree(self.install)
        self.assertEqual(self.check(), 0)
        self.assertEqual(tree(self.install), before)
        self.assertEqual(self.apply(), 0)
        self.launched(2)
        self.assertFalse((self.install / "obsolete.dll").exists())
        for name, raw in self.new.items():
            self.assertEqual((self.install / name).read_bytes(), raw)
        self.assertEqual(Path(registered()).resolve(), self.install)
        self.assertEqual(self.user.read_bytes(), b"user library, bookmarks and preferences")
        self.assertEqual(tree(self.portable), self.portable_before)
        self.uninstall()
        self.assertFalse(menu.exists())
        self.assertTrue(personal.exists())
        self.assertTrue(self.user.exists())
        for name in self.new:
            self.assertFalse((self.install / name).exists(), name)
        self.assertEqual(tree(self.portable), self.portable_before)

    def test_tampered_exe_and_inconsistent_installation_identity_refused(self):
        before = tree(self.install)
        with (self.workspace / "package.exe").open("ab") as target:
            target.write(b"tampered")
        self.assertEqual(self.check(), 32)
        self.assertEqual(tree(self.install), before)
        shutil.copy2(self.new_setup, self.workspace / "package.exe")
        marker = self.install / ".shiori-install"
        original = marker.read_bytes()
        marker.write_bytes(b"foreign marker\n")
        try:
            self.assertEqual(self.check(), 32)
        finally:
            marker.write_bytes(original)
        self.assertEqual(tree(self.install), before)

    def test_completed_installer_recovers_after_coordinator_interruption(self):
        update = self.apply(wait=False)
        deadline = time.monotonic() + 15
        pending = self.workspace / "setup.pending"
        while (not pending.exists() or "started verified Setup installer" not in (self.workspace / "updater.log").read_text(encoding="utf-8")) and update.poll() is None and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertTrue(pending.exists(), "Coordinator must persist recovery before installation")
        update.terminate()
        update.wait(timeout=10)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            state = self.recover()
            if state == 0:
                break
            self.assertIn(state, [20, 2])
            time.sleep(.05)
        self.assertEqual(state, 0)
        self.assertTrue((self.install / "data/new-file.txt").exists())
        self.assertFalse((self.install / "obsolete.dll").exists())
        self.assertTrue(self.user.exists())

    def test_locked_program_file_is_refused_before_installation(self):
        handle = portable_tests.kernel.CreateFileW(
            str(self.install / "data/app.so"), 0x80000000, 1, None, 3, 0x80, None)
        self.assertNotEqual(handle, portable_tests.ctypes.c_void_p(-1).value)
        try:
            self.assertEqual(self.check(), 31)
            self.assertEqual(self.apply(), 31)
        finally:
            portable_tests.kernel.CloseHandle(handle)
        self.launched(1)
        for name, raw in self.old.items():
            self.assertEqual((self.install / name).read_bytes(), raw)
        self.assertFalse((self.install / "data/new-file.txt").exists())
        self.assertEqual(Path(registered()).resolve(), self.install)
        self.assertEqual(self.user.read_bytes(), b"user library, bookmarks and preferences")
        self.assertEqual(tree(self.portable), self.portable_before)

    def test_installer_failure_preserves_repair_state_without_relaunch(self):
        # This signed test executable exits with an error without runtime.bin.
        # No production key or real release package is involved.
        shutil.copy2(self.binaries / "old-app.exe", self.new_setup)
        shutil.copy2(self.new_setup, self.workspace / "package.exe")
        self.sign()
        before = tree(self.install)
        self.assertEqual(self.apply(), 2)
        self.assertTrue((self.workspace / "setup.pending").exists())
        self.assertEqual(self.recover(), 2)
        self.assertEqual(tree(self.install), before)
        self.assertFalse((self.install / "launched.txt").exists())
        self.assertTrue(self.user.exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    args = parser.parse_args()
    SetupUpdateTest.binaries = args.bin_dir.resolve()
    SetupUpdateTest.compiler = args.compiler.resolve()
    unittest.main(argv=[sys.argv[0]], verbosity=2)
