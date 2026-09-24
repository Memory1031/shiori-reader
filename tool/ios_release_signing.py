"""Prepare CI-only manual App Store signing without creating certificates."""

import base64
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


TEAM = "V95CZH463Y"
GROUP = "group.dev.shiori.reader.import"
TARGETS = {
    "Runner": ("dev.shiori.reader", "97C147071CF9000F007C117D"),
    "ShareExtension": ("dev.shiori.reader.ShareExtension", "85C1EC4F835BA79CAF20E01B"),
}
PROJECT_RELEASE = "97C147041CF9000F007C117D"
API = "https://api.appstoreconnect.apple.com/v1"


def run(*args, input_bytes=None, env=None):
    return subprocess.run(
        args, input=input_bytes, env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True,
    ).stdout


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_signature_to_raw(der):
    # openssl dgst emits ASN.1 DER; App Store Connect JWT ES256 needs R || S.
    if der[0] != 0x30:
        raise ValueError("Invalid ECDSA signature")
    position = 2 if der[1] < 128 else 2 + (der[1] & 0x7F)
    values = []
    for _ in range(2):
        if der[position] != 0x02:
            raise ValueError("Invalid ECDSA signature component")
        length = der[position + 1]
        position += 2
        values.append(int.from_bytes(der[position:position + length], "big").to_bytes(32, "big"))
        position += length
    return b"".join(values)


def token(key_path, key_id, issuer):
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    payload = f"{header}.{claims}"
    signature = run("openssl", "dgst", "-sha256", "-sign", str(key_path), input_bytes=payload.encode())
    return f"{payload}.{b64url(der_signature_to_raw(signature))}"


class AppStoreConnect:
    def __init__(self, key_path, key_id, issuer):
        self.key_path, self.key_id, self.issuer = key_path, key_id, issuer

    def request(self, path, body=None):
        url = path if path.startswith("https://") else API + path
        if not url.startswith(API + "/"):
            raise ValueError("Unexpected App Store Connect pagination URL")
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(
            url, data=data,
            headers={
                "Authorization": "Bearer " + token(self.key_path, self.key_id, self.issuer),
                "Content-Type": "application/json",
            },
            method="POST" if body is not None else "GET",
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Apple may echo request fields in errors; never print the response body.
            raise RuntimeError(f"App Store Connect API returned HTTP {error.code} for {request.method} {url.split('?')[0]}") from None

    def all(self, path):
        result = []
        while path:
            page = self.request(path)
            result.extend(page["data"])
            path = page.get("links", {}).get("next")
        return result


def distribution_certificate(p12_base64, password):
    with tempfile.TemporaryDirectory() as directory:
        p12 = Path(directory) / "distribution.p12"
        p12.write_bytes(base64.b64decode("".join(p12_base64.split()), validate=True))
        env = dict(os.environ, IOS_DIST_CERT_PASSWORD=password)
        pem = run("openssl", "pkcs12", "-in", str(p12), "-clcerts", "-nokeys", "-passin", "env:IOS_DIST_CERT_PASSWORD", env=env)
        der = run("openssl", "x509", "-outform", "DER", input_bytes=pem)
    return der


def find_certificate(api, certificate_der):
    digest = hashlib.sha256(certificate_der).digest()
    certificates = api.all("/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION&limit=200")
    matches = [certificate for certificate in certificates
               if certificate["attributes"].get("certificateContent")
               and hashlib.sha256(base64.b64decode(certificate["attributes"]["certificateContent"])).digest() == digest]
    if len(matches) != 1:
        raise RuntimeError("Imported Distribution p12 does not match exactly one active Apple certificate")
    return matches[0]["id"]


def bundle_id(api, identifier):
    query = urllib.parse.urlencode({"filter[identifier]": identifier, "limit": 200})
    matches = [entry for entry in api.all("/bundleIds?" + query)
               if entry["attributes"]["identifier"] == identifier]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one registered bundle ID: {identifier}")
    return matches[0]["id"]


def find_or_create_profile(api, identifier, bundle, certificate):
    profiles = api.all("/profiles?filter[profileType]=IOS_APP_STORE&filter[profileState]=ACTIVE&include=bundleId,certificates&limit=200")
    for profile in profiles:
        relationships = profile.get("relationships", {})
        if (relationships.get("bundleId", {}).get("data", {}).get("id") == bundle
                and certificate in {item["id"] for item in relationships.get("certificates", {}).get("data", [])}):
            return profile
    name = f"Shiori CI App Store {identifier} {certificate}"
    return api.request("/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle}},
                "certificates": {"data": [{"type": "certificates", "id": certificate}]},
            },
        },
    })["data"]


def validate_and_install(profile, identifier, certificate_der):
    content = profile["attributes"].get("profileContent")
    if not content:
        raise RuntimeError(f"Missing profile content for {identifier}")
    binary = base64.b64decode(content, validate=True)
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "profile.mobileprovision"
        path.write_bytes(binary)
        decoded = plistlib.loads(run("security", "cms", "-D", "-i", str(path)))
    entitlements = decoded["Entitlements"]
    if (entitlements.get("application-identifier") != f"{TEAM}.{identifier}"
            or TEAM not in decoded.get("TeamIdentifier", [])
            or GROUP not in entitlements.get("com.apple.security.application-groups", [])
            or entitlements.get("get-task-allow") is not False
            or certificate_der not in decoded.get("DeveloperCertificates", [])
            or decoded["ExpirationDate"].replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc)):
        raise RuntimeError(f"App Store profile failed certificate, bundle ID, App Group or expiry validation: {identifier}")
    uuid = decoded["UUID"]
    destination = Path.home() / "Library/MobileDevice/Provisioning Profiles" / f"{uuid}.mobileprovision"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(binary)
    return decoded["Name"]


