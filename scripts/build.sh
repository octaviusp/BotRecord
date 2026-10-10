#!/bin/bash
# Builds out/Rec.app: release binary + Info.plist + bundled SVT-AV1/Opus dylibs + MLX's Metal library,
# signed with a stable identity so macOS keeps the Screen Recording permission across rebuilds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/out/Rec.app"
SIGN_IDENTITY="${REC_SIGN_IDENTITY:-Rec Local Signing}"
BREW_LIB="$(brew --prefix)/lib"
DYLIBS=(libSvtAv1Enc.4.dylib libopus.0.dylib)

# MLX kernels for live transcription. Command Line Tools can't compile Metal (no `xcrun metal`), so the
# base metallib comes prebuilt from the PyPI wheel of the exact MLX core vendored by mlx-swift.
MLX_CORE_VERSION="0.31.1"
MLX_WHEEL_URL="https://files.pythonhosted.org/packages/51/bc/987cb99e3aafb296aa11ce5133838a10eae8447edd53168d0804d4fb3a14/mlx_metal-0.31.1-py3-none-macosx_26_0_arm64.whl"
MLX_WHEEL_SHA256="e7324b7c56b519ae67c025d3ced07e5d35bc3a9f19d4c45fe4927f385148c59e"
METALLIB_SHA256="198488eb61359e953580a9c4530400feee1a06dd2f28a930a6ffa58aec66a597"
METALLIB_CACHE="$ROOT/.build/mlx-metal/mlx-$MLX_CORE_VERSION.metallib"

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# A metallib from another MLX version fails at runtime with missing or mismatched kernels.
check_mlx_core_version() {
    local header="$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/version.h"
    [[ -f "$header" ]] || { echo "error: $header not found; did 'swift build' resolve mlx-swift?" >&2; exit 1; }
    local resolved
    resolved="$(awk '/#define MLX_VERSION_(MAJOR|MINOR|PATCH) / {print $3}' "$header" | paste -sd. -)"
    if [[ "$resolved" != "$MLX_CORE_VERSION" ]]; then
        echo "error: mlx-swift vendors MLX core $resolved but this script bundles the $MLX_CORE_VERSION metallib." >&2
        echo "       Update MLX_CORE_VERSION, the wheel URL and both sha256 values in scripts/build.sh." >&2
        exit 1
    fi
}

# Downloads the wheel once and keeps only the verified metallib in .build/mlx-metal/.
fetch_metallib() {
    if [[ -f "$METALLIB_CACHE" && "$(sha256 "$METALLIB_CACHE")" == "$METALLIB_SHA256" ]]; then return; fi
    local dir wheel
    dir="$(dirname "$METALLIB_CACHE")"
    wheel="$dir/$(basename "$MLX_WHEEL_URL")"
    mkdir -p "$dir"
    echo "Downloading MLX $MLX_CORE_VERSION Metal library (49 MB, once)..."
    curl -fL --retry 3 --progress-bar -o "$wheel.part" "$MLX_WHEEL_URL"
    if [[ "$(sha256 "$wheel.part")" != "$MLX_WHEEL_SHA256" ]]; then
        rm -f "$wheel.part"
        echo "error: $(basename "$wheel") checksum mismatch" >&2; exit 1
    fi
    unzip -p "$wheel.part" mlx/lib/mlx.metallib > "$METALLIB_CACHE.part"
    rm -f "$wheel.part"
    if [[ "$(sha256 "$METALLIB_CACHE.part")" != "$METALLIB_SHA256" ]]; then
        rm -f "$METALLIB_CACHE.part"
        echo "error: mlx.metallib checksum mismatch" >&2; exit 1
    fi
    mv "$METALLIB_CACHE.part" "$METALLIB_CACHE"
}

cd "$ROOT"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Rec"
check_mlx_core_version
fetch_metallib

# Assemble in a fresh directory and swap it in: macOS may kill a signed binary overwritten in place.
STAGE="$ROOT/out/.Rec.app.staging"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Frameworks" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/Rec"
# Local symbols only help debuggers and crash symbolication; the dynamic symbol table stays, so the app still runs.
strip -x "$STAGE/Contents/MacOS/Rec"
cp "$ROOT/Resources/Info.plist" "$STAGE/Contents/Info.plist"
# MLX finds it under Bundle.main as SwiftPM would bundle it; no other dependency resource bundle is needed.
mkdir -p "$STAGE/Contents/Resources/mlx-swift_Cmlx.bundle"
cp "$METALLIB_CACHE" "$STAGE/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib"

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
