"""Offline real-process transaction tests, built by test_update_transaction.ps1."""

import argparse
import ctypes
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from ctypes import wintypes
from pathlib import Path

if sys.platform == "win32":
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateEventW.argtypes = [
        ctypes.c_void_p,
        wintypes.BOOL,
        wintypes.BOOL,
        wintypes.LPCWSTR,
    ]
    kernel.CreateEventW.restype = wintypes.HANDLE
    kernel.OpenEventW.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.LPCWSTR]
    kernel.OpenEventW.restype = wintypes.HANDLE
    kernel.SetEvent.argtypes = [wintypes.HANDLE]
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CreateFileW.argtypes = [
        wintypes.LPCWSTR,
        wintypes.DWORD,
        wintypes.DWORD,
        ctypes.c_void_p,
        wintypes.DWORD,
        wintypes.DWORD,
        wintypes.HANDLE,
    ]
    kernel.CreateFileW.restype = wintypes.HANDLE


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Event:
    def __init__(self):
        self.name = "Local\\Shiori.UpdateProbe." + uuid.uuid4().hex
        self.handle = kernel.CreateEventW(None, True, False, self.name)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())

    def wait(self):
        if kernel.WaitForSingleObject(self.handle, 10000) != 0:
            raise AssertionError("Probe did not reach checkpoint")

    def signal(self):
        kernel.SetEvent(self.handle)

    def close(self):
        kernel.CloseHandle(self.handle)


