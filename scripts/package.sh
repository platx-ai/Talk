#!/bin/bash
set -euo pipefail

# Talk packaging script — creates signed DMG for distribution
# Usage:
#   ./scripts/package.sh lite    # App only (~50 MB)
#   ./scripts/package.sh full    # App + bundled models (~3 GB)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/dist"
APP_NAME="Talk"
SCHEME="Talk"
PROJECT="${PROJECT_DIR}/Talk.xcodeproj"

# Signing config — set via environment variables, NOT committed to repo
# TALK_TEAM_ID: Apple Developer Team ID (e.g., "7A8HPDPNNX")
# TALK_SIGN_IDENTITY: (optional) specific signing identity
SIGN_IDENTITY="${TALK_SIGN_IDENTITY:-}"
TEAM_ID="${TALK_TEAM_ID:-}"

if [ -z "$TEAM_ID" ]; then
    # Try to read from pbxproj (set by Xcode UI)
    TEAM_ID=$(grep 'DEVELOPMENT_TEAM = [A-Z0-9]' "${PROJECT_DIR}/Talk.xcodeproj/project.pbxproj" | head -1 | sed 's/.*= \([A-Z0-9]*\).*/\1/' || true)
fi

log() { echo "[package] $*"; }
warn() { echo "[package] WARNING: $*" >&2; }
fail() { echo "[package] ERROR: $*" >&2; exit 1; }

# Auto-detect signing identity if not set
detect_signing() {
    if [ -z "$SIGN_IDENTITY" ]; then
        SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
    fi

    if [ -z "$SIGN_IDENTITY" ]; then
        # Fall back to any valid identity
        SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep -v "0 valid" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
    fi

    if [ -z "$SIGN_IDENTITY" ]; then
        warn "No signing identity found. Building with ad-hoc signing."
        SIGN_IDENTITY="-"
    else
        log "Using signing identity: ${SIGN_IDENTITY}"
    fi
}

# Build Release
build_app() {
    log "Building Release..."
    mkdir -p "$BUILD_DIR"

    if [ -n "$TEAM_ID" ]; then
        # Signed build with automatic signing
        xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
            -configuration Release \
            -derivedDataPath "${BUILD_DIR}/DerivedData" \
            DEVELOPMENT_TEAM="${TEAM_ID}" \
            build 2>&1 | tail -5
    else
        # Ad-hoc unsigned build
        xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
            -configuration Release \
            -derivedDataPath "${BUILD_DIR}/DerivedData" \
            CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
            build 2>&1 | tail -5
    fi

    APP_PATH="${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"
    if [ ! -d "$APP_PATH" ]; then
        fail "Build failed: ${APP_PATH} not found"
    fi
    log "Build complete: ${APP_PATH}"
}

# Sign the app (if not ad-hoc)
sign_app() {
    if [ "$SIGN_IDENTITY" = "-" ]; then
        log "Skipping signing (ad-hoc mode)"
        return
    fi

    log "Signing app with: ${SIGN_IDENTITY}"

    # Try with timestamp first, fall back to no timestamp if service unavailable
    if ! codesign --deep --force --verify --verbose \
        --sign "$SIGN_IDENTITY" \
        --options runtime \
        --entitlements "${PROJECT_DIR}/Talk/Talk.entitlements" \
        "$APP_PATH" 2>&1; then

        warn "Timestamp service unavailable, signing without timestamp..."
        codesign --deep --force --verify --verbose \
            --sign "$SIGN_IDENTITY" \
            --options runtime \
            --timestamp=none \
            --entitlements "${PROJECT_DIR}/Talk/Talk.entitlements" \
            "$APP_PATH"
    fi

    log "Verifying signature..."
    codesign --verify --deep --strict "$APP_PATH"
    log "Signature valid"
}

# Bundle models into app (for full variant)
bundle_models() {
    log "Bundling models..."

    local resources_dir="${APP_PATH}/Contents/Resources"

    # ASR model
    local asr_cache="${HOME}/.cache/huggingface/hub/models--mlx-community--Qwen3-ASR-0.6B-4bit/snapshots"
    local asr_source=$(find "$asr_cache" -maxdepth 2 -name "config.json" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
    if [ -n "$asr_source" ]; then
        local asr_dest="${resources_dir}/mlx-audio/mlx-community_Qwen3-ASR-0.6B-4bit"
        mkdir -p "$asr_dest"
        rsync -aL --inplace "$asr_source"/ "$asr_dest"/
        log "ASR model bundled from: ${asr_source}"
    else
        warn "ASR model not found in HuggingFace cache. Run 'make download-models' first."
    fi

    # LLM model
    local llm_cache="${HOME}/.cache/huggingface/hub/models--mlx-community--Qwen3-4B-Instruct-2507-4bit/snapshots"
    local llm_source=$(find "$llm_cache" -maxdepth 2 -name "config.json" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
    if [ -n "$llm_source" ]; then
        local llm_dest="${resources_dir}/Models/llm"
        mkdir -p "$llm_dest"
        rsync -aL --inplace "$llm_source"/ "$llm_dest"/
        log "LLM model bundled from: ${llm_source}"
    else
        warn "LLM model not found in HuggingFace cache. Run 'make download-models' first."
    fi
}

# Create DMG
create_dmg() {
    local variant="$1"
    local dmg_name="${APP_NAME}-${variant}.dmg"
    local dmg_path="${BUILD_DIR}/${dmg_name}"

    log "Creating ${dmg_name}..."

    rm -f "$dmg_path"

    # Stage DMG contents: app + Applications symlink
    local staging="${BUILD_DIR}/dmg-staging"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp -R "$APP_PATH" "$staging/"
    ln -s /Applications "$staging/Applications"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$staging" \
        -ov -format UDZO \
        "$dmg_path"

    rm -rf "$staging"

    local size=$(du -sh "$dmg_path" | cut -f1)
    log "Created: ${dmg_path} (${size})"
}

# Notarize DMG
notarize_dmg() {
    local dmg_path="$1"
    local profile="${TALK_NOTARIZE_PROFILE:-talk-notarize}"

    if ! xcrun notarytool --help >/dev/null 2>&1; then
        warn "notarytool not available, skipping notarization"
        return
    fi

    log "Submitting for Apple notarization..."
    if xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$profile" \
        --wait 2>&1; then

        log "Notarization accepted. Stapling ticket..."
        xcrun stapler staple "$dmg_path"
        log "Stapled successfully"
    else
        warn "Notarization failed. DMG is signed but not notarized."
        warn "Users will see Gatekeeper warnings on first open."
    fi
}

# Main
MODE="${1:-lite}"

log "=== Talk Packaging (${MODE}) ==="
detect_signing
build_app

case "$MODE" in
    lite)
        sign_app
        create_dmg "lite"
        [ "$SIGN_IDENTITY" != "-" ] && notarize_dmg "${BUILD_DIR}/Talk-lite.dmg"
        ;;
    full)
        bundle_models
        sign_app
        create_dmg "full"
        [ "$SIGN_IDENTITY" != "-" ] && notarize_dmg "${BUILD_DIR}/Talk-full.dmg"
        ;;
    *)
        fail "Unknown mode: ${MODE}. Use 'lite' or 'full'."
        ;;
esac

log "=== Done ==="
ls -lh "${BUILD_DIR}"/*.dmg 2>/dev/null
