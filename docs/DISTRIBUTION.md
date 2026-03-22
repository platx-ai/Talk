# Talk Distribution & Packaging

## Overview

Talk has two distribution variants:
- **Talk-lite.dmg** (~50 MB) — App only, models downloaded on first launch
- **Talk-full.dmg** (~3 GB) — App + bundled models, works offline immediately

## Signing & Notarization

### Prerequisites
- Apple Developer Program membership (paid)
- Developer ID Application certificate
- Developer ID Installer certificate (for .pkg)

### Build & Sign

```bash
# Build Release
make build-release

# Sign the app
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: YOUR_NAME (TEAM_ID)" \
    --options runtime \
    --entitlements Talk/Talk.entitlements \
    path/to/Talk.app

# Verify
codesign --verify --deep --strict path/to/Talk.app
spctl --assess --verbose path/to/Talk.app
```

### Notarization

```bash
# Create ZIP for notarization
ditto -c -k --keepParent path/to/Talk.app Talk.zip

# Submit for notarization
xcrun notarytool submit Talk.zip \
    --apple-id "YOUR_APPLE_ID" \
    --team-id "TEAM_ID" \
    --password "APP_SPECIFIC_PASSWORD" \
    --wait

# Staple the ticket
xcrun stapler staple path/to/Talk.app
```

## DMG Creation

### Talk-lite.dmg (no models)

```bash
# Create DMG
hdiutil create -volname "Talk" \
    -srcfolder path/to/Talk.app \
    -ov -format UDZO \
    Talk-lite.dmg
```

### Talk-full.dmg (with models)

```bash
# Create staging directory
mkdir -p dmg-staging
cp -R path/to/Talk.app dmg-staging/

# Copy models into app bundle
TALK_ASR_MODEL_SOURCE_DIR=~/.cache/huggingface/hub/models--mlx-community--Qwen3-ASR-0.6B-4bit/snapshots/*/
TALK_LLM_MODEL_SOURCE_DIR=~/.cache/huggingface/hub/models--mlx-community--Qwen3-4B-Instruct-2507-4bit/snapshots/*/
# Run the bundle script with proper env vars
# ...

hdiutil create -volname "Talk" \
    -srcfolder dmg-staging \
    -ov -format UDZO \
    Talk-full.dmg
```

## Model Download Sources

### HuggingFace (International)
- ASR: `mlx-community/Qwen3-ASR-0.6B-4bit`
- LLM: `mlx-community/Qwen3-4B-Instruct-2507-4bit`

### ModelScope (China Mainland)
- ASR: TBD (need to verify availability)
- LLM: TBD (need to verify availability)

### Download source selection
- Auto-detect: try HuggingFace first, if blocked use ModelScope
- User can manually select in Settings or during onboarding
- Download progress shown in floating indicator

## Makefile Targets

```bash
make package-lite     # Build + sign + create Talk-lite.dmg
make package-full     # Build + sign + bundle models + create Talk-full.dmg
make notarize         # Submit for Apple notarization
```
