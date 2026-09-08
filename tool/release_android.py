"""Android tag release checks. Standard library only; never print signing secrets."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def version(pubspec, tag):
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+([1-9]\d*)\s*$", pubspec, re.M)
    if not match or int(match[2]) > 2100000000:
        raise ValueError("pubspec must have an Android-compatible version and positive build number")
    if tag != "v" + match[1]:
        raise ValueError("Release tag must equal v + pubspec version (without build number)")
    return match[1], match[2]


def properties_value(value):
    # java.util.Properties.load(InputStream) uses ISO-8859-1 plus Unicode escapes.
    escaped = ""
    for character in value:
        if character in "\\ =:#!":
            escaped += "\\" + character
        elif character in "\r\n\t\f":
            escaped += {"\r": r"\r", "\n": r"\n", "\t": r"\t", "\f": r"\f"}[character]
        elif 32 <= ord(character) < 127:
            escaped += character
        else:
            units = character.encode("utf-16-be")
            escaped += "".join(f"\\u{int.from_bytes(units[i:i+2], 'big'):04x}" for i in range(0, len(units), 2))
    return escaped


def signing_values(environment):
    names = ("ANDROID_KEYSTORE_BASE64", "ANDROID_STORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")
    missing = [name for name in names if not environment.get(name)]
    if missing:
        raise ValueError("Missing Actions secrets: " + ", ".join(missing))
    try:
        binary = base64.b64decode("".join(environment[names[0]].split()), validate=True)
    except ValueError:
        raise ValueError("ANDROID_KEYSTORE_BASE64 is invalid") from None
    if not binary:
        raise ValueError("Keystore is empty")
    return binary, environment


def run(command):
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode:
        # Tool output may contain credential-dependent data; fail without echoing it.
        raise ValueError("Release tool failed: " + Path(command[0]).name)
    return result.stdout


def prepare_signing(root):
    binary, env = signing_values(os.environ)
    keystore = root / "android/app/release-keystore.jks"
    properties = root / "android/key.properties"
    keystore.write_bytes(binary)
    keystore.chmod(0o600)
    values = {"storeFile": "release-keystore.jks", "storePassword": env["ANDROID_STORE_PASSWORD"],
              "keyAlias": env["ANDROID_KEY_ALIAS"], "keyPassword": env["ANDROID_KEY_PASSWORD"]}
    properties.write_text("".join(f"{key}={properties_value(value)}\n" for key, value in values.items()), encoding="ascii")
    properties.chmod(0o600)
    certificate = run(["keytool", "-exportcert", "-keystore", str(keystore),
                       "-alias", env["ANDROID_KEY_ALIAS"], "-storepass:env", "ANDROID_STORE_PASSWORD"])
    (root / "android/release-certificate.der").write_bytes(certificate)


def verify_metadata(badging, certs, expected_version, expected_build, expected_certificate):
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != ("dev.shiori.reader", expected_build, expected_version):
        raise ValueError("APK package/version does not match release configuration")
    if re.search(r"^application-debuggable(?:\s|$)", badging, re.M):
        raise ValueError("APK must not be debuggable")
    fingerprints = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$", certs, re.M)
    if [value.lower() for value in fingerprints] != [expected_certificate.lower()]:
        raise ValueError("APK signing certificate differs from the configured keystore")


def verify_apk(root, tag):
    name, number = version((root / "pubspec.yaml").read_text(encoding="utf-8"), tag)
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    if not sdk:
        raise ValueError("Android SDK environment is missing")
    candidates = [path for path in (Path(sdk) / "build-tools").iterdir() if re.fullmatch(r"\d+\.\d+\.\d+", path.name)]
    if not candidates:
        raise ValueError("Android SDK Build Tools are missing")
    tools = max(candidates, key=lambda path: tuple(map(int, path.name.split("."))))
    apk = root / "build/app/outputs/flutter-apk/app-release.apk"
    certs = run(["java", "-jar", str(tools / "lib/apksigner.jar"), "verify", "--print-certs", str(apk)]).decode("utf-8")
    aapt = tools / ("aapt.exe" if os.name == "nt" else "aapt")
    badging = run([str(aapt), "dump", "badging", str(apk)]).decode("utf-8")
    certificate_hash = hashlib.sha256((root / "android/release-certificate.der").read_bytes()).hexdigest()
    verify_metadata(badging, certs, name, number, certificate_hash)
    output = root / "build/release-assets"
    output.mkdir(parents=True, exist_ok=True)
    target = output / f"shiori-reader-{tag}-android.apk"
    shutil.copyfile(apk, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{digest}  {target.name}\n", encoding="ascii")
    metadata = {"tag": tag, "commit": os.environ["GITHUB_SHA"], "versionName": name,
                "versionCode": int(number), "applicationId": "dev.shiori.reader",
                "apk": target.name, "sha256": digest, "certificateSha256": certificate_hash}
    (output / "release-info.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("version", "signing", "verify"))
    args = parser.parse_args()
    root = Path.cwd()
    if args.command == "signing":
        prepare_signing(root)
    else:
        tag = os.environ.get("GITHUB_REF_NAME", "")
        version((root / "pubspec.yaml").read_text(encoding="utf-8"), tag)
        if args.command == "verify":
            verify_apk(root, tag)
    print("Release " + args.command + " check passed")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError):
        # Do not put secrets or untrusted exception text into Actions annotations.
        print("Release check failed; check version/tag, signing secrets and Android tools.", file=sys.stderr)
        sys.exit(1)
