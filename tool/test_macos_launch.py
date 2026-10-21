"""Compile and exercise the production launch cover using AppKit, without Flutter."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == 'darwin', 'Requires AppKit')
class MacOSLaunchTests(unittest.TestCase):
    def test_native_cover_lifecycle(self):
        root = Path(__file__).resolve().parent.parent
        with tempfile.TemporaryDirectory(prefix='shiori-launch-test-') as temporary:
            stage = Path(temporary)
            executable = stage / 'launch-tests'
            subprocess.run([
                'xcrun', 'swiftc', '-parse-as-library',
                '-module-cache-path', str(stage / 'swift-cache'),
                str(root / 'macos/Runner/NativeLaunchView.swift'),
                str(root / 'macos/RunnerTests/NativeLaunchViewTests.swift'),
                '-o', str(executable),
            ], check=True, timeout=120)
            subprocess.run([str(executable)], check=True, timeout=15)


if __name__ == '__main__':
    unittest.main()
