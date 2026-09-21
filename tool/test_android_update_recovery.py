"""Explicit device process test; requires UpdateInstallSmokeRunner and its staged APK."""

import argparse
import subprocess
import time

APP = "dev.shiori.reader"
RUNNER = f"{APP}.test/{APP}.UpdateInstallSmokeRunner"
MARKER = "files/update-smoke/precommit"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--require-retained", action="store_true")
    args = parser.parse_args()
    base = [args.adb, "-s", args.serial]

    def run(*arguments, **kwargs):
        return subprocess.run(base + list(arguments), check=True, timeout=60, **kwargs)

    # Only this smoke's marker is removed; app databases/settings are untouched.
    run("shell", "run-as", APP, "rm", "-f", MARKER)
    process = subprocess.Popen(
        base + ["shell", "am", "instrument", "-w", "-e", "mode", "precommit", RUNNER],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            ready = subprocess.run(
                base + ["shell", "run-as", APP, "test", "-f", MARKER],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
            if ready.returncode == 0:
                break
            if process.poll() is not None:
                raise RuntimeError(process.communicate()[0].decode(errors="replace"))
            time.sleep(0.2)
        else:
            raise RuntimeError("Precommit checkpoint timeout")
        pid = run("shell", "pidof", APP, capture_output=True, text=True).stdout.strip()
        if not pid.isdigit():
            raise RuntimeError("Expected exactly one target app process")
        run("shell", "run-as", APP, "kill", "-9", pid)
        process.communicate(timeout=10)
        print("Killed app after persisted installing state, before session.commit.")
        result = run(
            "shell",
            "am",
            "instrument",
            "-w",
            "-e",
            "mode",
            "recover",
            RUNNER,
            capture_output=True,
            text=True,
        ).stdout
        print(result)
        if "PASS: recover" not in result:
            raise RuntimeError("Recovery acceptance failed")
        if args.require_retained and "retained after process death: true" not in result:
            raise RuntimeError(
                "System cleaned the session; retained-session process path untested"
            )
    finally:
        if process.poll() is None:
            run("shell", "am", "force-stop", APP)
            process.communicate(timeout=10)


if __name__ == "__main__":
    main()
