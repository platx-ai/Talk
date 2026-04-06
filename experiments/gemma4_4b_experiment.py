#!/usr/bin/env python3
"""
Gemma 4 4B ASR Experiment
==========================
Tests mlx-community/gemma-4-e4b-it-4bit (4B parameter model) for ASR.
Compares against 2B SOTA (sim=0.569, kw=0.344).

Usage:
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_4b_experiment.py
"""

import json
import os
import sys
import time
import subprocess
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
CASES_PATH = PROJECT_ROOT / "TalkTests" / "RegressionSuite" / "regression_cases.json"
RESULTS_DIR = PROJECT_ROOT / "experiments" / "regression_results"
LOG_PATH = PROJECT_ROOT / "experiments" / "gemma4_evolution_log.md"

MODEL_ID = "mlx-community/gemma-4-e4b-it-4bit"
MODEL_NAME = "mlx-4B-4bit"

# 2B SOTA for comparison
SOTA_2B_SIM = 0.569
SOTA_2B_KW = 0.344
SOTA_2B_PROMPT = "请逐字转录这段语音，使用简体中文。"

# Prompts to test
PROMPTS = {
    "gen2_baseline": "请逐字转录这段语音，使用简体中文。",  # 2B best prompt
    "gen2a_precise": "请精确转录这段语音的每一个字，使用简体中文，保留所有英文单词的原始拼写。",
    "gen2b_bilingual": "Transcribe this audio exactly as spoken. Keep English words in English. Use simplified Chinese for Chinese parts.",
}

# ============================================================
# Utilities
# ============================================================

report_lines = []

def log(msg: str):
    print(msg, flush=True)
    report_lines.append(msg)

def convert_to_wav(path: str) -> str:
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
    if text.strip().startswith(",") or text.strip().startswith("\uff0c"):
        return True
    return False

def is_garbled(text: str) -> bool:
    if not text:
        return True
    weird_chars = sum(1 for c in text if ord(c) > 0xFFFF or c in '\ufffd\ufffe\uffff')
    if weird_chars > len(text) * 0.3:
        return True
    if len(set(text.replace(" ", ""))) < 3 and len(text) > 10:
        return True
    return False

# ============================================================
# Model Management
# ============================================================

_model = None
_processor = None

def _patch_scaled_linear():
    """Monkey-patch ScaledLinear to support quantization for Gemma4 4-bit models."""
    import math
    import mlx.core as mx
    import mlx.nn as nn
    from mlx.nn.layers.quantized import _defaults_for_mode
    from mlx_vlm.models.gemma4.language import ScaledLinear

    if hasattr(ScaledLinear, '_patched'):
        return

    class QuantizedScaledLinear(nn.Module):
        def __init__(self, in_features, out_features, scalar, group_size, bits, mode):
            super().__init__()
            self.scalar = scalar
            self.group_size = group_size
            self.bits = bits
            self.mode = mode
            scale = math.sqrt(1 / in_features)
            w = mx.random.uniform(low=-scale, high=scale, shape=(out_features, in_features))
            self.weight, self.scales, *biases = mx.quantize(w, group_size, bits, mode=mode)
            self.biases = biases[0] if biases else None
            self.freeze()

        def __call__(self, x):
            result = mx.quantized_matmul(
                x, self["weight"], scales=self["scales"], biases=self.get("biases"),
                transpose=True, group_size=self.group_size, bits=self.bits, mode=self.mode,
            )
            return result * self.scalar

    def _to_quantized(self, group_size=64, bits=4, mode="affine", **kwargs):
        gs, b = _defaults_for_mode(mode, group_size, bits)
        return QuantizedScaledLinear(
            self.weight.shape[1], self.weight.shape[0], self.scalar, gs, b, mode
        )

    ScaledLinear.to_quantized = _to_quantized
    ScaledLinear._patched = True
    log("  [patch] ScaledLinear.to_quantized() patched")

