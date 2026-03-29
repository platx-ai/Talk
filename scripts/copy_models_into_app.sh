#!/bin/sh
set -eu

log() {
  echo "[bundle-models] $*"
}

warn() {
  echo "[bundle-models] warning: $*" >&2
}

fail() {
  echo "[bundle-models] error: $*" >&2
  exit 1
}

copy_dir() {
  src="$1"
  dst="$2"
  mkdir -p "$dst"
  rsync -a --inplace --delete "$src"/ "$dst"/
}

resolve_asr_source() {
  if [ -n "${TALK_ASR_MODEL_SOURCE_DIR:-}" ] && [ -f "${TALK_ASR_MODEL_SOURCE_DIR}/config.json" ]; then
    printf "%s" "${TALK_ASR_MODEL_SOURCE_DIR}"
    return 0
  fi

  default_dir="${SRCROOT}/../MLX/models/asr/mlx-community_Qwen3-ASR-0.6B-4bit"
  if [ -f "${default_dir}/config.json" ]; then
    printf "%s" "${default_dir}"
    return 0
  fi

  cache_root="${HOME}/.cache/huggingface/hub/models--mlx-community--Qwen3-ASR-0.6B-4bit/snapshots"
  if [ -d "$cache_root" ]; then
    match="$(find "$cache_root" -maxdepth 2 -type f -name config.json 2>/dev/null | head -n 1 || true)"
    if [ -n "$match" ]; then
      dirname "$match"
      return 0
    fi
  fi

  return 1
}

resolve_llm_source() {
  if [ -n "${TALK_LLM_MODEL_SOURCE_DIR:-}" ] && [ -f "${TALK_LLM_MODEL_SOURCE_DIR}/config.json" ]; then
    printf "%s" "${TALK_LLM_MODEL_SOURCE_DIR}"
    return 0
  fi

  default_dir="${SRCROOT}/../MLX/models/llm"
  if [ -f "${default_dir}/config.json" ]; then
    printf "%s" "${default_dir}"
    return 0
  fi

  return 1
}

resolve_vad_source() {
  if [ -n "${TALK_VAD_MODEL_SOURCE_DIR:-}" ] && [ -d "${TALK_VAD_MODEL_SOURCE_DIR}" ]; then
    printf "%s" "${TALK_VAD_MODEL_SOURCE_DIR}"
    return 0
  fi

  # Prefer current build's DerivedData checkout for determinism.
  if [ -n "${BUILD_DIR:-}" ]; then
    derived_root="$(cd "${BUILD_DIR}/../.." 2>/dev/null && pwd || true)"
    if [ -n "${derived_root}" ]; then
      candidate="${derived_root}/SourcePackages/checkouts/silero-vad-swift/Sources/SileroVAD/Resources/silero_vad.mlmodelc"
      if [ -d "${candidate}" ]; then
        printf "%s" "${candidate}"
        return 0
      fi
    fi
  fi

  # Fallback for local dev when using default Xcode DerivedData location.
  fallback="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -type d -name silero_vad.mlmodelc 2>/dev/null | head -n 1 || true)"
  if [ -n "${fallback}" ]; then
    printf "%s" "${fallback}"
    return 0
  fi

  return 1
}

require_models="${TALK_REQUIRE_BUNDLED_MODELS:-NO}"
resources_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
asr_dest_dir="${resources_dir}/mlx-audio/mlx-community_Qwen3-ASR-0.6B-4bit"
llm_dest_dir="${resources_dir}/Models/llm"
vad_dest_dir="${resources_dir}/silero_vad.mlmodelc"

asr_source="$(resolve_asr_source || true)"
llm_source="$(resolve_llm_source || true)"
vad_source="$(resolve_vad_source || true)"

if [ -n "$asr_source" ]; then
  log "Copying ASR model from: ${asr_source}"
  copy_dir "$asr_source" "$asr_dest_dir"
else
  warn "ASR model source not found. Set TALK_ASR_MODEL_SOURCE_DIR to a folder containing config.json"
fi

if [ -n "$llm_source" ]; then
  log "Copying LLM model from: ${llm_source}"
  copy_dir "$llm_source" "$llm_dest_dir"
else
  warn "LLM model source not found. Set TALK_LLM_MODEL_SOURCE_DIR to a folder containing config.json"
fi

if [ -n "$vad_source" ]; then
  log "Copying Silero VAD model from: ${vad_source}"
  copy_dir "$vad_source" "$vad_dest_dir"
else
  warn "Silero VAD model source not found. Set TALK_VAD_MODEL_SOURCE_DIR to a silero_vad.mlmodelc directory"
fi

has_asr="no"
has_llm="no"
has_vad="no"

if [ -f "${asr_dest_dir}/config.json" ]; then
  has_asr="yes"
fi

if [ -f "${llm_dest_dir}/config.json" ]; then
  has_llm="yes"
fi

if [ -d "${vad_dest_dir}" ]; then
  has_vad="yes"
fi

log "Bundle check: ASR=${has_asr}, LLM=${has_llm}, VAD=${has_vad}"

case "$require_models" in
  YES|yes|1|true|TRUE)
    [ "$has_asr" = "yes" ] || fail "ASR model missing in app bundle"
    [ "$has_llm" = "yes" ] || fail "LLM model missing in app bundle"
    [ "$has_vad" = "yes" ] || fail "Silero VAD model missing in app bundle"
    ;;
  *)
    ;;
esac
