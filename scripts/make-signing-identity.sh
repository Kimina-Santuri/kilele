#!/bin/sh
# One-time: creates a self-signed "Kilele Local Signing" code-signing identity (10 years) in your login keychain,
# usable by codesign without a prompt. Signing every build with it keeps Kilele's signature stable, so macOS
# remembers its permissions (Bluetooth, Calendar, Reminders, Documents, Automation) across rebuilds.
# It isn't marked as trusted and no system trust settings change. Remove it any time in Keychain Access.
set -e
NAME="Kilele Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "\"$NAME\" already exists"; exit 0; fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/cert.cnf" 2>/dev/null
PW=$(openssl rand -hex 16)
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PW" 2>/dev/null
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PW" -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\". Rebuild with scripts/build.sh --install; macOS will ask for permissions once more, then remember them."
