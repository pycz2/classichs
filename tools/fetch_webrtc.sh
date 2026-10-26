#!/bin/sh
# Puts the WebRTC plugin (godotengine/webrtc-native, GDExtension) for the native builds into
# addons/webrtc_native/lib/ (not committed): Windows, macOS, Linux and Android get the same
# WebRTCPeerConnection the browser gives the Web build, so code play works everywhere.
# A pinned release, checked by its SHA-256; only the libraries of our export platforms are kept.
# Does nothing when that version is already there. Usage: tools/fetch_webrtc.sh
set -e
cd "$(dirname "$0")/.."
VER=1.2.2-stable
SHA=98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5
DIR=addons/webrtc_native/lib
[ "$(cat "$DIR/VERSION" 2>/dev/null)" = "$VER" ] && exit 0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -sSfL -o "$tmp/w.zip" "https://github.com/godotengine/webrtc-native/releases/download/$VER/godot-extension-webrtc_native.zip"
got=$( (sha256sum "$tmp/w.zip" 2>/dev/null || shasum -a 256 "$tmp/w.zip") | cut -d' ' -f1)
[ "$got" = "$SHA" ] || { echo "webrtc-native $VER: SHA-256 $got, expected $SHA" >&2; exit 1; }
rm -rf "$DIR" && mkdir -p "$DIR"
unzip -q "$tmp/w.zip" -d "$tmp/x"
for t in template_debug template_release; do
	for f in "linux.$t.x86_64.so" "windows.$t.x86_64.dll" "android.$t.arm64.so" "macos.$t.universal.framework"; do
		cp -R "$tmp/x/addons/webrtc_native/lib/libwebrtc_native.$f" "$DIR/"
	done
done
echo "$VER" > "$DIR/VERSION"
echo "webrtc-native $VER → $DIR"
