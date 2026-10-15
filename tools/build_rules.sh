#!/bin/sh
# Builds the rules engine (rust/) for the game into rules/bin/ (not committed):
#   macos    rules/bin/libclassichs_godot.macos.dylib     (universal: arm64 + x86_64, lipo)
#   windows  rules/bin/classichs_godot.windows.x86_64.dll (on Windows)
#   linux    rules/bin/libclassichs_godot.linux.x86_64.so (on Linux x86_64)
#   android  rules/bin/libclassichs_godot.android.arm64.so (needs the Android NDK)
#   web      rules/bin/rules.wasm (+ web/rules.js loads it next to index.html)
#   all      what this machine can build: its desktop platform, android (if an NDK is found), web
# Usage: tools/build_rules.sh [platform ...]   (all by default)
# Needs Rust (rustup) with the targets; the NDK is taken from ANDROID_NDK_HOME,
# ANDROID_NDK_ROOT or the newest one in $ANDROID_HOME/ndk (or ~/Library/Android/sdk/ndk).
set -e
cd "$(dirname "$0")/.."
# rustup's cargo first (a Homebrew Rust on PATH has no cross targets)
for d in /opt/homebrew/opt/rustup/bin "$HOME/.cargo/bin"; do
	[ -x "$d/cargo" ] && { PATH="$d:$PATH"; break; }
done
BIN=rules/bin
mkdir -p "$BIN"
T=rust/target

target() {  # makes sure a Rust target is installed
	command -v rustup >/dev/null && rustup target list --installed | grep -qx "$1" || rustup target add "$1"
}

ndk() {
	for d in "$ANDROID_NDK_HOME" "$ANDROID_NDK_ROOT"; do
		[ -n "$d" ] && [ -d "$d" ] && { echo "$d"; return; }
	done
	for sdk in "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
		[ -n "$sdk" ] && [ -d "$sdk/ndk" ] && { ls -d "$sdk"/ndk/*/ | sort -V | tail -1 | sed 's,/$,,'; return; }
	done
}

build() {
	case $1 in
	macos)
		for t in aarch64-apple-darwin x86_64-apple-darwin; do
			target $t
			(cd rust && cargo build -p classichs-godot --release --target $t)
		done
		lipo -create -output "$BIN/libclassichs_godot.macos.dylib" \
			$T/aarch64-apple-darwin/release/libclassichs_godot.dylib $T/x86_64-apple-darwin/release/libclassichs_godot.dylib
		;;
	windows)
		(cd rust && cargo build -p classichs-godot --release)
		cp $T/release/classichs_godot.dll "$BIN/classichs_godot.windows.x86_64.dll"
		;;
	linux)
		(cd rust && cargo build -p classichs-godot --release)
		cp $T/release/libclassichs_godot.so "$BIN/libclassichs_godot.linux.x86_64.so"
		;;
	android)
		NDK=$(ndk)
		[ -n "$NDK" ] || { echo "no Android NDK found (set ANDROID_NDK_HOME)" >&2; exit 1; }
		LLVM=$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/ | head -1)
		target aarch64-linux-android
		export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${LLVM}bin/aarch64-linux-android24-clang"
		export CC_aarch64_linux_android="$CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER"
		export AR_aarch64_linux_android="${LLVM}bin/llvm-ar"
		(cd rust && cargo build -p classichs-godot --release --target aarch64-linux-android)
		cp $T/aarch64-linux-android/release/libclassichs_godot.so "$BIN/libclassichs_godot.android.arm64.so"
		;;
	web)
		target wasm32-unknown-unknown
		(cd rust && cargo build -p classichs-wasm --profile wasm --target wasm32-unknown-unknown)
		cp $T/wasm32-unknown-unknown/wasm/classichs_wasm.wasm "$BIN/rules.wasm"
		;;
	*)
		echo "unknown platform: $1" >&2
		exit 1
		;;
	esac
	echo "rules: $1 built"
}

WANT=${*:-all}
if [ "$WANT" = all ]; then
	case $(uname -s) in
	Darwin) WANT=macos ;;
	Linux) WANT=linux ;;
	*) WANT=windows ;;
	esac
	[ -n "$(ndk)" ] && WANT="$WANT android"
	WANT="$WANT web"
fi
for p in $WANT; do build "$p"; done
ls -l "$BIN"