@unittest.skipUnless(sys.platform == "win32", "Windows process test")
class TransactionTest(unittest.TestCase):
    binaries = None

    def setUp(self):
        if self.binaries is None:
            self.skipTest("Run test_update_transaction.ps1 to compile fixtures")
        self.temp = tempfile.TemporaryDirectory(prefix="事务 空格 ", dir=self.binaries)
        self.root = Path(self.temp.name)
        self.install = self.root / "安装 目录"
        self.workspace = self.root / "更新 暂存"
        self.payload = self.workspace / "payload"
        self.install.mkdir()
        self.payload.mkdir(parents=True)
        shutil.copyfile(self.binaries / "old-app.exe", self.install / "shiori.exe")
        shutil.copyfile(self.binaries / "new-app.exe", self.payload / "shiori.exe")
        (self.install / "runtime.bin").write_text("1")
        (self.payload / "runtime.bin").write_text("2")
        (self.install / "obsolete.bin").write_text("old only")
        (self.payload / "added.bin").write_text("new only")
        (self.payload / "data").mkdir()
        (self.payload / "data" / "asset.txt").write_text("new asset")
        self.old = self.entries(self.install)
        self.new = self.entries(self.payload)
        (self.install / "personal.txt").write_text("keep me")
        self.user_data = self.root / "user-data"
        self.user_data.mkdir()
        (self.user_data / "books.db").write_bytes(b"unchanged database fixture")
        self.job = self.root / "task.bin"
        self.write_job()
        self.processes = []
        self.events = []
        self.locks = []

    def tearDown(self):
        if not hasattr(self, "temp"):
            return
        for process in self.processes:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=10)
        for handle in self.locks:
            kernel.CloseHandle(handle)
        for event in self.events:
            event.close()
        self.temp.cleanup()

    def entries(self, root):
        return [
            (path.relative_to(root).as_posix(), digest(path))
            for path in sorted(root.rglob("*"))
            if path.is_file()
        ]

    def write_job(self):
        def string(value):
            raw = value.encode("utf-8")
            return struct.pack("<I", len(raw)) + raw

        raw = (
            string("ShioriUpdateTransaction/1")
            + string(str(self.install))
            + string(str(self.workspace))
        )
        for entries in (self.old, self.new):
            raw += struct.pack("<I", len(entries))
            for name, checksum in entries:
                raw += string(name) + string(checksum)
        self.job.write_bytes(raw)

    def event(self):
        result = Event()
        self.events.append(result)
        return result

    def spawn(self, args, cwd=None):
        result = subprocess.Popen(
            list(map(str, args)),
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        self.processes.append(result)
        return result

    def updater(self, mode="apply", pid=0, timeout=1000, checkpoint=None):
        args = [self.binaries / "update-probe.exe", mode]
        args += [self.job, pid, timeout] if mode == "apply" else [self.workspace]
        ready, proceed = None, None
        if checkpoint:
            ready, proceed = self.event(), self.event()
            args += [checkpoint, ready.name, proceed.name]
        process = self.spawn(args)
        if ready:
            ready.wait()
        return process, proceed

    def finish(self, process, code):
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(
            process.returncode, code, (stdout + stderr).decode(errors="replace")
        )

    def preserved(self):
        self.assertEqual((self.install / "personal.txt").read_text(), "keep me")
        self.assertEqual(
            (self.user_data / "books.db").read_bytes(), b"unchanged database fixture"
        )

    def check_old(self):
        for name, checksum in self.old:
            self.assertEqual(digest(self.install / name), checksum)
        self.assertFalse((self.install / "added.bin").exists())
        self.assertFalse((self.install / "data" / "asset.txt").exists())
        self.assertFalse((self.install / "launched.txt").exists())
        self.preserved()

    def check_new(self, launched=True):
        for name, checksum in self.new:
            self.assertEqual(digest(self.install / name), checksum)
        self.assertFalse((self.install / "obsolete.bin").exists())
        if launched:
            deadline = time.monotonic() + 5
            marker = self.install / "launched.txt"
            while time.monotonic() < deadline:
                if marker.exists() and marker.read_text() == "2":
                    break
                time.sleep(0.02)
            else:
                self.fail("New application did not run with matching runtime files")
            # The marker is written immediately before fixture process exit.
            time.sleep(0.05)
        self.preserved()

    def lock(self, path, share=1):
        handle = kernel.CreateFileW(str(path), 0x80000000, share, None, 3, 0x80, None)
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        self.locks.append(handle)
        return handle

    def unlock(self, handle):
        kernel.CloseHandle(handle)
        self.locks.remove(handle)

    def reject_role_change(self, reverse=False, mixed_case=False):
        old_name = "data/Layout" if mixed_case else "data/layout"
        new_name = "DATA/layout" if mixed_case else "data/layout"
        if reverse:
            old_name += "/default.json"
        else:
            new_name += "/default.json"
        for root, name, manifest in (
            (self.install, old_name, self.old),
            (self.payload, new_name, self.new),
        ):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("role change fixture")
            manifest.append((name, digest(path)))
        self.write_job()
        before = self.entries(self.install)
        process, _ = self.updater()
        self.finish(process, 10)
        self.assertEqual(self.entries(self.install), before)
        self.check_old()
        self.assertEqual({p.name for p in self.workspace.iterdir()}, {"payload"})

    def test_file_to_directory_rejected_before_mutation(self):
        self.reject_role_change()

    def test_directory_to_file_rejected_before_mutation(self):
        self.reject_role_change(reverse=True)

    def test_case_insensitive_file_to_directory_rejected(self):
        self.reject_role_change(mixed_case=True)

    def test_case_insensitive_directory_to_file_rejected(self):
        self.reject_role_change(reverse=True, mixed_case=True)

    def test_real_exit_replace_and_restart(self):
        ready, stop = self.event(), self.event()
        old = self.spawn(
            [self.install / "shiori.exe", ready.name, stop.name], self.install
        )
        ready.wait()
        updater, proceed = self.updater(pid=old.pid, checkpoint="waiting", timeout=5000)
        self.check_old()
        proceed.signal()
        stop.signal()
        self.finish(old, 0)
        self.finish(updater, 0)
        self.check_new()
        recovery, _ = self.updater("recover")
        self.finish(recovery, 0)
        self.check_new()

    def test_parent_timeout_changes_nothing(self):
        ready, stop = self.event(), self.event()
        old = self.spawn(
            [self.install / "shiori.exe", ready.name, stop.name], self.install
        )
        ready.wait()
        updater, _ = self.updater(pid=old.pid, timeout=30)
        self.finish(updater, 10)
        self.assertIsNone(old.poll())
        self.check_old()
        stop.signal()
        self.finish(old, 0)

    def test_lock_failure_then_recovery(self):
        updater, proceed = self.updater(checkpoint="file_applied:1")
        self.assertFalse((self.install / "shiori.exe").exists())
        # runtime.bin fails the apply; the already-published added.bin then
        # cannot be removed, so rollback stops. Unchanged files are skipped.
        lock = self.lock(self.install / "runtime.bin")
        added = self.lock(self.install / "added.bin")
        proceed.signal()
        self.finish(updater, 2)
        self.assertFalse((self.install / "shiori.exe").exists())
        self.unlock(lock)
        self.unlock(added)
        recovery, _ = self.updater("recover")
        self.finish(recovery, 1)
        self.check_old()
        repeated, _ = self.updater("recover")
        self.finish(repeated, 1)
        self.check_old()

    def test_locked_unchanged_file_does_not_block_rollback(self):
        updater, proceed = self.updater(checkpoint="file_applied:1")
        lock = self.lock(self.install / "runtime.bin")
        proceed.signal()
        self.finish(updater, 1)
        self.unlock(lock)
        self.check_old()

    def test_failure_rolls_back_without_manual_recovery(self):
        updater, proceed = self.updater(checkpoint="gated")
        (self.payload / "runtime.bin").unlink()
        proceed.signal()
        self.finish(updater, 1)
        self.check_old()

    def test_killed_updater_recovers_at_each_mutation_boundary(self):
        # Before publication there is no runnable new entry point, so recovery
        # restores the old version at every mutation boundary.
        for checkpoint in [
            "prepared",
            "gated",
            "removed",
            "file_applied:1",
        ]:
            with self.subTest(checkpoint=checkpoint):
                updater, _ = self.updater(checkpoint=checkpoint)
                updater.kill()
                updater.communicate(timeout=10)
                recovery, _ = self.updater("recover")
                self.finish(recovery, 1)
                self.check_old()
                self.reset_workspace()

    def reset_workspace(self):
        # Only the fresh test-owned workspace under this TemporaryDirectory.
        self.assertEqual(self.workspace.parent.resolve(), self.root.resolve())
        shutil.rmtree(self.workspace)
        self.payload.mkdir(parents=True)
        shutil.copyfile(self.binaries / "new-app.exe", self.payload / "shiori.exe")
        (self.payload / "runtime.bin").write_text("2")
        (self.payload / "added.bin").write_text("new only")
        (self.payload / "data").mkdir()
        (self.payload / "data" / "asset.txt").write_text("new asset")

    def test_killed_rollback_can_resume(self):
        updater, _ = self.updater(checkpoint="file_applied:1")
        updater.kill()
        updater.communicate(timeout=10)
        recovery, _ = self.updater("recover", checkpoint="rollback_file:1")
        self.assertFalse((self.install / "shiori.exe").exists())
        recovery.kill()
        recovery.communicate(timeout=10)
        again, _ = self.updater("recover")
        self.finish(again, 1)
        self.check_old()

    def test_committed_transaction_never_rolls_back(self):
        self.check_forward_recovery("committed")

    def test_publish_boundary_recovers_forward_before_exe_appears(self):
        self.check_forward_recovery("publishing")

    def test_exposed_new_executable_never_rolls_back(self):
        self.check_forward_recovery("installed")

    def check_forward_recovery(self, checkpoint):
        updater, _ = self.updater(checkpoint=checkpoint)
        if checkpoint == "publishing":
            self.assertFalse((self.install / "shiori.exe").exists())
        updater.kill()
        updater.communicate(timeout=10)
        recovery, _ = self.updater("recover")
        self.finish(recovery, 0)
        self.check_new(launched=False)
        self.assertFalse((self.install / "launched.txt").exists())

    def test_second_updater_is_excluded(self):
        first, proceed = self.updater(checkpoint="prepared")
        second, _ = self.updater()
        self.finish(second, 10)
        self.check_old()
        proceed.signal()
        self.finish(first, 0)
        self.check_new()

    def test_unmanaged_collision_and_tampered_payload_rejected(self):
        (self.install / "added.bin").write_text("personal collision")
        updater, _ = self.updater()
        self.finish(updater, 10)
        self.assertEqual((self.install / "added.bin").read_text(), "personal collision")
        (self.install / "added.bin").unlink()
        (self.payload / "runtime.bin").write_text("tampered")
        updater, _ = self.updater()
        self.finish(updater, 10)
        self.check_old()

    def test_unsafe_and_duplicate_paths_rejected(self):
        original = list(self.new)
        for path in [
            "../outside",
            "/absolute",
            "a/../b",
            "CON.txt",
            "x:stream",
            "a\\b",
            "a//b",
            "a./b",
            "SHIORI.EXE",
            "shiori.exe/child",
        ]:
            with self.subTest(path=path):
                self.new = original + [(path, "0" * 64)]
                self.write_job()
                updater, _ = self.updater()
                self.finish(updater, 10)
                self.check_old()

    def test_hardlink_payload_rejected(self):
        os.link(self.payload / "runtime.bin", self.root / "runtime-link")
        updater, _ = self.updater()
        self.finish(updater, 10)
        self.check_old()

    def test_restart_failure_keeps_committed_files(self):
        updater, proceed = self.updater(checkpoint="committed")
        lock = self.lock(self.install / "shiori.exe", share=0)
        proceed.signal()
        self.finish(updater, 3)
        self.unlock(lock)
        self.check_new(launched=False)
        recovery, _ = self.updater("recover")
        self.finish(recovery, 0)
        self.check_new(launched=False)

    def test_payload_changed_after_preparation_rolls_back(self):
        updater, proceed = self.updater(checkpoint="gated")
        (self.payload / "runtime.bin").write_text("changed after initial verification")
        proceed.signal()
        self.finish(updater, 1)
        self.check_old()

    def test_corrupt_backup_does_not_restore_untrusted_content(self):
        updater, _ = self.updater(checkpoint="file_applied:1")
        updater.kill()
        updater.communicate(timeout=10)
        (self.workspace / "backup" / "runtime.bin").write_text("corrupt backup")
        recovery, _ = self.updater("recover")
        self.finish(recovery, 2)
        self.assertFalse((self.install / "shiori.exe").exists())
        self.preserved()

    def test_workspace_inside_install_rejected(self):
        actual = self.workspace
        self.workspace = self.install / "nested-update"
        self.workspace.mkdir()
        self.write_job()
        updater, _ = self.updater()
        self.finish(updater, 10)
        self.check_old()
        self.workspace = actual

    def test_junction_payload_rejected(self):
        import _winapi

        target = self.root / "external"
        target.mkdir()
        (target / "asset.txt").write_text("new asset")
        (self.payload / "data" / "asset.txt").unlink()
        (self.payload / "data").rmdir()
        _winapi.CreateJunction(str(target), str(self.payload / "data"))
        updater, _ = self.updater()
        self.finish(updater, 10)
        self.check_old()
        self.assertEqual((target / "asset.txt").read_text(), "new asset")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, required=True)
    args = parser.parse_args()
    TransactionTest.binaries = args.bin_dir.resolve()
    unittest.main(argv=[sys.argv[0]], verbosity=2)
