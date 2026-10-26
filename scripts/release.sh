#!/bin/sh
# Publishes a Kilele release that installed copies pick up through "Check for updates".
#   scripts/release.sh 0.3.0 "What changed"
# Sets the version in Support/Info.plist, builds and signs (with "Kilele Local Signing": the updater only installs
# builds signed like the running copy), zips the app, commits and tags vVERSION, pushes, and creates the GitHub release
# with Kilele.zip attached.
set -e
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release.sh VERSION [notes]}
NOTES=${2:-"Kilele $VERSION"}
security find-certificate -c "Kilele Local Signing" >/dev/null 2>&1 || { echo "Run scripts/make-signing-identity.sh first"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first"; exit 1; }
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Support/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" -c "Set CFBundleVersion $BUILD" Support/Info.plist
scripts/build.sh
rm -f build/Kilele.zip
ditto -c -k --keepParent build/Kilele.app build/Kilele.zip
git commit -qm "Release $VERSION" Support/Info.plist
git tag "v$VERSION"
git push -q origin main "v$VERSION"
gh release create "v$VERSION" build/Kilele.zip --title "Kilele $VERSION" --notes "$NOTES"
