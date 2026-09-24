"""Offline checks for the iOS release signing preparation."""

import base64
import datetime as dt
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tool import ios_release_signing as signing


class FakeApi:
    def __init__(self, profiles):
        self.profiles = profiles
        self.creations = []

    def all(self, path):
        return self.profiles

    def request(self, path, body):
        self.creations.append((path, body))
        return {"data": {"id": "new", "attributes": body["data"]["attributes"]}}


class SigningTests(unittest.TestCase):
    def test_build_settings_query_targets_individually(self):
        names = {"Runner": "Runner Profile", "ShareExtension": "Extension Profile"}
        commands = []

        def xcodebuild(*args, **kwargs):
            commands.append(args)
            target = args[args.index("-target") + 1]
            return json.dumps([{"buildSettings": {
                "TARGET_NAME": target,
                "PRODUCT_BUNDLE_IDENTIFIER": signing.TARGETS[target][0],
                "CODE_SIGN_STYLE": "Manual",
                "CODE_SIGN_IDENTITY": "Apple Distribution",
                "DEVELOPMENT_TEAM": signing.TEAM,
                "PROVISIONING_PROFILE_SPECIFIER": names[target],
            }}]).encode()

        with mock.patch.object(signing, "run", side_effect=xcodebuild):
            signing.verify_build_settings(names)
        self.assertEqual([command[command.index("-target") + 1] for command in commands],
                         ["Runner", "ShareExtension"])

    def test_jwt_signature_uses_es256_raw_format(self):
        self.assertEqual(
            signing.der_signature_to_raw(bytes.fromhex("3006020101020102")),
            b"\x00" * 31 + b"\x01" + b"\x00" * 31 + b"\x02",
        )

    def test_existing_app_store_profile_is_reused(self):
        profile = {
            "id": "profile",
            "relationships": {
                "bundleId": {"data": {"id": "bundle"}},
                "certificates": {"data": [{"id": "distribution"}]},
            },
        }
        api = FakeApi([profile])
        self.assertIs(signing.find_or_create_profile(api, "dev.shiori.reader", "bundle", "distribution"), profile)
        self.assertEqual(api.creations, [])

    def test_new_profile_uses_only_existing_distribution_certificate(self):
        api = FakeApi([])
        signing.find_or_create_profile(api, "dev.shiori.reader.ShareExtension", "extension", "distribution")
        path, body = api.creations[0]
        self.assertEqual(path, "/profiles")
        self.assertEqual(body["data"]["attributes"]["profileType"], "IOS_APP_STORE")
        self.assertEqual(body["data"]["relationships"]["certificates"]["data"],
                         [{"type": "certificates", "id": "distribution"}])

    def test_ci_project_patch_changes_only_release_signing(self):
        original = Path("ios/Runner.xcodeproj/project.pbxproj").read_text()
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project.pbxproj"
            project.write_text(original)
            names = {"Runner": "XC iOS: Shiori Runner", "ShareExtension": "Shiori CI Extension"}
            signing.configure_project(project, names)
            changed = project.read_text()
        self.assertEqual(changed.count("PROVISIONING_PROFILE_SPECIFIER"), 2)
        self.assertEqual(changed.count("CODE_SIGN_STYLE = Manual;"), 2)
        self.assertIn('"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";', changed)
        self.assertIn('"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer";', changed)
        self.assertEqual(changed.count("CODE_SIGN_STYLE = Automatic;"), original.count("CODE_SIGN_STYLE = Automatic;") - 1)
        self.assertEqual(changed.count("group.dev.shiori.reader.import"), original.count("group.dev.shiori.reader.import"))

    def test_manual_export_maps_both_bundle_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "ExportOptions.plist"
            signing.configure_export_options(Path("ios/ExportOptions.plist"), destination,
                                             {"Runner": "Runner Profile", "ShareExtension": "Extension Profile"})
            with destination.open("rb") as file:
                options = plistlib.load(file)
        self.assertEqual(options["signingStyle"], "manual")
        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["signingCertificate"], "Apple Distribution")
        self.assertEqual(options["provisioningProfiles"], {
            "dev.shiori.reader": "Runner Profile",
            "dev.shiori.reader.ShareExtension": "Extension Profile",
        })

    def test_profile_entitlements_and_certificate_are_checked(self):
        certificate = b"distribution certificate"
        payload = {
            "UUID": "some-uuid",
            "Name": "Shiori CI Runner",
            "TeamIdentifier": [signing.TEAM],
            "DeveloperCertificates": [certificate],
            "ExpirationDate": dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=30),
            "Entitlements": {
                "application-identifier": signing.TEAM + ".dev.shiori.reader",
                "com.apple.security.application-groups": [signing.GROUP],
                "get-task-allow": False,
            },
        }
        profile = {"attributes": {"profileContent": base64.b64encode(b"CMS").decode()}}
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(signing, "run", return_value=plistlib.dumps(payload)), \
                 mock.patch.object(signing.Path, "home", return_value=Path(directory)):
                self.assertEqual(signing.validate_and_install(profile, "dev.shiori.reader", certificate), "Shiori CI Runner")
                payload["Entitlements"]["com.apple.security.application-groups"] = []
                with mock.patch.object(signing, "run", return_value=plistlib.dumps(payload)):
                    with self.assertRaises(RuntimeError):
                        signing.validate_and_install(profile, "dev.shiori.reader", certificate)


if __name__ == "__main__":
    unittest.main()
