#!/usr/bin/env python3
"""Create the App Store signing certificate and provisioning profile through the
App Store Connect API, so the one-time signing setup does not need a Mac.

Apple's own tooling makes the private key inside Keychain Access, which is why the
usual advice is "export the .p12 from your Mac". Nothing about that is required:
the key can be generated anywhere, the certificate signing request submitted over
the API, and the .p12 assembled with openssl. This script does that, and can also
list and revoke certificates, which is the way out of "your account has reached
the maximum number of certificates" without a Mac.

Needs python3 and openssl. Credentials come from the same App Store Connect API
key the release workflows already use:

    export APP_STORE_CONNECT_API_KEY_ID=...
    export APP_STORE_CONNECT_ISSUER_ID=...
    export APP_STORE_CONNECT_API_KEY_CONTENT="$(cat AuthKey_XXX.p8)"

    Tools/bootstrap_signing.py list
    Tools/bootstrap_signing.py create --set-secrets
    Tools/bootstrap_signing.py revoke <certificate-id>

See "Required Secrets" in README.md.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_ROOT = "https://api.appstoreconnect.apple.com"
CERTIFICATE_TYPE = "DISTRIBUTION"  # yields an "Apple Distribution" identity
PROFILE_TYPE = "IOS_APP_STORE"
# What the app's entitlements claim, so the App ID allows it before a profile is minted:
# a profile only carries the capabilities the App ID has switched on, and an archive whose
# entitlements ask for one the profile lacks fails at signing. The quiz claims nothing
# beyond the default sandbox, so there is nothing to switch on — add the capability here
# the same day an entitlement asking for it lands in project.yml.
CAPABILITIES: list[str] = []


class Failure(Exception):
    """Something the user needs to fix, reported without a traceback."""


def openssl(*args: str, stdin: bytes | None = None) -> bytes:
    result = subprocess.run(
        ["openssl", *args], input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if result.returncode != 0:
        detail = result.stderr.decode(errors="replace").strip()
        raise Failure(f"openssl {args[0]} failed: {detail}")
    return result.stdout


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_signature_to_raw(der: bytes) -> bytes:
    """ECDSA signatures come out of openssl as DER; JWS wants raw r||s."""

    def read_integer(data: bytes, offset: int) -> tuple[int, int]:
        if data[offset] != 0x02:
            raise Failure("malformed ECDSA signature from openssl")
        length = data[offset + 1]
        start = offset + 2
        return int.from_bytes(data[start : start + length], "big"), start + length

    if not der or der[0] != 0x30:
        raise Failure("malformed ECDSA signature from openssl")
    body = 2 + (2 if der[1] & 0x80 else 0)  # skip the SEQUENCE header
    r, offset = read_integer(der, body)
    s, _ = read_integer(der, offset)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


class AppStoreConnect:
    def __init__(self, key_id: str, issuer_id: str, key_pem: str) -> None:
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_file = tempfile.NamedTemporaryFile("w", suffix=".p8", delete=False)
        self.key_file.write(key_pem if key_pem.endswith("\n") else key_pem + "\n")
        self.key_file.close()
        os.chmod(self.key_file.name, 0o600)

    def close(self) -> None:
        os.unlink(self.key_file.name)

    def _token(self) -> str:
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        now = int(time.time())
        payload = {
            "iss": self.issuer_id,
            "iat": now,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        }
        signing_input = ".".join(
            b64url(json.dumps(part, separators=(",", ":")).encode())
            for part in (header, payload)
        ).encode()
        der = openssl("dgst", "-sha256", "-sign", self.key_file.name, stdin=signing_input)
        return f"{signing_input.decode()}.{b64url(der_signature_to_raw(der))}"

    def request(
        self,
        method: str,
        path: str,
        body: dict | None = None,
        params: dict[str, str] | None = None,
    ) -> dict:
        url = f"{API_ROOT}{path}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
        request = urllib.request.Request(
            url,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={
                "Authorization": f"Bearer {self._token()}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            raise Failure(self._describe(error)) from None
        except urllib.error.URLError as error:
            raise Failure(f"could not reach {API_ROOT}: {error.reason}") from None
        return json.loads(raw) if raw else {}

    @staticmethod
    def _describe(error: urllib.error.HTTPError) -> str:
        try:
            errors = json.loads(error.read())["errors"]
        except Exception:
            return f"App Store Connect returned HTTP {error.code}"
        lines = [
            f"{item.get('title', 'error')}: {item.get('detail', '')}".strip(": ")
            for item in errors
        ]
        return f"App Store Connect returned HTTP {error.code}\n  " + "\n  ".join(lines)


def distribution_certificates(api: AppStoreConnect) -> list[dict]:
    response = api.request(
        "GET",
        "/v1/certificates",
        params={"filter[certificateType]": CERTIFICATE_TYPE, "limit": "200"},
    )
    return response.get("data", [])


def describe_certificate(certificate: dict) -> str:
    attributes = certificate["attributes"]
    return (
        f"{certificate['id']}  {attributes.get('displayName', '?')}"
        f"  serial {attributes.get('serialNumber', '?')}"
        f"  expires {attributes.get('expirationDate', '?')}"
    )


def create_certificate(api: AppStoreConnect, common_name: str) -> tuple[Path, dict]:
    work = Path(tempfile.mkdtemp(prefix="signing-"))
    key_path = work / "private-key.pem"
    openssl("genrsa", "-out", str(key_path), "2048")
    key_path.chmod(0o600)
    csr = openssl(
        "req", "-new", "-key", str(key_path), "-subj", f"/CN={common_name}"
    ).decode()

    try:
        response = api.request(
            "POST",
            "/v1/certificates",
            {
                "data": {
                    "type": "certificates",
                    "attributes": {
                        "certificateType": CERTIFICATE_TYPE,
                        "csrContent": csr,
                    },
                }
            },
        )
    except Failure as error:
        if "maximum number of certificates" in str(error).lower():
            existing = distribution_certificates(api)
            listing = "\n  ".join(describe_certificate(c) for c in existing)
            raise Failure(
                f"{error}\n\nThe account is at its distribution certificate limit. "
                "These exist today:\n  "
                f"{listing}\n\nRevoke the ones you no longer hold a .p12 for, then "
                "retry:\n  Tools/bootstrap_signing.py revoke <certificate-id>"
            ) from None
        raise
    return key_path, response["data"]


def all_profiles(api: AppStoreConnect) -> list[dict]:
    return api.request("GET", "/v1/profiles", params={"limit": "200"}).get("data", [])


def profile_certificate_ids(api: AppStoreConnect, profile_id: str) -> list[str]:
    certificates = api.request("GET", f"/v1/profiles/{profile_id}/certificates").get(
        "data", []
    )
    return [certificate["id"] for certificate in certificates]


def ensure_bundle_id(api: AppStoreConnect, identifier: str, name: str) -> str:
    found = api.request(
        "GET", "/v1/bundleIds", params={"filter[identifier]": identifier, "limit": "200"}
    ).get("data", [])
    for bundle in found:
        if bundle["attributes"]["identifier"] == identifier:
            return bundle["id"]
    created = api.request(
        "POST",
        "/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": identifier,
                    "name": name,
                    "platform": "IOS",
                },
            }
        },
    )
    print(f"Registered App ID {identifier}")
    return created["data"]["id"]


def ensure_capabilities(api: AppStoreConnect, bundle_id: str, identifier: str) -> None:
    """Switch on, for the App ID, every capability the app's entitlements claim.

    The capabilities are read off the App ID's own relationship, which takes no
    parameters at all — asking it for a `limit` the way the flat collections above are
    asked is an HTTP 400, and was: "The parameter 'limit' can not be used with this
    request". There is nothing to page through in any case, since an App ID has a
    couple of dozen capabilities at the outside and Apple hands back all of them.
    """
    enabled = {
        capability["attributes"]["capabilityType"]
        for capability in api.request(
            "GET", f"/v1/bundleIds/{bundle_id}/bundleIdCapabilities"
        ).get("data", [])
    }
    for capability in CAPABILITIES:
        if capability in enabled:
            continue
        api.request(
            "POST",
            "/v1/bundleIdCapabilities",
            {
                "data": {
                    "type": "bundleIdCapabilities",
                    "attributes": {"capabilityType": capability},
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}
                    },
                }
            },
        )
        print(f"Enabled {capability} on App ID {identifier}")


def replace_profile(
    api: AppStoreConnect, name: str, bundle_id: str, certificate_id: str
) -> dict:
    for profile in api.request(
        "GET", "/v1/profiles", params={"filter[name]": name, "limit": "200"}
    ).get("data", []):
        api.request("DELETE", f"/v1/profiles/{profile['id']}")
        print(f"Removed the previous '{name}' profile")

    response = api.request(
        "POST",
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": PROFILE_TYPE},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                    "certificates": {
                        "data": [{"type": "certificates", "id": certificate_id}]
                    },
                },
            }
        },
    )
    return response["data"]


def build_p12(key_path: Path, certificate_der: bytes, password: str) -> bytes:
    work = key_path.parent
    cert_pem = work / "certificate.pem"
    cert_pem.write_bytes(
        openssl("x509", "-inform", "DER", "-outform", "PEM", stdin=certificate_der)
    )
    p12 = work / "certificate.p12"
    openssl(
        "pkcs12",
        "-export",
        "-inkey",
        str(key_path),
        "-in",
        str(cert_pem),
        "-out",
        str(p12),
        "-passout",
        f"pass:{password}",
        # macOS `security import` is happiest with the older PKCS#12 algorithms.
        "-keypbe",
        "PBE-SHA1-3DES",
        "-certpbe",
        "PBE-SHA1-3DES",
        "-macalg",
        "sha1",
    )
    return p12.read_bytes()


def set_github_secret(name: str, value: str, repo: str | None) -> None:
    command = ["gh", "secret", "set", name]
    if repo:
        command += ["--repo", repo]
    result = subprocess.run(command, input=value.encode(), stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise Failure(
            f"could not set {name}: {result.stderr.decode(errors='replace').strip()}"
        )
    print(f"Set secret {name}")


def write_secret_files(out_dir: Path, secrets_to_write: dict[str, str]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    out_dir.chmod(0o700)
    for name, value in secrets_to_write.items():
        path = out_dir / f"{name}.txt"
        path.write_text(value)
        path.chmod(0o600)


def load_api(args: argparse.Namespace) -> AppStoreConnect:
    key_id = os.environ.get("APP_STORE_CONNECT_API_KEY_ID", "")
    issuer_id = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "")
    key_pem = os.environ.get("APP_STORE_CONNECT_API_KEY_CONTENT", "")
    if args.key_file:
        key_pem = Path(args.key_file).read_text()
    missing = [
        name
        for name, value in (
            ("APP_STORE_CONNECT_API_KEY_ID", key_id),
            ("APP_STORE_CONNECT_ISSUER_ID", issuer_id),
            ("APP_STORE_CONNECT_API_KEY_CONTENT", key_pem),
        )
        if not value
    ]
    if missing:
        raise Failure(
            "missing credentials: "
            + ", ".join(missing)
            + "\nThese are the same values as the GitHub secrets of the same name."
        )
    if "PRIVATE KEY" not in key_pem:
        raise Failure(
            "the API key does not look like a .p8 file — it must include the "
            "-----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY----- lines"
        )
    return AppStoreConnect(key_id, issuer_id, key_pem)


def command_list(api: AppStoreConnect, args: argparse.Namespace) -> None:
    certificates = distribution_certificates(api)
    if certificates:
        print(f"Distribution certificates ({len(certificates)}):")
        for certificate in certificates:
            print(f"  {describe_certificate(certificate)}")
    else:
        print("No distribution certificates on the account.")
    profiles = api.request(
        "GET", "/v1/profiles", params={"filter[profileType]": PROFILE_TYPE, "limit": "200"}
    ).get("data", [])
    print(f"\nApp Store profiles ({len(profiles)}):")
    for profile in profiles:
        attributes = profile["attributes"]
        print(
            f"  {attributes.get('name')}  {attributes.get('profileState')}"
            f"  expires {attributes.get('expirationDate')}"
        )
    print(
        "\nA certificate is only usable by CI if you still hold its private key, "
        "which lives in the .p12 this script wrote when it created the certificate."
    )


def command_revoke(api: AppStoreConnect, args: argparse.Namespace) -> None:
    for certificate_id in args.certificate_id:
        api.request("DELETE", f"/v1/certificates/{certificate_id}")
        print(f"Revoked {certificate_id}")
    print(
        "\nAny build still signing with a revoked certificate will fail, so re-run "
        "`bootstrap_signing.py create` if you revoked the one CI was using."
    )


def command_cleanup(api: AppStoreConnect, args: argparse.Namespace) -> None:
    """Retire the certificates earlier builds created.

    Builds that mint their own certificate name the profile after the run, so the
    profile names identify which certificates belong to CI and which belong to a
    person. Anything matching the prefix goes, along with the certificates it was
    issued for.
    """
    doomed: set[str] = set()
    for profile in all_profiles(api):
        name = profile["attributes"].get("name", "")
        if not name.startswith(args.profile_prefix) or name == args.keep:
            continue
        doomed.update(profile_certificate_ids(api, profile["id"]))
        api.request("DELETE", f"/v1/profiles/{profile['id']}")
        print(f"Deleted profile {name}")

    if args.include_orphans:
        # A run that died between creating the certificate and creating the profile
        # leaves a certificate nothing points at, which the sweep above cannot see.
        still_used: set[str] = set()
        for profile in all_profiles(api):
            still_used.update(profile_certificate_ids(api, profile["id"]))
        for certificate in distribution_certificates(api):
            if certificate["id"] not in still_used:
                doomed.add(certificate["id"])

    kept = 0
    for certificate in distribution_certificates(api):
        if certificate["id"] not in doomed:
            continue
        if certificate["attributes"].get("serialNumber") in args.keep_serial:
            doomed.discard(certificate["id"])
            kept += 1
            print(f"Keeping {describe_certificate(certificate)}")

    for certificate_id in sorted(doomed):
        api.request("DELETE", f"/v1/certificates/{certificate_id}")
        print(f"Revoked certificate {certificate_id}")

    remaining = distribution_certificates(api)
    print(
        f"{len(doomed)} certificate(s) revoked, {kept} kept by serial, "
        f"{len(remaining)} left on the account."
    )


def command_create(api: AppStoreConnect, args: argparse.Namespace) -> None:
    # The App ID first, and the certificate only once it is settled. Apple caps the
    # account at a couple of certificates and a minted one cannot be handed back, so
    # anything that might fail belongs in front of the minting rather than behind it:
    # a run that died between the two left a certificate nobody holds the key to, and
    # the next build's sweep had to clear it away.
    bundle_id = ensure_bundle_id(api, args.bundle_id, args.app_name)
    ensure_capabilities(api, bundle_id, args.bundle_id)

    key_path, certificate = create_certificate(api, args.common_name)
    attributes = certificate["attributes"]
    print(
        f"Created certificate {attributes.get('displayName')} "
        f"(serial {attributes.get('serialNumber')}, "
        f"expires {attributes.get('expirationDate')})"
    )

    profile = replace_profile(api, args.profile_name, bundle_id, certificate["id"])
    print(
        f"Created profile {profile['attributes']['name']} "
        f"(expires {profile['attributes']['expirationDate']})"
    )

    password = args.password or secrets.token_urlsafe(24)
    p12 = build_p12(
        key_path, base64.b64decode(attributes["certificateContent"]), password
    )
    values = {
        "APPLE_DISTRIBUTION_CERT_P12": base64.b64encode(p12).decode(),
        "APPLE_DISTRIBUTION_CERT_PASSWORD": password,
        "APPLE_PROVISIONING_PROFILE": profile["attributes"]["profileContent"],
    }

    if args.ephemeral:
        write_secret_files(Path(args.out_dir), values)
        print(
            f"\nWrote the certificate to {args.out_dir}/ for this build to sign with. "
            "A later build retires it:\n  Tools/bootstrap_signing.py cleanup "
            f"--profile-prefix '{args.profile_name.rsplit(' ', 1)[0]} '"
        )
    elif args.set_secrets:
        for name, value in values.items():
            set_github_secret(name, value, args.repo)
        print("\nTestFlight builds can sign now. Nothing was written to disk.")
    else:
        out_dir = Path(args.out_dir)
        write_secret_files(out_dir, values)
        print(f"\nWrote the three secret values to {out_dir}/ (gitignored). Set them:")
        for name in values:
            print(f"  gh secret set {name} < {out_dir}/{name}.txt")
        print(
            f"\nKeep {out_dir}/APPLE_DISTRIBUTION_CERT_P12.txt somewhere safe before "
            "deleting the directory — it holds the only copy of the private key, and "
            "Apple cannot reissue it."
        )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--key-file", help="read the App Store Connect .p8 from this path instead of the environment"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    listing = subparsers.add_parser("list", help="show the account's certificates and profiles")
    listing.set_defaults(handler=command_list)

    revoke = subparsers.add_parser("revoke", help="revoke certificates by id")
    revoke.add_argument("certificate_id", nargs="+")
    revoke.set_defaults(handler=command_revoke)

    cleanup = subparsers.add_parser(
        "cleanup", help="retire the certificates and profiles earlier builds created"
    )
    cleanup.add_argument("--profile-prefix", default="NYC Neighborhoods CI ")
    cleanup.add_argument("--keep", default="", help="profile name to leave alone")
    cleanup.add_argument(
        "--keep-serial",
        action="append",
        default=[],
        help="serial number never to revoke; repeatable",
    )
    cleanup.add_argument(
        "--include-orphans",
        action="store_true",
        help="also revoke distribution certificates no profile references",
    )
    cleanup.set_defaults(handler=command_cleanup)

    create = subparsers.add_parser(
        "create", help="create a certificate and profile, and emit the three secrets"
    )
    create.add_argument("--bundle-id", default="com.nycneighborhoodsquiz.app")
    create.add_argument("--app-name", default="NYC Neighborhoods: Map Quiz")
    create.add_argument("--profile-name", default="NYC Neighborhoods App Store")
    create.add_argument("--common-name", default="NYC Neighborhoods CI", help="subject of the signing request")
    create.add_argument("--password", help="password for the .p12 (random if omitted)")
    create.add_argument("--out-dir", default=".signing-secrets")
    create.add_argument(
        "--set-secrets",
        action="store_true",
        help="store the values as GitHub secrets with gh instead of writing files",
    )
    create.add_argument(
        "--ephemeral",
        action="store_true",
        help="the certificate is for one build and will be retired, so skip the "
        "advice about keeping it",
    )
    create.add_argument("--repo", help="owner/name to pass to gh, when it cannot be inferred")
    create.set_defaults(handler=command_create)

    args = parser.parse_args(argv)
    api = load_api(args)
    try:
        args.handler(api, args)
    finally:
        api.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Failure as failure:
        print(f"error: {failure}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