def load_model():
    global _model, _processor
    if _model is not None:
        return _model, _processor

    _patch_scaled_linear()

    log(f"\nLoading model: {MODEL_ID}")
    t0 = time.time()
    from mlx_vlm.utils import load
    _model, _processor = load(MODEL_ID)
    elapsed = time.time() - t0
    log(f"Model loaded in {elapsed:.1f}s")

    # Verify audio tower
    param_count = sum(1 for k in _model.parameters().keys() if 'audio' in str(k).lower())
    log(f"Audio-related parameter groups: {param_count}")

    return _model, _processor

def transcribe(model, processor, audio_path: str, prompt_text: str, max_tokens: int = 500) -> dict:
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
# Full Regression
# ============================================================

def run_regression(model, processor, prompt_name: str, prompt_text: str) -> dict:
    with open(CASES_PATH) as f:
        suite = json.load(f)

    results = {
        "engine": f"gemma4-{MODEL_NAME}",
        "model": MODEL_ID,
        "prompt_name": prompt_name,
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

        log(f"  {case['id']} ({case['duration']}s, {case['lang']})...")

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
            "output": r["text"][:300],
            "ground_truth": gt[:300],
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
        log(f"    output: {r['text'][:120]}")

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

# ============================================================
# Main
# ============================================================

def main():
    log(f"{'='*72}")
    log(f"Gemma 4 4B ASR Experiment")
    log(f"Model: {MODEL_ID}")
    log(f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    log(f"2B SOTA: sim={SOTA_2B_SIM}, kw={SOTA_2B_KW}")
    log(f"{'='*72}")

    # Load model
    try:
        model, processor = load_model()
    except Exception as e:
        log(f"\nFAILED to load model: {e}")
        import traceback
        traceback.print_exc()
        return

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    all_results = {}
    sota_sim = 0
    sota_prompt = None

    for prompt_name, prompt_text in PROMPTS.items():
        log(f"\n{'='*72}")
        log(f"Testing prompt: {prompt_name}")
        log(f"Prompt: \"{prompt_text}\"")
        log(f"{'='*72}")

        results = run_regression(model, processor, prompt_name, prompt_text)
        all_results[prompt_name] = results

        s = results["summary"]
        log(f"\n  Summary for {prompt_name}:")
        log(f"    Avg Similarity:   {s['avg_similarity']:.3f}")
        log(f"    Keyword Accuracy: {s['keyword_accuracy']:.3f}")
        log(f"    Hallucinations:   {s['hallucination_count']}/{s['total_cases']}")
        log(f"    Avg Latency:      {s['avg_latency']:.3f}s")
        log(f"    vs 2B SOTA (sim): {s['avg_similarity'] - SOTA_2B_SIM:+.3f}")
        log(f"    vs 2B SOTA (kw):  {s['keyword_accuracy'] - SOTA_2B_KW:+.3f}")

        # Save individual results
        ts = time.strftime("%Y%m%d_%H%M%S")
        path = RESULTS_DIR / f"gemma4_{MODEL_NAME}_{prompt_name}_{ts}.json"
        with open(path, "w") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        log(f"  Saved: {path}")

        if s["avg_similarity"] > sota_sim:
            sota_sim = s["avg_similarity"]
            sota_prompt = prompt_name

    # Write evolution log (append to existing)
    log(f"\n{'='*72}")
    log(f"FINAL RESULTS")
    log(f"{'='*72}")
    log(f"Best prompt: {sota_prompt} (sim={sota_sim:.3f})")
    log(f"vs 2B SOTA:  {sota_sim - SOTA_2B_SIM:+.3f}")

    append_evolution_log(all_results, sota_prompt, sota_sim)

def append_evolution_log(all_results: dict, best_prompt: str, best_sim: float):
    """Append 4B results to the evolution log."""
    # Read existing log
    existing = ""
    if LOG_PATH.exists():
        with open(LOG_PATH) as f:
            existing = f.read()

    lines = [
        "",
        "---",
        "",
        f"## Generation 2: Gemma4 4B Experiments",
        f"",
        f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"Model: {MODEL_ID}",
        f"Model size: ~5.2 GB (4-bit quantized, vs ~1.5 GB for 2B 4-bit)",
        f"",
    ]

    for prompt_name, results in all_results.items():
        s = results["summary"]
        prompt_text = results["prompt_text"]

        delta_sim = s["avg_similarity"] - SOTA_2B_SIM
        delta_kw = s["keyword_accuracy"] - SOTA_2B_KW

        if s["avg_similarity"] > SOTA_2B_SIM + 0.01:
            decision = "KEEP (beats 2B SOTA)"
        elif abs(s["avg_similarity"] - SOTA_2B_SIM) <= 0.01:
            decision = "NEUTRAL (within margin of 2B SOTA)"
        else:
            decision = "DISCARD (worse than 2B SOTA)"

        lines.extend([
            f"### {prompt_name}",
            f"- Model: {MODEL_ID}",
            f"- Prompt: \"{prompt_text}\"",
            f"- Score: sim={s['avg_similarity']:.3f}, kw={s['keyword_accuracy']:.3f}, hallucination={s['hallucination_count']}/{s['total_cases']}",
            f"- Avg Latency: {s['avg_latency']:.3f}s",
            f"- vs 2B SOTA (sim=0.569): {delta_sim:+.3f}",
            f"- vs 2B SOTA (kw=0.344): {delta_kw:+.3f}",
            f"- vs Qwen3 (1.000): gap={1.000 - s['avg_similarity']:.3f}",
            f"- Decision: {decision}",
            f"",
            f"Per-case results:",
        ])
        for c in results["cases"]:
            garbled = " GARBLED" if c.get("garbled") else ""
            halluc = " HALLUC" if c.get("hallucination") else ""
            lines.append(f"- {c['id']}: sim={c['similarity']:.3f} kw={c['keyword_hits']}/{c['keyword_total']}{garbled}{halluc}")
            if c.get("output"):
                lines.append(f"  output: {c['output'][:120]}")
        lines.append("")

    # Summary
    best_results = all_results[best_prompt]
    best_s = best_results["summary"]
    lines.extend([
        f"### 4B Summary",
        f"- Best prompt: {best_prompt} (\"{PROMPTS.get(best_prompt, best_results['prompt_text'])}\")",
        f"- Best sim: {best_sim:.3f} (vs 2B SOTA: {best_sim - SOTA_2B_SIM:+.3f})",
        f"- Best kw: {best_s['keyword_accuracy']:.3f} (vs 2B SOTA: {best_s['keyword_accuracy'] - SOTA_2B_KW:+.3f})",
        f"- Avg Latency: {best_s['avg_latency']:.3f}s",
        f"",
        f"## Updated Comparison Table",
        f"",
        f"| Metric | Qwen3-ASR | Gemma4 2B 4bit | Gemma4 4B 4bit (best) |",
        f"|--------|-----------|----------------|----------------------|",
        f"| Model | Qwen3-ASR-0.6B | mlx-community/gemma-4-e2b-it-4bit | {MODEL_ID} |",
        f"| Size | ~1.6 GB | ~1.5 GB | ~5.2 GB |",
        f"| Avg Similarity | 1.000 | {SOTA_2B_SIM:.3f} | {best_sim:.3f} |",
        f"| Keyword Accuracy | 1.000 | {SOTA_2B_KW:.3f} | {best_s['keyword_accuracy']:.3f} |",
        f"| Avg Latency | ~2-4s | ~0.28s | {best_s['avg_latency']:.3f}s |",
        f"",
    ])

    with open(LOG_PATH, "w") as f:
        f.write(existing + "\n".join(lines))
    log(f"\nEvolution log updated: {LOG_PATH}")


if __name__ == "__main__":
    main()
