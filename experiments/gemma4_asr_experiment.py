#!/usr/bin/env python3
"""
Gemma 4 ASR Experiment for Talk
================================
Evaluates Google Gemma 4 (2B) as an alternative ASR engine to Qwen3-ASR-0.6B.

Usage:
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_asr_experiment.py

Requirements:
    pip install mlx-vlm  (installed in conda base env)

Key Questions:
    1. How good is Gemma4's Chinese ASR quality?
    2. Does including hotwords in the prompt improve recognition?
    3. How does it handle audio > 30 seconds (750 token limit)?
    4. Memory footprint: 2B (~5GB) vs Qwen3 (~1.6GB) - acceptable?

Known Limitations (verified):
    - ~40ms/token, max 750 audio tokens => ~30s audio limit
    - Input: 128-bin mel spectrogram, 16kHz, Conformer encoder
    - Supports WAV, MP3, FLAC; M4A works after ffmpeg conversion to WAV
    - CRITICAL: Prompt must be formatted with apply_chat_template() including
      <|audio|> token, otherwise audio is silently ignored
    - Chinese output mixes simplified/traditional characters (繁简混排)
    - Proper nouns (Gemma4, Codex, AGENTS.md) are often misrecognized
    - Hotword prompts DEGRADE quality rather than improve it
    - 48s audio still partially works (truncated, not error)
    - English TTS: model "understands" content but paraphrases instead of transcribing
    - Peak memory reporting from mlx-vlm is unreliable (shows 0.01 GB)
"""

import json
import os
import sys
import time
import subprocess
import tempfile
from dataclasses import dataclass, field
from typing import Optional

# Fix: no_proxy contains IPv6 CIDR (::ffff:0:0:0:0/1) which httpx can't parse.
# Strip those entries before any httpx/huggingface_hub import.
for _key in ("no_proxy", "NO_PROXY"):
    _val = os.environ.get(_key, "")
    if _val:
        _cleaned = ", ".join(
            p.strip() for p in _val.split(",")
            if "::" not in p.strip()
        )
        os.environ[_key] = _cleaned

# ============================================================
# Configuration
# ============================================================

MODEL_ID = "google/gemma-4-e2b-it"
AUDIO_DIR = os.path.expanduser("~/Library/Application Support/Talk/audio/")
HISTORY_PATH = os.path.expanduser("~/Library/Application Support/Talk/history.json")
TEST_AUDIO_DIR = os.path.join(os.path.dirname(__file__), "..", "TalkTests", "TestAudio")
RESULTS_PATH = os.path.join(os.path.dirname(__file__), "gemma4_results.txt")

# Real recording samples (selected for diversity in duration)
REAL_SAMPLES = {
    # ~5s short Chinese
    "A1481388-5773-4DF4-8004-B7526EBC7DEE.m4a": {
        "duration": 4.8,
        "qwen3_raw": "问题和发现及时同步到对应的艺术。",
        "qwen3_polished": "问题和发现及时同步到对应的艺术。",
    },
    # ~9s medium Chinese
    "3EE1EB40-9B37-42BF-A947-F9B076E5A84B.m4a": {
        "duration": 9.1,
        "qwen3_raw": "这个进化不是特别成功。我觉得你在迭代三轮吧。",
        "qwen3_polished": "这个进化不是特别成功。我觉得你在迭代三轮吧。",
    },
    # ~10s with technical terms
    "61B4215E-2DAA-41C1-ACBD-E7B6F742EA5F.m4a": {
        "duration": 10.4,
        "qwen3_raw": "这些危险的模式到最后也需要默认情况下关闭。通过阿拉多的环境变量打开。",
        "qwen3_polished": "这些危险的模式到最后也需要默认情况下关闭。通过阿拉多的环境变量打开。",
    },
    # ~20s longer Chinese
    "F65A3E92-8E80-432F-BDBE-C207F7065BE8.m4a": {
        "duration": 20.7,
        "qwen3_raw": "你在深入分析和调研一下Codex的沙盒机制。目前我们给的Runtime有一些命令没法执行，然后你可以本地做一些实验。不要直接提交代码，你可以修改代码。",
        "qwen3_polished": "你在深入分析和调研一下Codex的沙盒机制。目前我们给的Runtime有一些命令没法执行，然后你可以本地做一些实验。不要直接提交代码，你可以修改代码。",
    },
    # ~30s boundary test
    "60D15531-2FE6-44A8-996A-04A413C85495.m4a": {
        "duration": 30.5,
        "qwen3_raw": "开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个T Mate去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四有一个三十秒大概的一个上限，所以其这个要做特殊的处理。",
        "qwen3_polished": "开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个T Mate去做实验，然后探索它的。用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四有一个三十秒大概的一个上限，所以其这个要做特殊的处理。",
    },
    # ~48s over-limit test
    "5CEEF1EE-40AB-4731-9264-7055D76C7C0E.m4a": {
        "duration": 47.7,
        "qwen3_raw": "但是用户，侧的项目是不需要自动去创建Agent Start MD的软链接。也就是说，当Cloud X的这个特性被打开的时候，我们可以自动执行的操作是：呃，与阿拉多相关的，我们维护的这些Cloud Start的...",
        "qwen3_polished": "",
    },
}

