#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain. Signing every build
# with the same identity keeps the designated requirement stable, so the Automation and
# Accessibility grants in TCC survive rebuilds (ad-hoc signatures change with every build).
set -euo pipefail
NAME="${1:-ChromeProfileBar Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate \"$NAME\" already exists."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout pass:temp -out "$TMP/id.p12"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P temp -T /usr/bin/codesign
echo "Created \"$NAME\"."
