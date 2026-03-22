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

# Read signing identity from environment or try to auto-detect
SIGN_IDENTITY="${TALK_SIGN_IDENTITY:-}"
TEAM_ID="${TALK_TEAM_ID:-}"

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

    local sign_flags=""
    if [ "$SIGN_IDENTITY" = "-" ]; then
        sign_flags="CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
    else
        sign_flags="CODE_SIGN_IDENTITY=${SIGN_IDENTITY}"
        if [ -n "$TEAM_ID" ]; then
            sign_flags="${sign_flags} DEVELOPMENT_TEAM=${TEAM_ID}"
        fi
    fi

    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        ${sign_flags} \
        build 2>&1 | tail -5

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

    log "Signing app..."
    codesign --deep --force --verify --verbose \
        --sign "$SIGN_IDENTITY" \
        --options runtime \
        --entitlements "${PROJECT_DIR}/Talk/Talk.entitlements" \
        "$APP_PATH"

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

    # Remove old DMG
    rm -f "$dmg_path"

    # Create DMG with app
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP_PATH" \
        -ov -format UDZO \
        "$dmg_path"

    local size=$(du -sh "$dmg_path" | cut -f1)
    log "Created: ${dmg_path} (${size})"
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
        ;;
    full)
        bundle_models
        sign_app
        create_dmg "full"
        ;;
    *)
        fail "Unknown mode: ${MODE}. Use 'lite' or 'full'."
        ;;
esac

log "=== Done ==="
ls -lh "${BUILD_DIR}"/*.dmg 2>/dev/null