# TTS test audio files
TTS_SAMPLES = {
    "en_claude_code.wav": {
        "expected": "Claude Code is a command line tool for AI assisted coding",
        "language": "en",
    },
    "en_anthropic.wav": {
        "expected": "Anthropic is an AI safety company",
        "language": "en",
    },
    "en_technical.wav": {
        "expected": "The model uses metal GPU acceleration on Apple Silicon",
        "language": "en",
    },
    "zh_claude.wav": {
        "expected": "Claude是一个人工智能助手",
        "language": "zh",
    },
}

# Prompt variants for testing
PROMPTS = {
    "basic_en": "Transcribe this audio.",
    "basic_zh": "请转录这段音频。",
    "detailed_en": "Transcribe this audio accurately. Output only the transcription, no commentary.",
    "detailed_zh": "请准确转录这段音频的内容。只输出转录文本，不要添加任何解释。",
    "hotword_talk": (
        "Transcribe this audio. The following terms may appear: "
        "Claude Code, Claude Agent SDK, Codex, 飞书, Anthropic, 阿拉多, duoduo"
    ),
    "hotword_talk_zh": (
        "请转录这段音频。可能出现的专有词汇包括："
        "Claude Code, Claude Agent SDK, Codex, 飞书, Anthropic, 阿拉多, duoduo"
    ),
}


# ============================================================
# Utilities
# ============================================================

@dataclass
class TranscriptionResult:
    audio_file: str
    prompt_name: str
    prompt_text: str
    transcription: str
    latency_s: float
    prompt_tokens: int
    generation_tokens: int
    peak_memory_gb: float
    error: Optional[str] = None


