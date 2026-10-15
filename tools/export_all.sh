#!/bin/sh
# Exports the game for every platform into build/release/:
#   ClassicHS-<version>-web.zip, -windows-x86_64.exe, -linux-x86_64.AppImage,
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
		export_preset "Windows Desktop" "$OUT/ClassicHS-$VER-windows-x86_64.exe"
		;;
	linux)
		export_preset "Linux" "$OUT/linux/ClassicHS.x86_64"
		if command -v appimagetool >/dev/null; then
			APP="$OUT/linux/AppDir"
			rm -rf "$APP"
			mkdir -p "$APP/usr/bin"
			cp "$OUT/linux/ClassicHS.x86_64" "$APP/usr/bin/"
			cp icons/icon_512.png "$APP/classichs.png"
			printf '[Desktop Entry]\nType=Application\nName=Classic HS\nExec=ClassicHS.x86_64\nIcon=classichs\nCategories=Game;CardGame;\n' > "$APP/classichs.desktop"
			printf '#!/bin/sh\nexec "$(dirname "$(readlink -f "$0")")/usr/bin/ClassicHS.x86_64" "$@"\n' > "$APP/AppRun"
			chmod +x "$APP/AppRun"
			ARCH=x86_64 appimagetool "$APP" "$OUT/ClassicHS-$VER-linux-x86_64.AppImage"
		else
			echo "appimagetool not found: only the plain Linux binary was made" >&2
			cp "$OUT/linux/ClassicHS.x86_64" "$OUT/ClassicHS-$VER-linux-x86_64"
		fi
		;;
	macos)
		export_preset "macOS" "$OUT/ClassicHS-$VER-macos.zip"
		;;
	android)
		export_preset "Android" "$OUT/ClassicHS-$VER-android-arm64.apk"
		rm -f "$OUT/ClassicHS-$VER-android-arm64.apk.idsig"  # (a v4 signature file the release does not need)
		;;
	*)
		echo "unknown platform: $p" >&2
		exit 1
		;;
	esac
done
ls -l "$OUT"/ClassicHS-"$VER"-* 2>/dev/null
