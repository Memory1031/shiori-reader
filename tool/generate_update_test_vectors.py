"""Regenerate public-only signature fixtures with an ephemeral, discarded test key."""

import base64
import copy
import json
import sys
from pathlib import Path

from test_update_manifest import UpdateManifestTest
from update_manifest import encoded, sign_manifest, envelope


def main():
    UpdateManifestTest.setUpClass()
    case = UpdateManifestTest()
    try:
        case.setUp()
        original = json.loads(case.manifest())
        variants = {}

        def add(name, edit):
            value = copy.deepcopy(original)
            edit(value)
            raw = encoded(value)
            signature = sign_manifest(raw, case.secret, case.key)
            variants[name] = {
                "envelope": base64.b64encode(envelope(raw, signature)).decode(),
                "manifest": base64.b64encode(raw).decode(),
                "signature": base64.b64encode(
                    signature
                ).decode(),
            }

        add("valid", lambda value: None)
        for number in range(2, 11):

            def history(value, number=number):
                tag = f"v1.2.1-beta.{number}"
                value.update(tag=tag, build=10 + number)
                for asset in value["assets"]:
                    asset["name"] = asset["name"].replace("1.2.1-beta.1", tag[1:])

            add(f"beta{number}", history)
        add("wrongSchema", lambda value: value.update(schemaVersion=1))
        add("wrongChannel", lambda value: value.update(channel="stable"))
        add("wrongApp", lambda value: value.update(applicationId="other.app"))
        add("missingAsset", lambda value: value["assets"].pop())
        add("duplicateAsset", lambda value: value["assets"].append(value["assets"][0]))
        add("wrongPlatform", lambda value: value["assets"][3].update(platform="macos-arm64"))
        add("wrongMacProtocol", lambda value: value["assets"][3].update(updaterProtocol=1))
        add("wrongSetupProtocol", lambda value: value["assets"][2].update(updaterProtocol=1))
        add("wrongMacName", lambda value: value["assets"][3].update(name="shiori-reader-v1.2.1-beta.1-macos-universal.zip"))
        add("wrongDigest", lambda value: value["assets"][0].update(sha256="bad"))
        add("wrongSize", lambda value: value["assets"][0].update(size=-1))
        add(
            "traversal",
            lambda value: value["assets"][1]["files"][0].update(path="../outside"),
        )
        add("wrongProtocol", lambda value: value["assets"][1].update(updaterProtocol=1))
        add("missingRuntime", lambda value: value["assets"][1]["files"].pop())
        raw = encoded(original).replace(b'"schemaVersion":2', b'"schemaVersion":2,"schemaVersion":2')
        signature = sign_manifest(raw, case.secret, case.key)
        variants['duplicateField'] = dict(manifest=base64.b64encode(raw).decode(), signature=base64.b64encode(signature).decode(), envelope=base64.b64encode(envelope(raw, signature)).decode())
        destination = Path("test/fixtures/updates/vectors.json")
        destination.parent.mkdir(parents=True, exist_ok=True)
        packages = {
            asset["platform"]: base64.b64encode(
                (case.assets / asset["name"]).read_bytes()
            ).decode()
            for asset in original["assets"]
        }
        destination.write_bytes(
            encoded({"publicKey": case.key, "cases": variants, "packages": packages})
        )
        print("Public update signature fixtures generated; no private key retained.")
    finally:
        case.doCleanups()
        UpdateManifestTest.doClassCleanups()


if __name__ == "__main__":
    main()
