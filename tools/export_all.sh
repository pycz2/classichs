#!/bin/sh
# Exports the game for every platform into build/release/:
#   ClassicHS-<version>-web.zip, -windows-x86_64.exe, -linux-x86_64.AppImage,
#   -macos.zip, -android-arm64.apk
# Usage: tools/export_all.sh [platform ...]   (web windows linux macos android; all by default)
# Needs Godot 4.7.2 with its export templates on PATH as `godot`. The AppImage needs
# appimagetool on PATH (Linux); Android needs the SDK and a keystore (see .github/workflows/release.yml).
set -e
cd "$(dirname "$0")/.."
VER=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
OUT=build/release
WANT=${*:-web windows linux macos android}
mkdir -p "$OUT"
touch build/.gdignore
godot --headless --path . --import >/dev/null 2>&1 || true

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
