#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Packages the built app as a renamed copy to give someone outside the
# official releases: its own name and icon, no update checks (an official
# update would replace it with a different app), and, if given, the settings
# it starts from on its first launch, as a backup from Settings → Advanced or
# `--export-settings` writes them. Writes dist/<Name>.app and
# dist/<Name>-<version>.dmg. Run ./build.sh first.
#
#   Tools/make-edition.sh NAME ICON.png CLASSIC-ICON.png [SETTINGS.plist]
#
# ICON.png is a 1024-pixel square the system rounds into the icon's shape;
# CLASSIC-ICON.png is the same art already rounded, with the usual margin,
# for macOS versions before adaptive icons.
set -euo pipefail
cd "$(dirname "$0")/.."

if (( $# < 3 )); then
    echo "usage: Tools/make-edition.sh NAME ICON.png CLASSIC-ICON.png [SETTINGS.plist]" >&2
    exit 2
fi
NAME="$1"
ICON="$2"
CLASSIC="$3"
SETTINGS="${4:-}"
SOURCE="build/stage/Vorssaint.app"
if [[ ! -d "$SOURCE" ]]; then
    echo "✗ $SOURCE not found — run ./build.sh first" >&2
    exit 1
fi
for file in "$ICON" "$CLASSIC" ${SETTINGS:+"$SETTINGS"}; do
    [[ -f "$file" ]] || { echo "✗ $file not found" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$NAME.app"
ditto "$SOURCE" "$APP"
xattr -cr "$APP"
PLIST="$APP/Contents/Info.plist"
RESOURCES="$APP/Contents/Resources"

echo "▸ Naming it $NAME…"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :VorssaintUpdatesDisabled" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :VorssaintUpdatesDisabled bool true" "$PLIST"

echo "▸ Drawing its icon…"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$CLASSIC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$CLASSIC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

# The adaptive icon macOS 26 draws: the square art as one flat layer.
ACTOOL_BIN="$(xcrun --find actool 2>/dev/null || true)"
COMPILED=0
if [[ -n "$ACTOOL_BIN" ]]; then
    PACKAGE="$WORK/AppIcon.icon"
    mkdir -p "$PACKAGE/Assets" "$WORK/catalog"
    cp "$ICON" "$PACKAGE/Assets/artwork.png"
    cat > "$PACKAGE/icon.json" <<'JSON'
{
  "fill" : "automatic",
  "groups" : [
    {
      "layers" : [
        {
          "glass" : false,
          "hidden" : false,
          "image-name" : "artwork.png",
          "name" : "artwork",
          "position" : { "scale" : 1, "translation-in-points" : [0, 0] }
        }
      ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "specular" : false,
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
JSON
    if "$ACTOOL_BIN" "$PACKAGE" --compile "$WORK/catalog" --app-icon AppIcon --platform macosx \
            --target-device mac --minimum-deployment-target 14.0 --enable-on-demand-resources NO \
            --output-partial-info-plist "$WORK/partial-info.plist" >"$WORK/actool.log" 2>&1 \
            && [[ -s "$WORK/catalog/Assets.car" ]]; then
        cp "$WORK/catalog/Assets.car" "$RESOURCES/Assets.car"
        COMPILED=1
    fi
fi
if (( ! COMPILED )); then
    # Without its own adaptive icon, the classic one is drawn everywhere.
    rm -f "$RESOURCES/Assets.car"
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
    echo "  adaptive icon skipped; the classic icon is used"
fi

if [[ -n "$SETTINGS" ]]; then
    echo "▸ Packing the settings it starts from…"
    cp "$SETTINGS" "$RESOURCES/EditionSettings.plist"
    chmod 644 "$RESOURCES/EditionSettings.plist"
fi

echo "▸ Signing…"
IDENTITY="$(codesign -dvv "$SOURCE" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
codesign --force --strip-disallowed-xattrs --preserve-metadata=entitlements,requirements,flags \
    --sign "${IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
mkdir -p dist
rm -rf "dist/$NAME.app"
ditto "$APP" "dist/$NAME.app"

echo "▸ Making the disk image…"
FOLDER="$WORK/disk"
mkdir -p "$FOLDER"
ditto "$APP" "$FOLDER/$NAME.app"
ln -s /Applications "$FOLDER/Applications"
OUT="dist/$NAME-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -quiet -volname "$NAME" -srcfolder "$FOLDER" -fs HFS+ -format UDZO "$OUT"
echo "✓ $OUT"