def set_build_setting(text, configuration, key, value):
    pattern = re.compile(rf"(\b{configuration} /\* Release \*/ = \{{.*?buildSettings = \{{)(.*?)(\n\s*\}};\s*name = Release;)", re.S)
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"Could not locate unique Release configuration {configuration}")
    match = matches[0]
    settings = match.group(2)
    setting = re.compile(rf"^\s*{re.escape(key)} = [^\n]*;\r?$", re.M)
    replacement = f"\n\t\t\t\t{key} = {value};"
    if setting.search(settings):
        settings = setting.sub(replacement, settings)
    else:
        settings += replacement
    return text[:match.start(2)] + settings + text[match.end(2):]


def configure_project(project, profile_names):
    text = project.read_text()
    # Project Release has an SDK-specific iPhone Developer identity. Override it
    # only in this runner checkout, keeping local Debug and Release untouched.
    text = set_build_setting(text, PROJECT_RELEASE, '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"', '"Apple Distribution"')
    for target, (_, configuration) in TARGETS.items():
        text = set_build_setting(text, configuration, "CODE_SIGN_STYLE", "Manual")
        text = set_build_setting(text, configuration, "CODE_SIGN_IDENTITY", '"Apple Distribution"')
        name = profile_names[target]
        if not name or any(ord(character) < 32 for character in name):
            raise RuntimeError(f"Unsafe provisioning profile name for {target}")
        escaped = name.replace("\\", "\\\\").replace('"', '\\"')
        text = set_build_setting(text, configuration, "PROVISIONING_PROFILE_SPECIFIER", f'"{escaped}"')
    project.write_text(text)


def configure_export_options(source, destination, profile_names):
    with source.open("rb") as file:
        options = plistlib.load(file)
    if (options.get("method") != "app-store-connect"
            or options.get("signingStyle") != "manual"
            or options.get("teamID") != TEAM):
        raise RuntimeError("ExportOptions.plist must use manual signing for the expected team")
    options["signingCertificate"] = "Apple Distribution"
    options["provisioningProfiles"] = {
        TARGETS[target][0]: name for target, name in profile_names.items()
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as file:
        plistlib.dump(options, file)


def verify_build_settings(profile_names):
    settings = json.loads(run(
        "xcodebuild", "-workspace", "Runner.xcworkspace", "-scheme", "Runner",
        "-configuration", "Release", "-destination", "generic/platform=iOS",
        "-showBuildSettings", "-json",
    ))
    seen = set()
    fields = ("TARGET_NAME", "PRODUCT_BUNDLE_IDENTIFIER", "CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", "DEVELOPMENT_TEAM", "PROVISIONING_PROFILE_SPECIFIER")
    for item in settings:
        values = item["buildSettings"]
        target = values.get("TARGET_NAME")
        if target not in TARGETS:
            continue
        expected_bundle = TARGETS[target][0]
        if (values.get("PRODUCT_BUNDLE_IDENTIFIER") != expected_bundle
                or values.get("CODE_SIGN_STYLE") != "Manual"
                or values.get("CODE_SIGN_IDENTITY") != "Apple Distribution"
                or values.get("DEVELOPMENT_TEAM") != TEAM
                or values.get("PROVISIONING_PROFILE_SPECIFIER") != profile_names[target]):
            raise RuntimeError(f"Unexpected effective Release signing settings for {target}")
        seen.add(target)
        print(json.dumps({field: values.get(field, "") for field in fields}, ensure_ascii=False))
    if seen != TARGETS.keys():
        raise RuntimeError("Runner and ShareExtension must both have manual Distribution signing")


def main():
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    key_path = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    certificate_der = distribution_certificate(os.environ["IOS_DIST_CERT_P12"], os.environ["IOS_DIST_CERT_PASSWORD"])
    identities = run("security", "find-identity", "-v", "-p", "codesigning").decode()
    if hashlib.sha1(certificate_der).hexdigest().upper() not in identities.upper():
        raise RuntimeError("Imported Distribution certificate has no matching keychain signing identity")
    api = AppStoreConnect(key_path, key_id, issuer)
    certificate = find_certificate(api, certificate_der)
    profiles = {}
    for target, (identifier, _) in TARGETS.items():
        profile = find_or_create_profile(api, identifier, bundle_id(api, identifier), certificate)
        if not profile["attributes"].get("profileContent"):
            profile = api.request(f"/profiles/{profile['id']}")["data"]
        profiles[target] = validate_and_install(profile, identifier, certificate_der)
        print(f"Installed validated App Store profile for {target} ({identifier})")
    configure_project(Path("Runner.xcodeproj/project.pbxproj"), profiles)
    configure_export_options(Path("ExportOptions.plist"), Path("../build/ios/ExportOptions.plist"), profiles)
    verify_build_settings(profiles)


if __name__ == "__main__":
    main()
