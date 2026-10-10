#!/bin/bash
# Packages a BotRecord release: builds the app ad-hoc signed, zips it, gathers the pinned speech-model files
# and their license into dist/, and writes release.json (committed) with every asset's size and sha256.
# Upload the files in dist/ to the GitHub release "v<version>"; ./install downloads them from there.
#
# Usage: scripts/release.sh <version>            e.g. scripts/release.sh 0.1.0
# Model files come from BOTRECORD_MODEL_DIR, else BotRecord's installed model folder, else Hugging Face.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"

# Must match TranscriptionModelManifest.nemotron (checked below so the two can't drift apart).
MODEL_REPO="aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit"
MODEL_REVISION="5339193d26b1eda4461358c6210f5039e97af213"
MODEL_DIR_NAME="nemotron-0.6b-int8-5339193"
MODEL_FILES=(config.json vocab.json languages.json model.safetensors)
MODEL_SHA256=(
    284d6b51bd2b5a5717ae34caff2ff362535790a853992cd2e06996230699f649
    f7218f3ae2c5baf002974a7babf50ee1f719732fb1f349eeefb86b62219dc0cd
    a1efe863e1057d4658bce8175c978020ac35a63a3c9a65ae899f324a32c8e4f6
    4d7598b934dc106dd648b0299cbb7795c5641761bb158abde9d20558808f8050
)
MODEL_LICENSE="LICENSE-OpenMDW-1.1.txt"
MANIFEST_SWIFT="$ROOT/Sources/BotRecord/Transcription/Model/TranscriptionModelManifest.swift"

die() { echo "error: $*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
file_size() { stat -f %z "$1"; }

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh <version>  (e.g. 0.1.0)"

check_manifest_matches_app() {
    grep -q "\"$MODEL_REVISION\"" "$MANIFEST_SWIFT" || die "model revision differs from $MANIFEST_SWIFT"
    grep -q "\"$MODEL_DIR_NAME\"" "$MANIFEST_SWIFT" || die "model folder name differs from $MANIFEST_SWIFT"
    for hash in "${MODEL_SHA256[@]}"; do
        grep -q "$hash" "$MANIFEST_SWIFT" || die "model checksum $hash not in $MANIFEST_SWIFT"
    done
}

# Copies (or downloads) each model file into dist/ and verifies it against the pinned checksum.
gather_model() {
    local source="${BOTRECORD_MODEL_DIR:-$HOME/Library/Application Support/com.octaviusp.botrecord/models/$MODEL_DIR_NAME}"
    local i name target
    for i in "${!MODEL_FILES[@]}"; do
        name="${MODEL_FILES[$i]}"
        target="$DIST/$name"
        if [[ -f "$source/$name" ]]; then
            cp "$source/$name" "$target"
        else
            echo "Downloading $name from Hugging Face ($MODEL_REPO@${MODEL_REVISION:0:7})..."
            curl -fL --retry 3 --progress-bar -o "$target" \
                "https://huggingface.co/$MODEL_REPO/resolve/$MODEL_REVISION/$name"
        fi
        [[ "$(sha256 "$target")" == "${MODEL_SHA256[$i]}" ]] || die "$name checksum mismatch (source: $source)"
    done
    cp "$ROOT/licenses/$MODEL_LICENSE" "$DIST/$MODEL_LICENSE"
}

asset_json() {
    local name="$1" kind="$2"
    printf '    {"name": "%s", "sha256": "%s", "size": %s, "kind": "%s"}' \
        "$name" "$(sha256 "$DIST/$name")" "$(file_size "$DIST/$name")" "$kind"
}

write_release_json() {
    local app_zip="$1" entries=() name
    entries+=("$(asset_json "$app_zip" app)")
    for name in "${MODEL_FILES[@]}"; do entries+=("$(asset_json "$name" model)"); done
    entries+=("$(asset_json "$MODEL_LICENSE" license)")
    {
        printf '{\n'
        printf '  "version": "%s",\n  "minimumMacOS": "26.0",\n  "arch": "arm64",\n' "$VERSION"
        printf '  "assets": [\n'
        local last=$((${#entries[@]} - 1)) i
        for i in "${!entries[@]}"; do
            printf '%s%s\n' "${entries[$i]}" "$([[ $i -lt $last ]] && echo ,)"
        done
        printf '  ],\n'
        printf '  "model": {"id": "%s", "revision": "%s", "installDirName": "%s"}\n' \
            "$MODEL_REPO" "$MODEL_REVISION" "$MODEL_DIR_NAME"
        printf '}\n'
    } > "$ROOT/release.json.part"
    plutil -convert xml1 -o /dev/null "$ROOT/release.json.part" || die "generated release.json is not valid JSON"
    mv "$ROOT/release.json.part" "$ROOT/release.json"
}

check_manifest_matches_app
rm -rf "$DIST"
mkdir -p "$DIST"

# Ad-hoc signing runs on any Apple Silicon Mac; curl/git downloads carry no quarantine flag for Gatekeeper.
BOTRECORD_SIGN_IDENTITY="-" BOTRECORD_VERSION="$VERSION" "$ROOT/scripts/build.sh"
APP_ZIP="BotRecord-$VERSION-arm64.zip"
ditto -c -k --keepParent "$ROOT/out/BotRecord.app" "$DIST/$APP_ZIP"

gather_model
write_release_json "$APP_ZIP"

echo
echo "Release $VERSION ready:"
ls -l "$DIST"
echo
echo "Next: commit release.json, then create the GitHub release v$VERSION with every file in dist/ attached."
