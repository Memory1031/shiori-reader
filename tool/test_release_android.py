import base64
import unittest
import os
from pathlib import Path
import tempfile
from unittest.mock import patch

from release_android import ReleaseCheckError, properties_value, signing_values, verify_metadata, version, sdk_tools, run


class ReleaseChecksTest(unittest.TestCase):
    def test_pinned_tools_ignore_newer_installed_version(self):
        with tempfile.TemporaryDirectory() as directory:
            for version_name in ('35.0.0', '37.0.0'):
                tools = Path(directory) / 'build-tools' / version_name
                (tools / 'lib').mkdir(parents=True)
                (tools / 'lib/apksigner.jar').touch()
                (tools / ('aapt.exe' if os.name == 'nt' else 'aapt')).touch()
            with patch.dict(os.environ, {'ANDROID_SDK_ROOT': directory}):
                self.assertEqual(sdk_tools().name, '35.0.0')
                (Path(directory) / 'build-tools/35.0.0/lib/apksigner.jar').unlink()
                with self.assertRaisesRegex(ReleaseCheckError, '35.0.0'):
                    sdk_tools()

    def test_tool_error_does_not_disclose_arguments_or_output(self):
        with patch('release_android.subprocess.run') as process:
            process.return_value.returncode = 1
            process.return_value.stderr = b'private password'
            with self.assertRaises(ReleaseCheckError) as caught:
                run(['java', 'private password'])
            self.assertEqual(str(caught.exception), 'Release tool failed: java')

    def test_version_and_build(self):
        self.assertEqual(version('version: 1.0.0+2\n', 'v1.0.0'), ('1.0.0', '2'))
        self.assertEqual(version('version: 1.0.0-rc.1+3\n', 'v1.0.0-rc.1'), ('1.0.0-rc.1', '3'))
        for text, tag in [('version: 0.1.0+1', 'v1.0.0'), ('version: 1.0.0', 'v1.0.0'),
                          ('version: 1.0.0+0', 'v1.0.0'), ('version: 1.0.0+2100000001', 'v1.0.0')]:
            with self.assertRaises(ValueError):
                version(text, tag)

    def test_properties_preserves_special_characters(self):
        self.assertEqual(properties_value(' a\\b:=#!\n密🔑'),
                         r'\ a\\b\:\=\#\!\n\u5bc6\ud83d\udd11')

    def test_all_secrets_required_and_base64_checked(self):
        env = dict(ANDROID_KEYSTORE_BASE64=base64.b64encode(b'synthetic').decode(),
                   ANDROID_STORE_PASSWORD='test', ANDROID_KEY_ALIAS='synthetic', ANDROID_KEY_PASSWORD='test')
        self.assertEqual(signing_values(env)[0], b'synthetic')
        for key in env:
            with self.assertRaises(ValueError):
                signing_values({**env, key: ''})
        with self.assertRaises(ValueError):
            signing_values({**env, 'ANDROID_KEYSTORE_BASE64': 'invalid!base64'})

    def test_apk_identity_debug_flag_and_certificate(self):
        badging = "package: name='dev.shiori.reader' versionCode='2' versionName='1.0.0' platformBuildVersionName='16'\n"
        certificate = 'a' * 64
        certs = f'Signer #1 certificate SHA-256 digest: {certificate}\n'
        verify_metadata(badging, certs, '1.0.0', '2', certificate)
        for output, signatures, expected in [
            (badging.replace("versionCode='2'", "versionCode='1'"), certs, certificate),
            (badging.replace('dev.shiori.reader', 'other.app'), certs, certificate),
            (badging + 'application-debuggable\n', certs, certificate),
            (badging, certs, 'b' * 64),
            (badging, '', certificate),
            (badging, certs + certs.replace('#1', '#2'), certificate),
        ]:
            with self.assertRaises(ValueError):
                verify_metadata(output, signatures, '1.0.0', '2', expected)


if __name__ == '__main__':
    unittest.main()
