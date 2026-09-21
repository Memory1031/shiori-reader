"""Regenerate public-only signature fixtures with an ephemeral, discarded test key."""

import base64
import copy
import json
from pathlib import Path

from test_update_manifest import UpdateManifestTest
from update_manifest import encoded, sign_manifest


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
            variants[name] = {
                "manifest": base64.b64encode(raw).decode(),
                "signature": base64.b64encode(
                    sign_manifest(raw, case.secret, case.key)
                ).decode(),
            }

        add("valid", lambda value: None)
        add("wrongSchema", lambda value: value.update(schemaVersion=2))
        add("wrongChannel", lambda value: value.update(channel="stable"))
        add("wrongApp", lambda value: value.update(applicationId="other.app"))
        add("missingAsset", lambda value: value["assets"].pop())
        add("duplicateAsset", lambda value: value["assets"].append(value["assets"][0]))
        add("wrongDigest", lambda value: value["assets"][0].update(sha256="bad"))
        add("wrongSize", lambda value: value["assets"][0].update(size=-1))
        add(
            "traversal",
            lambda value: value["assets"][1]["files"][0].update(path="../outside"),
        )
        add("wrongProtocol", lambda value: value["assets"][1].update(updaterProtocol=2))
        add("missingRuntime", lambda value: value["assets"][1]["files"].pop())
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
