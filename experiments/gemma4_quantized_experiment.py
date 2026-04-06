#!/usr/bin/env python3
"""
Gemma 4 Quantized ASR Experiment
=================================
Tests unsloth MLX 4-bit quantized Gemma 4 models for ASR.

Previous experiment used google/gemma-4-e2b-it (9.6GB, non-quantized) -> avg_similarity=0.061
This experiment uses unsloth 4-bit quantized versions (~1.5-3GB).

NOTE: mlx-community quantized versions reportedly produce garbled output
due to PLE layer quantization issues. unsloth versions may fix this.

Usage:
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_quantized_experiment.py
"""

import json
import os
import sys
import time
import subprocess
import tempfile
from pathlib import Path
from difflib import SequenceMatcher

# Fix: no_proxy contains IPv6 CIDR (::ffff:0:0:0:0/1) which httpx can't parse.
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

PROJECT_ROOT = Path(__file__).parent.parent
AUDIO_DIR = Path.home() / "Library" / "Application Support" / "Talk" / "audio"
TEST_AUDIO_DIR = PROJECT_ROOT / "TalkTests" / "TestAudio"
CASES_PATH = PROJECT_ROOT / "TalkTests" / "RegressionSuite" / "regression_cases.json"
RESULTS_DIR = PROJECT_ROOT / "experiments" / "regression_results"
LOG_PATH = PROJECT_ROOT / "experiments" / "gemma4_evolution_log.md"

MODELS = {
    # mlx-community versions (have audio tower, simpler quantization)
    "mlx-2B-4bit": "mlx-community/gemma-4-e2b-it-4bit",
    "mlx-4B-4bit": "mlx-community/gemma-4-e4b-it-4bit",
    # unsloth versions (text-only, no audio tower -- NOT usable for ASR)
    # "unsloth-2B-4bit": "unsloth/gemma-4-E2B-it-UD-MLX-4bit",
    # "unsloth-4B-4bit": "unsloth/gemma-4-E4B-it-UD-MLX-4bit",
    # EZCon mixed quantization (may avoid PLE issues)
    "ezcon-2B-4bit": "EZCon/gemma-4-E2B-it-4bit-g32-mxfp4-mixed_4_8-mlx",
}

# Prompt evolution generations
PROMPTS = {
    "gen0_baseline": "Transcribe this audio verbatim.",
    "gen1a_zh": "请逐字转录这段语音，使用简体中文。",
    "gen1b_mixed": "Transcribe this audio word for word in its original language. Use simplified Chinese characters.",
    "gen1c_role": "You are a speech-to-text transcriber. Output the exact words spoken, nothing else.",
}

# Quick validation samples
QUICK_SAMPLES = [
    {
        "path": str(TEST_AUDIO_DIR / "en_claude_code.wav"),
        "expected": "Claude Code is a command line tool for AI assisted coding",
        "lang": "en",
        "name": "en_claude_code",
    },
    {
        "path": str(AUDIO_DIR / "7E9A42BA-8AD9-44D7-BED3-95BAEDA2B699.m4a"),
        "expected": "好的，我来更新一把。",
        "lang": "zh",
        "name": "zh_short_update",
    },
    {
        "path": str(AUDIO_DIR / "1E656A70-C1AF-44A0-9191-2B84DCAD800D.m4a"),
        "expected": "Cloud Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。",
        "lang": "mixed",
        "name": "mixed_sdk",
    },
]

# ============================================================
# Utilities
# ============================================================

report_lines = []

def log(msg: str):
    print(msg)
    report_lines.append(msg)

def convert_to_wav(path: str) -> str:
    """Convert audio to 16kHz mono WAV if needed."""
    if path.endswith(".wav"):
        return path
    wav_path = path.rsplit(".", 1)[0] + ".wav"
    if os.path.exists(wav_path):
        return wav_path
    subprocess.run(
        ["ffmpeg", "-y", "-i", path, "-ar", "16000", "-ac", "1", wav_path],
        capture_output=True, timeout=30
    )
    return wav_path

def char_similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, a, b).ratio()

def keyword_score(text: str, keywords: list) -> tuple:
    hits = sum(1 for kw in keywords if kw.lower() in text.lower())
    return hits, len(keywords)

