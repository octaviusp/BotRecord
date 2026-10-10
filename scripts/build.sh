#!/bin/bash
# Builds out/Rec.app: release binary + Info.plist + bundled SVT-AV1/Opus dylibs, signed with a
# stable identity so macOS keeps the Screen Recording permission across rebuilds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/out/Rec.app"
SIGN_IDENTITY="${REC_SIGN_IDENTITY:-Rec Local Signing}"
BREW_LIB="$(brew --prefix)/lib"
DYLIBS=(libSvtAv1Enc.4.dylib libopus.0.dylib)

cd "$ROOT"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Rec"

# Assemble in a fresh directory and swap it in: macOS may kill a signed binary overwritten in place.
STAGE="$ROOT/out/.Rec.app.staging"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Frameworks" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/Rec"
cp "$ROOT/Resources/Info.plist" "$STAGE/Contents/Info.plist"

for lib in "${DYLIBS[@]}"; do
    cp "$BREW_LIB/$lib" "$STAGE/Contents/Frameworks/$lib"
    chmod u+w "$STAGE/Contents/Frameworks/$lib"
    install_name_tool -id "@rpath/$lib" "$STAGE/Contents/Frameworks/$lib"
    # The binary links the Homebrew path; point it at the bundled copy.
    linked="$(otool -L "$STAGE/Contents/MacOS/Rec" | awk -v l="$lib" '$1 ~ l {print $1}')"
    if [[ -n "$linked" ]]; then
        install_name_tool -change "$linked" "@rpath/$lib" "$STAGE/Contents/MacOS/Rec"
    fi
done

if ! security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    echo "Signing identity '$SIGN_IDENTITY' not found; falling back to ad-hoc (permission resets each build)." >&2
    SIGN_IDENTITY="-"
fi
for lib in "${DYLIBS[@]}"; do
    codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$STAGE/Contents/Frameworks/$lib"
done
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$STAGE"

rm -rf "$APP"
mv "$STAGE" "$APP"
echo "Built $APP"
