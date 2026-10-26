#!/bin/sh
# Builds the vendored mediaremote-adapter (github.com/ungive/mediaremote-adapter v0.7.7, BSD-3) and checks it works
# on this Mac. build.sh bundles the result into Kilele.app when it's there.
set -e
cd "$(dirname "$0")/../Vendor/mediaremote-adapter"
rm -rf build && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build . >/dev/null
cd ..
/usr/bin/perl bin/mediaremote-adapter.pl "$PWD/build/MediaRemoteAdapter.framework" "$PWD/build/MediaRemoteAdapterTestClient" test \
  && echo "Adapter built and working: Vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework" \
  || { echo "Adapter built, but its self-test failed on this macOS version"; exit 1; }
