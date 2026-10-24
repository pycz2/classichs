#!/bin/sh
# Exports the game for every platform into build/release/:
#   ClassicHS-<version>-web.zip, -windows-x86_64.zip (the .exe and the rules .dll), -linux-x86_64.AppImage,
#   -macos.zip, -android-arm64.apk
# Usage: tools/export_all.sh [platform ...]   (web windows linux macos android; all by default)
# Needs Godot 4.7.2 with its export templates on PATH as `godot`. The AppImage needs
# appimagetool on PATH (Linux); Android needs the SDK and a keystore (see .github/workflows/release.yml).
# The rules engine is built first (tools/build_rules.sh) for each platform; with
# RULES_PREBUILT=1 the libraries already in rules/bin are used (CI builds them per platform).
set -e
cd "$(dirname "$0")/.."
VER=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
OUT=build/release
WANT=${*:-web windows linux macos android}
mkdir -p "$OUT"
touch build/.gdignore
tools/build_packs.sh  # res://packs/*.cardpack: the built-in game packs
godot --headless --path . --import >/dev/null 2>&1 || true

rules_lib() {  # the rules engine library a platform's export needs
	case $1 in
	web) echo rules/bin/rules.wasm ;;
	windows) echo rules/bin/classichs_godot.windows.x86_64.dll ;;
	linux) echo rules/bin/libclassichs_godot.linux.x86_64.so ;;
	macos) echo rules/bin/libclassichs_godot.macos.dylib ;;
	android) echo rules/bin/libclassichs_godot.android.arm64.so ;;
	esac
}

for p in $WANT; do
	[ "$RULES_PREBUILT" = 1 ] || tools/build_rules.sh "$p"
	[ -s "$(rules_lib "$p")" ] || { echo "the rules engine for $p is missing: $(rules_lib "$p") (tools/build_rules.sh $p)" >&2; exit 1; }
done

# Android reads a compressed file inside the APK from its start again on every backward seek, so a game
# pack (a zip, read by random access) took minutes to open and the game hung on its splash (0.28.x).
# Godot compresses the files it does not know (.cardpack): store them again uncompressed, align the APK
# and sign it again with the export's key (GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD).
android_store_packs() {  # the APK
	apk=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
	bt=$(ls -d "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"/build-tools/*/ | sort -V | tail -1)
	t=$(mktemp -d)
	(cd "$t" && unzip -q "$apk" 'assets/packs/*.cardpack' && zip -q -0 "$apk" assets/packs/*.cardpack)
	"${bt}zipalign" -P 16 -f 4 "$apk" "$t/aligned.apk"
	"${bt}apksigner" sign --ks "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" --ks-key-alias "$GODOT_ANDROID_KEYSTORE_RELEASE_USER" \
		--ks-pass env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD --key-pass env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD \
		--out "$apk" "$t/aligned.apk"
	rm -rf "$t" "$apk.idsig"
	if unzip -lv "$apk" | grep '\.cardpack$' | grep -qv ' Stored '; then
		echo "a game pack is still compressed in $apk" >&2; exit 1
	fi
	# without INTERNET Android allows no socket: no game server, no pack download (0.29.1)
	if ! "${bt}aapt2" dump permissions "$apk" | grep -q 'android.permission.INTERNET'; then
		echo "$apk does not ask for android.permission.INTERNET (export_presets.cfg permissions/internet)" >&2; exit 1
	fi
}

export_preset() {  # preset name, output path
	mkdir -p "$(dirname "$2")"
	godot --headless --path . --export-release "$1" "$2"
	[ -s "$2" ] || { echo "export of $1 made nothing" >&2; exit 1; }
}

for p in $WANT; do
	case $p in
	web)
		rm -rf "$OUT/web"
		export_preset "Web" "$OUT/web/index.html"
		cp web/rules.js rules/bin/rules.wasm "$OUT/web/"  # the rules engine, loaded by index.html (html/head_include)
		perl -pi -e 's/const CACHEABLE_FILES = \[/const CACHEABLE_FILES = ["rules.js","rules.wasm",/' "$OUT/web/index.service.worker.js"  # offline play (PWA) keeps the engine too
		(cd "$OUT/web" && zip -qr "../ClassicHS-$VER-web.zip" .)
		;;
	windows)
		# Godot puts the rules engine (.dll) next to the .exe: both go into the zip
		rm -rf "$OUT/windows" && mkdir -p "$OUT/windows/ClassicHS"
		export_preset "Windows Desktop" "$OUT/windows/ClassicHS/ClassicHS.exe"
		[ -s "$OUT/windows/ClassicHS/$(basename "$(rules_lib windows)")" ] || { echo "the export did not put the rules .dll next to the .exe" >&2; exit 1; }
		(cd "$OUT/windows" && rm -f "../ClassicHS-$VER-windows-x86_64.zip" && zip -qr "../ClassicHS-$VER-windows-x86_64.zip" ClassicHS)
		;;
	linux)
		rm -rf "$OUT/linux"
		export_preset "Linux" "$OUT/linux/ClassicHS.x86_64"
		SO="$OUT/linux/$(basename "$(rules_lib linux)")"  # the rules engine, next to the binary
		[ -s "$SO" ] || { echo "the export did not put the rules .so next to the binary" >&2; exit 1; }
		if command -v appimagetool >/dev/null; then
			APP="$OUT/linux/AppDir"
			rm -rf "$APP"
			mkdir -p "$APP/usr/bin"
			cp "$OUT/linux/ClassicHS.x86_64" "$SO" "$APP/usr/bin/"
			cp icons/icon_512.png "$APP/classichs.png"
			printf '[Desktop Entry]\nType=Application\nName=Classic HS\nExec=ClassicHS.x86_64\nIcon=classichs\nCategories=Game;CardGame;\n' > "$APP/classichs.desktop"
			printf '#!/bin/sh\nexec "$(dirname "$(readlink -f "$0")")/usr/bin/ClassicHS.x86_64" "$@"\n' > "$APP/AppRun"
			chmod +x "$APP/AppRun"
			ARCH=x86_64 appimagetool "$APP" "$OUT/ClassicHS-$VER-linux-x86_64.AppImage"
		else
			echo "appimagetool not found: a .tar.gz of the binary and the rules .so instead" >&2
			tar -czf "$OUT/ClassicHS-$VER-linux-x86_64.tar.gz" -C "$OUT/linux" ClassicHS.x86_64 "$(basename "$SO")"
		fi
		;;
	macos)
		export_preset "macOS" "$OUT/ClassicHS-$VER-macos.zip"
		;;
	android)
		export_preset "Android" "$OUT/ClassicHS-$VER-android-arm64.apk"
		android_store_packs "$OUT/ClassicHS-$VER-android-arm64.apk"  # (also drops the v4 .idsig the release does not need)
		;;
	*)
		echo "unknown platform: $p" >&2
		exit 1
		;;
	esac
done
for f in packs/*.cardpack; do  # the game packs, for servers started from a release build (--packs-dir)
	[ -f "$f" ] && cp "$f" "$OUT/ClassicHS-$VER-$(basename "$f" .cardpack).cardpack"
done
ls -l "$OUT"/ClassicHS-"$VER"-* 2>/dev/null
