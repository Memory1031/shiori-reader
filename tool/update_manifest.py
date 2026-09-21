"""Signed update protocol. OpenSSL handles RSA; private keys never appear in output."""

import argparse
import base64
import hashlib
import json
import os
import re
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path

from release_android import ReleaseCheckError, version

ALGORITHM = "rsa3072-pkcs1-sha256"
APPLICATION_ID = "dev.shiori.reader"
MAX_SIZE = 2 * 1024 * 1024 * 1024
MAX_MANIFEST = 4 * 1024 * 1024
IDENTITY_ASSET = "assets/release/build-info.json"


def openssl(*args, input_bytes=None):
    result = subprocess.run(
        [os.environ.get("OPENSSL", "openssl"), *map(str, args)],
        input=input_bytes,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise ReleaseCheckError("OpenSSL update signing operation failed")
    return result.stdout


def encoded(value):
    return (
        json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode()


def read_json(raw):
    def pairs(items):
        value = {}
        for key, entry in items:
            if key in value:
                raise ReleaseCheckError("Duplicate JSON field")
            value[key] = entry
        return value

    return json.loads(raw, object_pairs_hook=pairs)


def public_key(value):
    modulus = value.get("modulus", "")
    if (
        value.get("algorithm") != ALGORITHM
        or value.get("exponent") != 65537
        or not isinstance(modulus, str)
        or not re.fullmatch("[89a-f][0-9a-f]{767}", modulus)
        or int(modulus, 16) % 2 != 1
        or value.get("keyId") != hashlib.sha256(bytes.fromhex(modulus)).hexdigest()
    ):
        raise ReleaseCheckError("Invalid update public key")
    return value


def key_from_private(path):
    details = openssl("pkey", "-in", path, "-text_pub", "-noout").decode()
    if not re.search(r"(?:publicExponent|Exponent): 65537 \(0x10001\)", details):
        raise ReleaseCheckError("Update key exponent must be 65537")
    output = openssl("rsa", "-in", path, "-modulus", "-noout").decode().strip()
    modulus = output.removeprefix("Modulus=").lower()
    return public_key(
        {
            "algorithm": ALGORITHM,
            "exponent": 65537,
            "modulus": modulus,
            "keyId": hashlib.sha256(bytes.fromhex(modulus)).hexdigest(),
        }
    )


def identity(pubspec, tag, commit):
    name, build = version(pubspec, tag)
    if not re.fullmatch(
        r"v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-beta\.[1-9]\d*)?", tag
    ):
        raise ReleaseCheckError("Unsupported update release tag")
    if not re.fullmatch("[0-9a-f]{40}", commit):
        raise ReleaseCheckError("Update identity requires a full commit SHA")
    return {
        "applicationId": APPLICATION_ID,
        "tag": tag,
        "version": name,
        "build": int(build),
        "channel": "beta" if "-beta." in tag else "stable",
        "commit": commit,
    }


def check_bundled(raw, expected, key):
    bundled = read_json(raw)
    if bundled != {"schemaVersion": 1, "identity": expected, "publicKey": key}:
        raise ReleaseCheckError("Package build identity or trusted key mismatch")


def safe_path(path):
    if not path or len(path) > 1024 or re.search(r'[\\:\x00-\x1f<>"|?*]', path):
        return False
    return all(
        part
        and part not in (".", "..")
        and not part.endswith((".", " "))
        and not re.match(
            r"^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)", part, re.IGNORECASE
        )
        for part in path.split("/")
    )


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def windows_files(path, expected, key):
    files, names, total = [], set(), 0
    with zipfile.ZipFile(path) as package:
        entries = package.infolist()
        if not entries or len(entries) > 10000:
            raise ReleaseCheckError("Invalid Windows update file count")
        for entry in entries:
            name = entry.filename
            if (
                not safe_path(name)
                or name.lower() in names
                or entry.is_dir()
                or stat.S_ISLNK(entry.external_attr >> 16)
                or entry.flag_bits & 1
            ):
                raise ReleaseCheckError("Unsafe Windows update entry")
            names.add(name.lower())
            total += entry.file_size
            if total > MAX_SIZE:
                raise ReleaseCheckError("Windows update exceeds size limit")
            with package.open(entry) as source:
                digest = hashlib.file_digest(source, "sha256").hexdigest()
            files.append({"path": name, "size": entry.file_size, "sha256": digest})
        for name in names:
            parts = name.split("/")
            if any("/".join(parts[:i]) in names for i in range(1, len(parts))):
                raise ReleaseCheckError("Windows file/directory collision")
        if not {"shiori.exe", "data/app.so"}.issubset(names):
            raise ReleaseCheckError("Missing Windows runtime files")
        bundled = package.getinfo("data/flutter_assets/" + IDENTITY_ASSET)
        if bundled.file_size > 16384:
            raise ReleaseCheckError("Build identity too large")
        check_bundled(package.read(bundled), expected, key)
    return sorted(files, key=lambda item: item["path"])


def create_manifest(root, assets, tag, commit, key):
    expected = identity(
        (root / "pubspec.yaml").read_text(encoding="utf-8"), tag, commit
    )
    key = public_key(key)
    result = dict(
        schemaVersion=1, algorithm=ALGORITHM, keyId=key["keyId"], **expected, assets=[]
    )
    for platform, suffix, metadata_name in [
        ("android", "android.apk", "release-info.json"),
        ("windows-x64", "windows-x64.zip", "release-info-windows-x64.json"),
    ]:
        metadata = read_json((assets / metadata_name).read_bytes())
        name = f"shiori-reader-{tag}-{suffix}"
        path = assets / name
        if (
            metadata["tag"] != tag
            or metadata["commit"] != commit
            or metadata["versionName"] != expected["version"]
            or metadata["versionCode"] != expected["build"]
            or metadata.get("apk" if platform == "android" else "archive") != name
            or path.is_symlink()
            or not 0 < path.stat().st_size <= MAX_SIZE
            or metadata["sha256"] != sha(path)
        ):
            raise ReleaseCheckError("Update asset metadata mismatch")
        asset = {
            "platform": platform,
            "name": name,
            "size": path.stat().st_size,
            "sha256": metadata["sha256"],
        }
        if platform == "android":
            certificate = metadata["certificateSha256"]
            if metadata["applicationId"] != APPLICATION_ID or not re.fullmatch(
                "[0-9a-f]{64}", certificate
            ):
                raise ReleaseCheckError("Android package identity mismatch")
            with zipfile.ZipFile(path) as apk:
                bundled = apk.getinfo("assets/flutter_assets/" + IDENTITY_ASSET)
                if bundled.file_size > 16384:
                    raise ReleaseCheckError("Build identity too large")
                check_bundled(apk.read(bundled), expected, key)
            asset.update(minimumSystem="24", certificateSha256=certificate)
        else:
            if metadata["platform"] != "windows-x64":
                raise ReleaseCheckError("Windows platform identity mismatch")
            asset.update(
                minimumSystem="10.0.17763",
                updaterProtocol=1,
                files=windows_files(path, expected, key),
            )
        result["assets"].append(asset)
    raw = encoded(result)
    if len(raw) > MAX_MANIFEST:
        raise ReleaseCheckError("Update manifest too large")
    return raw


def sign_manifest(raw, private_pem, key):
    with tempfile.TemporaryDirectory(prefix="shiori-update-sign-") as directory:
        private = Path(directory) / "private.pem"
        private.write_bytes(private_pem)
        private.chmod(0o600)
        if key_from_private(private) != public_key(key):
            raise ReleaseCheckError("Update signing key does not match bundled trust")
        signature = openssl("dgst", "-sha256", "-sign", private, input_bytes=raw)
        if len(signature) != 384:
            raise ReleaseCheckError("Invalid update signature size")
        return signature


def verify_signature(raw, signature, key):
    key = public_key(key)
    if not 0 < len(raw) <= MAX_MANIFEST or len(signature) != 384:
        raise ReleaseCheckError("Invalid update signature input")
    with tempfile.TemporaryDirectory(prefix="shiori-update-verify-") as directory:
        directory = Path(directory)
        # PKCS#1 RSAPublicKey DER, fixed 3072-bit positive modulus and exponent 65537.
        der = bytes.fromhex("3082018a0282018100" + key["modulus"] + "0203010001")
        (directory / "public.der").write_bytes(der)
        public = openssl(
            "rsa",
            "-RSAPublicKey_in",
            "-inform",
            "DER",
            "-in",
            directory / "public.der",
            "-pubout",
        )
        (directory / "public.pem").write_bytes(public)
        (directory / "manifest.sig").write_bytes(signature)
        openssl(
            "dgst",
            "-sha256",
            "-verify",
            directory / "public.pem",
            "-signature",
            directory / "manifest.sig",
            input_bytes=raw,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["identity", "manifest", "keygen"])
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--assets", type=Path, default=Path("build/release-assets"))
    parser.add_argument("--tag", default=os.environ.get("GITHUB_REF_NAME", ""))
    parser.add_argument("--commit", default=os.environ.get("GITHUB_SHA", ""))
    parser.add_argument("--private-key", type=Path)
    parser.add_argument("--public-key", type=Path)
    args = parser.parse_args()
    if args.command == "keygen":
        if (
            not args.private_key
            or not args.public_key
            or args.private_key.exists()
            or args.public_key.exists()
        ):
            raise ReleaseCheckError("Supply new private/public key output paths")
        # Generate in memory; exclusive creation prevents overwriting an existing key.
        secret = openssl(
            "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:3072"
        )
        with args.private_key.open("xb") as output:
            args.private_key.chmod(0o600)
            output.write(secret)
        key = key_from_private(args.private_key)
        with args.public_key.open("xb") as output:
            output.write(encoded(key))
        print(
            "Update key pair created. Store the private key securely; publish only the public key."
        )
        return
    key = public_key(read_json(os.environ.get("UPDATE_PUBLIC_KEY_JSON", "{}")))
    if args.command == "identity":
        expected = identity(
            (args.root / "pubspec.yaml").read_text(encoding="utf-8"),
            args.tag,
            args.commit,
        )
        (args.root / IDENTITY_ASSET).write_bytes(
            encoded({"schemaVersion": 1, "identity": expected, "publicKey": key})
        )
    else:
        raw = create_manifest(args.root, args.assets, args.tag, args.commit, key)
        secret = base64.b64decode(
            os.environ.get("UPDATE_SIGNING_KEY_PEM_B64", ""), validate=True
        )
        if not secret:
            raise ReleaseCheckError("Missing UPDATE_SIGNING_KEY_PEM_B64")
        signature = sign_manifest(raw, secret, key)
        (args.assets / "update-manifest.json").write_bytes(raw)
        (args.assets / "update-manifest.sig").write_bytes(signature)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile):
        raise SystemExit(
            "Update preparation failed: check release identity, assets and signing configuration."
        )
