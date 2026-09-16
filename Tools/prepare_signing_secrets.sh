#!/usr/bin/env bash
#
# Turns a distribution certificate and an App Store provisioning profile into the
# base64 blobs the release workflows expect as GitHub secrets, after checking that
# the two actually belong together. Run this once; the same certificate is then
# reused by every build instead of Apple issuing a new one per run.
#
#   Tools/prepare_signing_secrets.sh Certificates.p12 NeighborhoodQuiz_AppStore.mobileprovision
#
# See "Required Secrets" in README.md for where the two files come from.

set -euo pipefail

OUT_DIR="${OUT_DIR:-.signing-secrets}"

die() { echo "error: $*" >&2; exit 1; }

if [ $# -ne 2 ]; then
  echo "usage: $(basename "$0") <certificate.p12> <profile.mobileprovision>" >&2
  exit 2
fi

P12="$1"
PROFILE="$2"

[ -r "$P12" ] || die "cannot read $P12"
[ -r "$PROFILE" ] || die "cannot read $PROFILE"
command -v openssl > /dev/null || die "openssl is required"
command -v python3 > /dev/null || die "python3 is required"

if [ -n "${P12_PASSWORD:-}" ]; then
  PASSWORD="$P12_PASSWORD"
else
  read -rsp "Password for $P12: " PASSWORD
  echo
fi
export PASSWORD

CERT_PEM=$(openssl pkcs12 -in "$P12" -clcerts -nokeys -passin env:PASSWORD 2>/dev/null) \
  || die "could not open $P12 — wrong password, or not a PKCS#12 file"

openssl pkcs12 -in "$P12" -nocerts -nodes -passin env:PASSWORD 2>/dev/null | grep -q "PRIVATE KEY" \
  || die "$P12 contains no private key. Export it from Keychain Access with the key, not just the certificate."

CERT_SUBJECT=$(printf '%s' "$CERT_PEM" | openssl x509 -noout -subject | sed 's/^subject= *//')
CERT_EXPIRY=$(printf '%s' "$CERT_PEM" | openssl x509 -noout -enddate | cut -d= -f2)
CERT_SHA1=$(printf '%s' "$CERT_PEM" | openssl x509 -outform DER | openssl dgst -sha1 | awk '{print tolower($NF)}')

printf '%s' "$CERT_PEM" | openssl x509 -noout -checkend 0 > /dev/null \
  || die "the certificate expired on $CERT_EXPIRY"

case "$CERT_SUBJECT" in
  *Distribution*) ;;
  *) echo "warning: '$CERT_SUBJECT' does not look like a distribution certificate" >&2 ;;
esac

PROFILE_PLIST=$(mktemp)
trap 'rm -f "$PROFILE_PLIST"' EXIT
if command -v security > /dev/null; then
  security cms -D -i "$PROFILE" -o "$PROFILE_PLIST" 2> /dev/null \
    || die "could not decode $PROFILE as a provisioning profile"
else
  openssl smime -verify -noverify -inform DER -in "$PROFILE" -out "$PROFILE_PLIST" 2> /dev/null \
    || die "could not decode $PROFILE as a provisioning profile"
fi

eval "$(python3 - "$PROFILE_PLIST" <<'PY'
import hashlib, plistlib, shlex, sys

with open(sys.argv[1], "rb") as handle:
    profile = plistlib.load(handle)

fields = {
    "PROFILE_NAME": profile.get("Name", ""),
    "PROFILE_UUID": profile.get("UUID", ""),
    "PROFILE_EXPIRY": str(profile.get("ExpirationDate", "")),
    "PROFILE_APP_ID": profile.get("Entitlements", {}).get("application-identifier", ""),
    "PROFILE_CERT_SHA1S": " ".join(
        hashlib.sha1(cert).hexdigest() for cert in profile.get("DeveloperCertificates", [])
    ),
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(value)}")
PY
)"

[ -n "$PROFILE_NAME" ] || die "$PROFILE has no name — is it a provisioning profile?"

case " $PROFILE_CERT_SHA1S " in
  *" $CERT_SHA1 "*) ;;
  *) die "$PROFILE was not issued for this certificate. Regenerate the profile in the developer portal and pick the certificate in $P12." ;;
esac

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
base64 < "$P12" | tr -d '\n' > "$OUT_DIR/APPLE_DISTRIBUTION_CERT_P12.txt"
base64 < "$PROFILE" | tr -d '\n' > "$OUT_DIR/APPLE_PROVISIONING_PROFILE.txt"
chmod 600 "$OUT_DIR"/*.txt

cat <<EOF

Certificate: $CERT_SUBJECT
             expires $CERT_EXPIRY
Profile:     $PROFILE_NAME
             $PROFILE_APP_ID, expires $PROFILE_EXPIRY
             signed for this certificate

Wrote base64 values to $OUT_DIR/ (gitignored). Set them with:

  gh secret set APPLE_DISTRIBUTION_CERT_P12 < $OUT_DIR/APPLE_DISTRIBUTION_CERT_P12.txt
  gh secret set APPLE_PROVISIONING_PROFILE < $OUT_DIR/APPLE_PROVISIONING_PROFILE.txt
  gh secret set APPLE_DISTRIBUTION_CERT_PASSWORD

Then delete $OUT_DIR/ — the .p12 is the only copy of the private key, so keep it
somewhere safe (a password manager) rather than on disk next to the repo.
EOF