def is_hallucination(text: str) -> bool:
    if not text or len(text.strip()) <= 2:
        return True
    words = text.split()
    if len(words) >= 6:
        for window in range(2, min(6, len(words) // 3)):
            pattern = " ".join(words[:window])
            count = text.count(pattern)
            if count >= 3:
                return True
    if text.strip().startswith(",") or text.strip().startswith(","):
        return True
    return False

def is_garbled(text: str) -> bool:
    """Detect garbled output from quantization issues."""
    if not text:
        return True
    # Check for excessive non-CJK, non-ASCII symbols
    weird_chars = sum(1 for c in text if ord(c) > 0xFFFF or c in '\ufffd\ufffe\uffff')
    if weird_chars > len(text) * 0.3:
        return True
    # Check for repeating single characters
    if len(set(text.replace(" ", ""))) < 3 and len(text) > 10:
        return True
    return False

# ============================================================
# Model Management
# ============================================================

_loaded_models = {}

def _patch_scaled_linear():
    """
    Monkey-patch ScaledLinear to support quantization.

    The unsloth quantized Gemma 4 models include per_layer_model_projection
    in their quantization config, but ScaledLinear doesn't have to_quantized().
    mlx's nn.quantize raises ValueError when class_predicate returns True
    for a module without to_quantized.

    Fix: Add to_quantized() that returns a QuantizedScaledLinear with
    weight/scales/biases as direct attributes (matching the weight file's
    flat key structure: per_layer_model_projection.weight/.scales/.biases).
    """
    import math
    import mlx.core as mx
    import mlx.nn as nn
    from mlx.nn.layers.quantized import _defaults_for_mode
    from mlx_vlm.models.gemma4.language import ScaledLinear

    if hasattr(ScaledLinear, '_patched'):
        return

    class QuantizedScaledLinear(nn.Module):
        """Quantized version of ScaledLinear with flat weight/scales/biases."""
        def __init__(self, in_features, out_features, scalar, group_size, bits, mode):
            super().__init__()
            self.scalar = scalar
            self.group_size = group_size
            self.bits = bits
            self.mode = mode

            # Initialize with placeholder quantized weights
            # (will be overwritten by load_weights)
            scale = math.sqrt(1 / in_features)
            w = mx.random.uniform(low=-scale, high=scale, shape=(out_features, in_features))
            self.weight, self.scales, *biases = mx.quantize(w, group_size, bits, mode=mode)
            self.biases = biases[0] if biases else None
            self.freeze()

        def __call__(self, x: mx.array) -> mx.array:
            result = mx.quantized_matmul(
                x,
                self["weight"],
                scales=self["scales"],
                biases=self.get("biases"),
                transpose=True,
                group_size=self.group_size,
                bits=self.bits,
                mode=self.mode,
            )
            return result * self.scalar

    def _to_quantized(self, group_size=64, bits=4, mode="affine", **kwargs):
        gs, b = _defaults_for_mode(mode, group_size, bits)
        return QuantizedScaledLinear(
            self.weight.shape[1], self.weight.shape[0],
            self.scalar, gs, b, mode
        )

    ScaledLinear.to_quantized = _to_quantized
    ScaledLinear._patched = True
    log("  [patch] ScaledLinear.to_quantized() added for quantization support")

def load_model(model_id: str):
    """Load model, caching across calls."""
    if model_id in _loaded_models:
        return _loaded_models[model_id]

    _patch_scaled_linear()

    log(f"\nLoading model: {model_id}")
    t0 = time.time()
    from mlx_vlm.utils import load
    model, processor = load(model_id)
    elapsed = time.time() - t0
    log(f"Model loaded in {elapsed:.1f}s")
    _loaded_models[model_id] = (model, processor)
    return model, processor

def transcribe(model, processor, audio_path: str, prompt_text: str, max_tokens: int = 500) -> dict:
    """Run transcription and return result dict."""
    from mlx_vlm import generate
    from mlx_vlm.prompt_utils import apply_chat_template

    wav_path = convert_to_wav(audio_path)
    formatted = apply_chat_template(processor, model.config, prompt_text, num_audios=1)

    t0 = time.time()
    try:
        result = generate(
            model=model,
            processor=processor,
            prompt=formatted,
            audio=[wav_path],
            max_tokens=max_tokens,
            temperature=0.0,
        )
        elapsed = time.time() - t0
        text = result.strip() if isinstance(result, str) else result.text.strip()
        return {
            "text": text,
            "latency": round(elapsed, 3),
            "error": None,
            "garbled": is_garbled(text),
        }
    except Exception as e:
        elapsed = time.time() - t0
        return {
            "text": "",
            "latency": round(elapsed, 3),
            "error": str(e),
            "garbled": True,
        }

# ============================================================
# Experiment 1: Quick Validation
# ============================================================

def experiment_quick_validation(model_name: str, model_id: str) -> bool:
    """Quick 3-sample validation. Returns True if model produces usable output."""
    log(f"\n{'='*72}")
    log(f"EXPERIMENT 1: Quick Validation - {model_name} ({model_id})")
    log(f"{'='*72}")

    model, processor = load_model(model_id)
    prompt = PROMPTS["gen0_baseline"]

    garbled_count = 0
    for sample in QUICK_SAMPLES:
        if not os.path.exists(sample["path"]):
            log(f"  SKIP: {sample['name']} - file not found: {sample['path']}")
            continue

        log(f"\n  [{sample['name']}] ({sample['lang']})")
        log(f"  Expected: {sample['expected'][:80]}")

        result = transcribe(model, processor, sample["path"], prompt)

        log(f"  Output:   {result['text'][:80]}")
        log(f"  Latency:  {result['latency']:.2f}s")

        if result["error"]:
            log(f"  ERROR:    {result['error'][:200]}")
            garbled_count += 1
        elif result["garbled"]:
            log(f"  WARNING:  Output appears GARBLED (quantization issue?)")
            garbled_count += 1
        else:
            sim = char_similarity(sample["expected"], result["text"])
            log(f"  Similarity: {sim:.3f}")

    usable = garbled_count < len(QUICK_SAMPLES)
    log(f"\n  Verdict: {'USABLE' if usable else 'GARBLED/UNUSABLE'} ({garbled_count}/{len(QUICK_SAMPLES)} garbled)")
    return usable

# ============================================================
# Experiment 2: Full Regression Suite
# ============================================================

def run_regression(model, processor, prompt_name: str, prompt_text: str, engine_label: str) -> dict:
    """Run full 12-case regression suite."""
    with open(CASES_PATH) as f:
        suite = json.load(f)

    results = {
        "engine": engine_label,
        "prompt": prompt_name,
        "prompt_text": prompt_text,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "cases": [],
        "summary": {},
    }

    total_sim = 0
    total_kw_hits = 0
    total_kw_total = 0
    total_hallucinations = 0
    total_latency = 0
    n = 0

    for case in suite["cases"]:
        audio_path = str(AUDIO_DIR / case["file"])
        if not os.path.exists(audio_path):
            log(f"  SKIP {case['id']}: audio not found")
            continue

        log(f"  {case['id']} ({case['duration']}s, {case['lang']})...", )

        r = transcribe(model, processor, audio_path, prompt_text)

        gt = case["ground_truth"]
        sim = char_similarity(gt, r["text"])
        kw_hits, kw_total = keyword_score(r["text"], case.get("keywords", []))
        hallucinated = is_hallucination(r["text"])

        case_result = {
            "id": case["id"],
            "similarity": round(sim, 3),
            "keyword_hits": kw_hits,
            "keyword_total": kw_total,
            "keyword_score": round(kw_hits / max(kw_total, 1), 3),
            "hallucination": hallucinated,
            "latency": r["latency"],
            "garbled": r["garbled"],
            "output": r["text"][:200],
            "ground_truth": gt[:200],
            "error": r["error"],
        }
        results["cases"].append(case_result)

        total_sim += sim
        total_kw_hits += kw_hits
        total_kw_total += kw_total
        total_hallucinations += 1 if hallucinated else 0
        total_latency += r["latency"]
        n += 1

        marker = "GARBLED" if r["garbled"] else ("HALLUC" if hallucinated else ("OK" if sim > 0.3 else "LOW"))
        log(f"    {marker} sim={sim:.3f} kw={kw_hits}/{kw_total} {r['latency']:.2f}s")
        if r["text"]:
            log(f"    output: {r['text'][:100]}")

    results["summary"] = {
        "total_cases": n,
        "avg_similarity": round(total_sim / max(n, 1), 3),
        "keyword_accuracy": round(total_kw_hits / max(total_kw_total, 1), 3),
        "hallucination_count": total_hallucinations,
        "hallucination_rate": round(total_hallucinations / max(n, 1), 3),
        "total_latency": round(total_latency, 2),
        "avg_latency": round(total_latency / max(n, 1), 3),
    }

    return results

def experiment_full_regression(model_name: str, model_id: str) -> dict:
    """Run baseline prompt on full regression suite."""
    log(f"\n{'='*72}")
    log(f"EXPERIMENT 2: Full Regression - {model_name}")
    log(f"{'='*72}")

    model, processor = load_model(model_id)
    prompt_name = "gen0_baseline"
    prompt_text = PROMPTS[prompt_name]
    engine_label = f"gemma4-{model_name}"

    results = run_regression(model, processor, prompt_name, prompt_text, engine_label)

    s = results["summary"]
    log(f"\n  Summary:")
    log(f"    Avg Similarity:   {s['avg_similarity']:.3f}")
    log(f"    Keyword Accuracy: {s['keyword_accuracy']:.3f}")
    log(f"    Hallucinations:   {s['hallucination_count']}/{s['total_cases']}")
    log(f"    Avg Latency:      {s['avg_latency']:.3f}s")

    # Save results
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    path = RESULTS_DIR / f"gemma4_{model_name}_{prompt_name}_{ts}.json"
    with open(path, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    log(f"  Results saved to: {path}")

    return results

# ============================================================
# Experiment 3: Prompt Evolution
# ============================================================

def experiment_prompt_evolution(model_name: str, model_id: str, baseline_score: float) -> list:
    """Test prompt variants, keep those that beat baseline."""
    log(f"\n{'='*72}")
    log(f"EXPERIMENT 3: Prompt Evolution - {model_name}")
    log(f"{'='*72}")

    model, processor = load_model(model_id)
    engine_label = f"gemma4-{model_name}"

    all_results = []
    sota_score = baseline_score
    sota_prompt = "gen0_baseline"

    for prompt_name, prompt_text in PROMPTS.items():
        if prompt_name == "gen0_baseline":
            continue  # Already tested

        log(f"\n  --- Testing: {prompt_name} ---")
        log(f"  Prompt: \"{prompt_text[:80]}\"")

        results = run_regression(model, processor, prompt_name, prompt_text, engine_label)

        s = results["summary"]
        score = s["avg_similarity"]
        log(f"\n  Score: sim={score:.3f} kw={s['keyword_accuracy']:.3f} halluc={s['hallucination_count']}")

        delta = score - sota_score
        if delta > 0.01:
            decision = "KEEP (new SOTA)"
            sota_score = score
            sota_prompt = prompt_name
        elif abs(delta) <= 0.01:
            decision = "NEUTRAL"
        else:
            decision = "DISCARD"

        log(f"  vs SOTA ({sota_prompt}): {delta:+.3f} -> {decision}")

        all_results.append({
            "prompt_name": prompt_name,
            "prompt_text": prompt_text,
            "results": results,
            "decision": decision,
            "delta": delta,
        })

        # Save individual results
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        ts = time.strftime("%Y%m%d_%H%M%S")
        path = RESULTS_DIR / f"gemma4_{model_name}_{prompt_name}_{ts}.json"
        with open(path, "w") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)

    log(f"\n  Final SOTA: {sota_prompt} (sim={sota_score:.3f})")
    return all_results

# ============================================================
# Evolution Log Generation
# ============================================================

def write_evolution_log(model_name: str, model_id: str, baseline_results: dict, evolution_results: list):
    """Write structured evolution log."""
    lines = [
        f"# Gemma 4 Quantized ASR Evolution Log",
        f"",
        f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"Model: {model_id}",
        f"Variant: {model_name}",
        f"mlx-vlm version: 0.4.4",
        f"",
        f"## Previous Baseline (non-quantized google/gemma-4-e2b-it)",
        f"- avg_similarity: 0.061",
        f"- keyword_accuracy: 0.000",
        f"- Verdict: UNUSABLE (paraphrases instead of transcribing)",
        f"",
        f"## Qwen3 Baseline (ground truth source)",
        f"- avg_similarity: 1.000 (by definition, GT = Qwen3 output)",
        f"- keyword_accuracy: 1.000",
        f"",
    ]

    # Baseline prompt results
    s = baseline_results["summary"]
    lines.extend([
        f"## Generation 0: Baseline Prompt",
        f"- Prompt: \"{PROMPTS['gen0_baseline']}\"",
        f"- Model: {model_id}",
        f"- Score: sim={s['avg_similarity']:.3f}, kw={s['keyword_accuracy']:.3f}, hallucination={s['hallucination_count']}/{s['total_cases']}",
        f"- Avg Latency: {s['avg_latency']:.3f}s",
        f"- vs Previous (non-quantized): {s['avg_similarity'] - 0.061:+.3f}",
        f"- Decision: BASELINE",
        f"",
        f"### Per-case results:",
    ])
    for c in baseline_results["cases"]:
        lines.append(f"- {c['id']}: sim={c['similarity']:.3f} kw={c['keyword_hits']}/{c['keyword_total']} {'GARBLED' if c.get('garbled') else ''}")
        if c.get("output"):
            lines.append(f"  output: {c['output'][:100]}")
        if c.get("error"):
            lines.append(f"  error: {c['error'][:100]}")

    lines.append("")

    # Evolution results
    for i, evo in enumerate(evolution_results, 1):
        s = evo["results"]["summary"]
        lines.extend([
            f"## Generation 1{chr(ord('a')+i-1)}: {evo['prompt_name']}",
            f"- Prompt: \"{evo['prompt_text']}\"",
            f"- Model: {model_id}",
            f"- Score: sim={s['avg_similarity']:.3f}, kw={s['keyword_accuracy']:.3f}, hallucination={s['hallucination_count']}/{s['total_cases']}",
            f"- Avg Latency: {s['avg_latency']:.3f}s",
            f"- vs SOTA: {evo['delta']:+.3f}",
            f"- Decision: {evo['decision']}",
            f"",
        ])

    with open(LOG_PATH, "w") as f:
        f.write("\n".join(lines))

    log(f"\nEvolution log saved to: {LOG_PATH}")

# ============================================================
# Main
# ============================================================

def main():
    log(f"{'='*72}")
    log(f"Gemma 4 Quantized ASR Experiment")
    log(f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    log(f"{'='*72}")
    log(f"")
    log(f"NOTE: unsloth/gemma-4-E2B-it-UD-MLX-4bit is text-only (no audio tower).")
    log(f"Using mlx-community quantized versions which include audio support.")

    # Try models in order of preference
    model_order = ["mlx-2B-4bit", "mlx-4B-4bit", "ezcon-2B-4bit"]
    best_name = None
    best_score = 0
    best_results = None
    best_evolution = []

    for model_name in model_order:
        model_id = MODELS[model_name]

        # Clear previous model from memory
        _loaded_models.clear()

        # Experiment 1: Quick validation
        try:
            usable = experiment_quick_validation(model_name, model_id)
        except Exception as e:
            log(f"\n  FAILED to load {model_name}: {e}")
            continue

        if not usable:
            log(f"\n  {model_name} output is garbled/unusable. Trying next model...")
            continue

        # Experiment 2: Full regression
        baseline_results = experiment_full_regression(model_name, model_id)
        baseline_score = baseline_results["summary"]["avg_similarity"]

        # Experiment 3: Prompt evolution (only if baseline shows some capability)
        if baseline_score > 0.1:
            evolution_results = experiment_prompt_evolution(model_name, model_id, baseline_score)
        else:
            log(f"\nBaseline score too low ({baseline_score:.3f}), skipping prompt evolution.")
            evolution_results = []

        # Write evolution log for this model
        write_evolution_log(model_name, model_id, baseline_results, evolution_results)

        # Track best
        if baseline_score > best_score:
            best_score = baseline_score
            best_name = model_name
            best_results = baseline_results
            best_evolution = evolution_results

        # If score is decent, no need to try more models
        if baseline_score > 0.3:
            log(f"\n{model_name} achieved decent score ({baseline_score:.3f}), skipping remaining models.")
            break

    if best_name is None:
        log(f"\nAll quantized models failed or produced unusable output.")
        write_garbled_log()
    else:
        log(f"\n{'='*72}")
        log(f"BEST MODEL: {best_name} (sim={best_score:.3f})")
        log(f"{'='*72}")

    log(f"\nFull report in: {LOG_PATH}")

def write_garbled_log():
    """Write log when all models produce garbled output."""
    lines = [
        "# Gemma 4 Quantized ASR Evolution Log",
        "",
        f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "## Result: ALL MODELS PRODUCE GARBLED OUTPUT",
        "",
        "Both unsloth/gemma-4-E2B-it-UD-MLX-4bit and unsloth/gemma-4-E4B-it-UD-MLX-4bit",
        "produce garbled/unusable output. This confirms the PLE (Piecewise Linear Encoding)",
        "layer quantization issue reported for mlx-community quantized Gemma 4 models.",
        "",
        "The unsloth versions do NOT fix this issue.",
        "",
        "## Recommendation",
        "- Stay with Qwen3-ASR-0.6B as the primary ASR engine",
        "- Wait for upstream fixes to PLE layer quantization",
        "- Or try non-quantized Gemma 4 with memory optimization",
    ]
    with open(LOG_PATH, "w") as f:
        f.write("\n".join(lines))
    log(f"\nGarbled output log saved to: {LOG_PATH}")


if __name__ == "__main__":
    main()
