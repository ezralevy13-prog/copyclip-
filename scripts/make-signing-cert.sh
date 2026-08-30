#!/bin/bash
#
# Creates a self-signed code-signing certificate in your login keychain.
#
# Why bother for a local build: macOS ties the Accessibility permission to an
# app's code signature. An ad-hoc signature (`codesign -s -`) changes every time
# the binary changes, so macOS treats each rebuild as a different app and
# silently drops the permission -- auto-paste just stops working. Signing with a
# stable self-signed identity keeps the grant across rebuilds.
#
# Run once, then add this to your shell profile:
#     export CLIPWELL_SIGN_IDENTITY="Clipwell Local Signing"
set -euo pipefail

CERT_NAME="Clipwell Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "Certificate '$CERT_NAME' already exists."
    echo "Add this to your shell profile if you haven't:"
    echo "    export CLIPWELL_SIGN_IDENTITY=\"$CERT_NAME\""
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = Clipwell Local Signing

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
CNF

echo "==> Generating key and certificate"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/bundle.p12" -passout pass: -name "$CERT_NAME"

echo "==> Importing into login keychain"
# -T authorises codesign to use the key without prompting on every build.
security import "$TMP/bundle.p12" -k "$KEYCHAIN" -P "" \
    -T /usr/bin/codesign -T /usr/bin/security

echo "==> Trusting for code signing"
# Needs an admin password. Without trust, codesign refuses the identity.
sudo security add-trusted-cert -d -r trustRoot \
    -p codeSign -k /Library/Keychains/System.keychain "$TMP/cert.pem"

# Stops the keychain prompting for permission on every single build.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo
echo "Done. Add this to your ~/.zshrc:"
echo "    export CLIPWELL_SIGN_IDENTITY=\"$CERT_NAME\""
echo
echo "Then rebuild with ./build.sh and grant Accessibility once."