def convert_m4a_to_wav(m4a_path: str) -> str:
    """Convert M4A/AAC to 16kHz WAV using ffmpeg."""
    wav_path = tempfile.mktemp(suffix=".wav")
    cmd = [
        "ffmpeg", "-y", "-i", m4a_path,
        "-ar", "16000", "-ac", "1", "-f", "wav",
        wav_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg conversion failed: {result.stderr[:200]}")
    return wav_path


def get_audio_duration(path: str) -> float:
    """Get audio duration in seconds using ffprobe."""
    cmd = ["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
           "-of", "default=noprint_wrappers=1:nokey=1", path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return float(result.stdout.strip())


results: list[TranscriptionResult] = []
report_lines: list[str] = []


def log(msg: str):
    print(msg)
    report_lines.append(msg)


def log_separator():
    log("=" * 72)


# ============================================================
# Model Loading
# ============================================================

def load_model():
    """Load Gemma 4 2B model via mlx-vlm."""
    log(f"\nLoading model: {MODEL_ID}")
    log("This may take a while on first run (downloading ~5GB)...")

    t0 = time.time()
    from mlx_vlm.utils import load
    model, processor = load(MODEL_ID)
    load_time = time.time() - t0

    log(f"Model loaded in {load_time:.1f}s")
    return model, processor


# ============================================================
# Transcription
# ============================================================

def format_prompt(processor, model_config, prompt_text: str) -> str:
    """Format prompt using Gemma 4's chat template with <|audio|> token."""
    from mlx_vlm.prompt_utils import apply_chat_template
    return apply_chat_template(
        processor,
        model_config,
        prompt_text,
        num_audios=1,
    )


def transcribe(model, processor, audio_path: str, prompt_name: str, prompt_text: str,
               max_tokens: int = 2048) -> TranscriptionResult:
    """Run a single transcription and measure performance."""
    from mlx_vlm import generate

    # Format the prompt with chat template (adds <|audio|> token)
    formatted_prompt = format_prompt(processor, model.config, prompt_text)

    # Convert M4A to WAV if needed
    converted = False
    actual_path = audio_path
    if audio_path.endswith(('.m4a', '.aac', '.mp4')):
        try:
            actual_path = convert_m4a_to_wav(audio_path)
            converted = True
        except Exception as e:
            return TranscriptionResult(
                audio_file=os.path.basename(audio_path),
                prompt_name=prompt_name,
                prompt_text=prompt_text,
                transcription="",
                latency_s=0,
                prompt_tokens=0,
                generation_tokens=0,
                peak_memory_gb=0,
                error=f"Conversion failed: {e}",
            )

    try:
        t0 = time.time()
        result = generate(
            model,
            processor,
            prompt=formatted_prompt,
            audio=actual_path,
            max_tokens=max_tokens,
            temperature=0.0,
            verbose=False,
        )
        latency = time.time() - t0

        return TranscriptionResult(
            audio_file=os.path.basename(audio_path),
            prompt_name=prompt_name,
            prompt_text=prompt_text,
            transcription=result.text.strip(),
            latency_s=latency,
            prompt_tokens=result.prompt_tokens,
            generation_tokens=result.generation_tokens,
            peak_memory_gb=result.peak_memory / 1024,  # MB to GB
        )
    except Exception as e:
        import traceback
        return TranscriptionResult(
            audio_file=os.path.basename(audio_path),
            prompt_name=prompt_name,
            prompt_text=prompt_text,
            transcription="",
            latency_s=time.time() - t0,
            prompt_tokens=0,
            generation_tokens=0,
            peak_memory_gb=0,
            error=f"{type(e).__name__}: {e}\n{traceback.format_exc()[-500:]}",
        )
    finally:
        if converted and os.path.exists(actual_path):
            os.unlink(actual_path)


# ============================================================
# Experiments
# ============================================================

def experiment_tts_baseline(model, processor):
    """Experiment A: TTS test audio - basic transcription capability."""
    log_separator()
    log("EXPERIMENT A: TTS Test Audio Baseline")
    log_separator()

    for filename, info in TTS_SAMPLES.items():
        audio_path = os.path.join(TEST_AUDIO_DIR, filename)
        if not os.path.exists(audio_path):
            log(f"  SKIP: {filename} not found")
            continue

        prompt = PROMPTS["basic_en"] if info["language"] == "en" else PROMPTS["basic_zh"]
        r = transcribe(model, processor, audio_path, "basic", prompt)
        results.append(r)

        log(f"\n  File: {filename} ({info['language']})")
        log(f"  Expected:     {info['expected']}")
        log(f"  Gemma4:       {r.transcription}")
        if r.error:
            log(f"  ERROR:        {r.error}")
        log(f"  Latency:      {r.latency_s:.2f}s")
        log(f"  Tokens:       prompt={r.prompt_tokens}, gen={r.generation_tokens}")
        log(f"  Peak Memory:  {r.peak_memory_gb:.2f} GB")


def experiment_real_recordings(model, processor):
    """Experiment B: Real recordings from Talk history."""
    log_separator()
    log("EXPERIMENT B: Real Recordings (M4A)")
    log_separator()

    for filename, info in REAL_SAMPLES.items():
        audio_path = os.path.join(AUDIO_DIR, filename)
        if not os.path.exists(audio_path):
            log(f"  SKIP: {filename} not found")
            continue

        prompt = PROMPTS["detailed_zh"]
        r = transcribe(model, processor, audio_path, "detailed_zh", prompt)
        results.append(r)

        log(f"\n  File: {filename} ({info['duration']:.1f}s)")
        log(f"  Qwen3 raw:    {info['qwen3_raw'][:100]}")
        log(f"  Gemma4:       {r.transcription[:100]}")
        if r.error:
            log(f"  ERROR:        {r.error[:200]}")
        log(f"  Latency:      {r.latency_s:.2f}s")
        log(f"  Tokens:       prompt={r.prompt_tokens}, gen={r.generation_tokens}")
        log(f"  Peak Memory:  {r.peak_memory_gb:.2f} GB")


def experiment_prompt_impact(model, processor):
    """Experiment C: Test how different prompts affect transcription."""
    log_separator()
    log("EXPERIMENT C: Prompt Impact on Transcription")
    log_separator()

    # Use the 10s technical term sample
    test_file = "61B4215E-2DAA-41C1-ACBD-E7B6F742EA5F.m4a"
    audio_path = os.path.join(AUDIO_DIR, test_file)
    if not os.path.exists(audio_path):
        log(f"  SKIP: {test_file} not found")
        return

    info = REAL_SAMPLES[test_file]
    log(f"\n  Test file: {test_file} ({info['duration']:.1f}s)")
    log(f"  Qwen3 baseline: {info['qwen3_raw']}")

    for prompt_name, prompt_text in PROMPTS.items():
        r = transcribe(model, processor, audio_path, prompt_name, prompt_text)
        results.append(r)

        log(f"\n  Prompt [{prompt_name}]: {prompt_text[:60]}...")
        log(f"  Result:       {r.transcription[:100]}")
        if r.error:
            log(f"  ERROR:        {r.error[:200]}")
        log(f"  Latency:      {r.latency_s:.2f}s")


def experiment_duration_boundary(model, processor):
    """Experiment D: Test 30-second boundary behavior."""
    log_separator()
    log("EXPERIMENT D: Duration Boundary (30s limit)")
    log_separator()

    boundary_files = [
        ("F65A3E92-8E80-432F-BDBE-C207F7065BE8.m4a", "~21s - under limit"),
        ("60D15531-2FE6-44A8-996A-04A413C85495.m4a", "~30s - at boundary"),
        ("5CEEF1EE-40AB-4731-9264-7055D76C7C0E.m4a", "~48s - over limit"),
    ]

    prompt = PROMPTS["detailed_zh"]

    for filename, desc in boundary_files:
        audio_path = os.path.join(AUDIO_DIR, filename)
        if not os.path.exists(audio_path):
            log(f"  SKIP: {filename} not found")
            continue

        info = REAL_SAMPLES.get(filename, {})

        r = transcribe(model, processor, audio_path, "boundary_test", prompt)
        results.append(r)

        log(f"\n  File: {filename} ({desc})")
        log(f"  Qwen3 raw:    {info.get('qwen3_raw', 'N/A')[:100]}")
        log(f"  Gemma4:       {r.transcription[:150]}")
        if r.error:
            log(f"  ERROR:        {r.error[:200]}")
        log(f"  Latency:      {r.latency_s:.2f}s")
        log(f"  Tokens:       prompt={r.prompt_tokens}, gen={r.generation_tokens}")


# ============================================================
# Report Generation
# ============================================================

def generate_report():
    """Generate final comparison report."""
    log_separator()
    log("SUMMARY REPORT")
    log_separator()

    # Latency statistics
    valid = [r for r in results if r.error is None]
    if valid:
        avg_latency = sum(r.latency_s for r in valid) / len(valid)
        max_latency = max(r.latency_s for r in valid)
        min_latency = min(r.latency_s for r in valid)
        avg_memory = sum(r.peak_memory_gb for r in valid) / len(valid)

        log(f"\n  Total runs:     {len(results)} ({len(valid)} successful, {len(results)-len(valid)} failed)")
        log(f"  Avg latency:    {avg_latency:.2f}s")
        log(f"  Min latency:    {min_latency:.2f}s")
        log(f"  Max latency:    {max_latency:.2f}s")
        log(f"  Avg peak mem:   {avg_memory:.2f} GB")

    # Error summary
    errors = [r for r in results if r.error is not None]
    if errors:
        log(f"\n  Errors ({len(errors)}):")
        for r in errors:
            log(f"    {r.audio_file} [{r.prompt_name}]: {r.error[:100]}")

    log("\n  Comparison: Gemma4 2B vs Qwen3-ASR-0.6B")
    log("  +-----------------+------------------+------------------+")
    log("  | Metric          | Gemma4 2B        | Qwen3-ASR 0.6B   |")
    log("  +-----------------+------------------+------------------+")
    log(f"  | Model Size      | ~5 GB            | ~1.6 GB          |")
    if valid:
        log(f"  | Avg Latency     | {avg_latency:.2f}s            | ~2-4s (typical)  |")
        log(f"  | Peak Memory     | {avg_memory:.2f} GB          | ~2 GB            |")
    log(f"  | Audio Limit     | ~30s             | unlimited        |")
    log(f"  | Chinese Quality | (see results)    | good             |")
    log(f"  | Hotword Support | via prompt       | system prompt    |")
    log("  +-----------------+------------------+------------------+")

    # Write report
    with open(RESULTS_PATH, "w") as f:
        f.write("\n".join(report_lines))
    log(f"\nFull report saved to: {RESULTS_PATH}")


# ============================================================
# Main
# ============================================================

def main():
    log("=" * 72)
    log("Gemma 4 ASR Experiment for Talk")
    log(f"Model: {MODEL_ID}")
    log(f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    log("=" * 72)

    # Check prerequisites
    if not os.path.exists(AUDIO_DIR):
        log(f"WARNING: Audio directory not found: {AUDIO_DIR}")
    if not os.path.exists(TEST_AUDIO_DIR):
        log(f"WARNING: Test audio directory not found: {TEST_AUDIO_DIR}")

    # Check ffmpeg
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        log("ERROR: ffmpeg not found. Required for M4A conversion.")
        sys.exit(1)

    # Load model
    model, processor = load_model()

    # Run experiments
    experiment_tts_baseline(model, processor)
    experiment_real_recordings(model, processor)
    experiment_prompt_impact(model, processor)
    experiment_duration_boundary(model, processor)

    # Generate report
    generate_report()


if __name__ == "__main__":
    main()
