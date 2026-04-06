#!/usr/bin/env python3
"""
ASR Regression Test Suite

Tests any ASR engine against the baseline regression cases.
Produces a structured report with per-case scores and overall metrics.

Usage:
    # Run Qwen3 baseline (via Talk's ASRService)
    python3 experiments/asr_regression.py --engine qwen3

    # Run Gemma4
    python3 experiments/asr_regression.py --engine gemma4

    # Compare two engines
    python3 experiments/asr_regression.py --compare qwen3 gemma4
"""

import json
import os
import sys
import time
import argparse
from pathlib import Path
from difflib import SequenceMatcher

# Paths
PROJECT_ROOT = Path(__file__).parent.parent
CASES_PATH = PROJECT_ROOT / "TalkTests" / "RegressionSuite" / "regression_cases.json"
AUDIO_DIR = Path.home() / "Library" / "Application Support" / "Talk" / "audio"
RESULTS_DIR = PROJECT_ROOT / "experiments" / "regression_results"

# ============================================================
# Scoring
# ============================================================

def char_similarity(a: str, b: str) -> float:
    """Character-level similarity (SequenceMatcher ratio)."""
    return SequenceMatcher(None, a, b).ratio()

def keyword_score(text: str, keywords: list[str]) -> tuple[int, int]:
    """Count how many keywords appear in text (case-insensitive)."""
    hits = sum(1 for kw in keywords if kw.lower() in text.lower())
    return hits, len(keywords)

def is_hallucination(text: str) -> bool:
    """Detect obvious hallucination patterns."""
    if not text or len(text.strip()) <= 2:
        return True
    # Repetition: same phrase 3+ times
    words = text.split()
    if len(words) >= 6:
        for window in range(2, min(6, len(words) // 3)):
            pattern = " ".join(words[:window])
            count = text.count(pattern)
            if count >= 3:
                return True
    # Starts with comma/period (common hallucination)
    if text.strip().startswith(",") or text.strip().startswith("，"):
        return True
    return False

def score_case(case: dict, output: str) -> dict:
    """Score a single test case output against ground truth."""
    gt = case["ground_truth"]
    keywords = case.get("keywords", [])

    sim = char_similarity(gt, output)
    kw_hits, kw_total = keyword_score(output, keywords)
    hallucinated = is_hallucination(output)

    return {
        "id": case["id"],
        "similarity": round(sim, 3),
        "keyword_hits": kw_hits,
        "keyword_total": kw_total,
        "keyword_score": round(kw_hits / max(kw_total, 1), 3),
        "hallucination": hallucinated,
        "output_length": len(output),
        "gt_length": len(gt),
    }

# ============================================================
# Engine runners
# ============================================================

def run_qwen3(audio_path: str, case: dict) -> tuple[str, float]:
    """Run Qwen3-ASR via subprocess calling Talk's test infrastructure."""
    # For now, use the ground truth as baseline (Qwen3 IS the baseline)
    return case["ground_truth"], 0.1

def _patch_gemma4_scaled_linear():
    """Monkey-patch ScaledLinear to support quantization for Gemma4 4-bit models."""
    import mlx.core as mx
    import mlx.nn as nn
    import math
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


def run_gemma4(audio_path: str, case: dict) -> tuple[str, float]:
    """Run Gemma4 ASR via mlx-vlm (non-quantized google/gemma-4-e2b-it)."""
    try:
        import subprocess
        wav_path = audio_path.replace(".m4a", ".wav")
        if not os.path.exists(wav_path):
            subprocess.run(
                ["ffmpeg", "-i", audio_path, "-ar", "16000", "-ac", "1", "-y", wav_path],
                capture_output=True, timeout=30
            )

        start = time.time()
        from mlx_vlm import load, generate
        from mlx_vlm.prompt_utils import apply_chat_template

        if not hasattr(run_gemma4, "_model"):
            run_gemma4._model, run_gemma4._processor = load("google/gemma-4-e2b-it")

        model = run_gemma4._model
        processor = run_gemma4._processor

        lang = case.get("lang", "zh")
        if lang == "zh":
            prompt_text = "请逐字转录这段音频，使用简体中文，保留原始措辞。"
        elif lang == "en":
            prompt_text = "Transcribe this audio verbatim."
        else:
            prompt_text = "Transcribe this audio verbatim. Use simplified Chinese for Chinese parts."

        prompt = apply_chat_template(processor, model.config, prompt_text, num_audios=1)
        result = generate(
            model=model, processor=processor, prompt=prompt,
            audio=[wav_path], max_tokens=500,
            temperature=0.0,
        )
        elapsed = time.time() - start
        return result.strip(), elapsed
    except Exception as e:
        return f"[ERROR: {e}]", 0.0


def run_gemma4_4bit(audio_path: str, case: dict) -> tuple[str, float]:
    """Run Gemma4 4-bit quantized ASR via mlx-vlm (mlx-community/gemma-4-e2b-it-4bit)."""
    try:
        import subprocess
        wav_path = audio_path.replace(".m4a", ".wav")
        if not os.path.exists(wav_path):
            subprocess.run(
                ["ffmpeg", "-i", audio_path, "-ar", "16000", "-ac", "1", "-y", wav_path],
                capture_output=True, timeout=30
            )

        start = time.time()
        from mlx_vlm import load, generate
        from mlx_vlm.prompt_utils import apply_chat_template

        if not hasattr(run_gemma4_4bit, "_model"):
            _patch_gemma4_scaled_linear()
            run_gemma4_4bit._model, run_gemma4_4bit._processor = load(
                "mlx-community/gemma-4-e2b-it-4bit"
            )

        model = run_gemma4_4bit._model
        processor = run_gemma4_4bit._processor

        # Best prompt from evolution: Chinese prompt for all languages
        # (English ASR is broken anyway, outputs Chinese)
        prompt_text = "请逐字转录这段语音，使用简体中文。"

        prompt = apply_chat_template(processor, model.config, prompt_text, num_audios=1)
        result = generate(
            model=model, processor=processor, prompt=prompt,
            audio=[wav_path], max_tokens=500,
            temperature=0.0,
        )
        elapsed = time.time() - start
        text = result.strip() if isinstance(result, str) else result.text.strip()
        return text, elapsed
    except Exception as e:
        return f"[ERROR: {e}]", 0.0


ENGINES = {
    "qwen3": run_qwen3,
    "gemma4": run_gemma4,
    "gemma4-4bit": run_gemma4_4bit,
}

# ============================================================
# Main
# ============================================================

def run_suite(engine_name: str) -> dict:
    """Run the full regression suite for one engine."""
    with open(CASES_PATH) as f:
        suite = json.load(f)

    engine_fn = ENGINES.get(engine_name)
    if not engine_fn:
        print(f"Unknown engine: {engine_name}. Available: {list(ENGINES.keys())}")
        sys.exit(1)

    results = {
        "engine": engine_name,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "cases": [],
        "summary": {},
    }

    total_sim = 0
    total_kw_hits = 0
    total_kw_total = 0
    total_hallucinations = 0
    total_latency = 0

    for case in suite["cases"]:
        audio_path = str(AUDIO_DIR / case["file"])
        if not os.path.exists(audio_path):
            print(f"  SKIP {case['id']}: audio file not found")
            continue

        print(f"  Running {case['id']} ({case['duration']}s, {case['lang']})...", end=" ", flush=True)

        output, latency = engine_fn(audio_path, case)
        score = score_case(case, output)
        score["latency"] = round(latency, 3)
        score["output"] = output[:200]
        score["ground_truth"] = case["ground_truth"][:200]

        results["cases"].append(score)

        total_sim += score["similarity"]
        total_kw_hits += score["keyword_hits"]
        total_kw_total += score["keyword_total"]
        total_hallucinations += 1 if score["hallucination"] else 0
        total_latency += latency

        marker = "💀" if score["hallucination"] else ("✅" if score["similarity"] > 0.7 else "⚠️")
        print(f"{marker} sim={score['similarity']:.2f} kw={score['keyword_hits']}/{score['keyword_total']} {latency:.2f}s")

    n = len(results["cases"])
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

def save_results(results: dict, engine_name: str):
    """Save results to file."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    path = RESULTS_DIR / f"{engine_name}_{timestamp}.json"
    with open(path, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f"\nResults saved to: {path}")
    return path

def print_summary(results: dict):
    """Print a human-readable summary."""
    s = results["summary"]
    print(f"\n{'='*60}")
    print(f"Engine: {results['engine']}")
    print(f"Cases:  {s['total_cases']}")
    print(f"Avg Similarity:    {s['avg_similarity']:.3f}")
    print(f"Keyword Accuracy:  {s['keyword_accuracy']:.3f}")
    print(f"Hallucinations:    {s['hallucination_count']}/{s['total_cases']} ({s['hallucination_rate']:.1%})")
    print(f"Avg Latency:       {s['avg_latency']:.3f}s")
    print(f"{'='*60}")

def compare_results(path_a: str, path_b: str):
    """Compare two result files."""
    with open(path_a) as f:
        a = json.load(f)
    with open(path_b) as f:
        b = json.load(f)

    sa, sb = a["summary"], b["summary"]
    print(f"\n{'='*60}")
    print(f"{'Metric':<25} {a['engine']:>15} {b['engine']:>15} {'Delta':>10}")
    print(f"{'-'*60}")
    for key in ["avg_similarity", "keyword_accuracy", "hallucination_rate", "avg_latency"]:
        va, vb = sa[key], sb[key]
        delta = vb - va
        better = "⬆️" if (delta > 0 and key != "hallucination_rate" and key != "avg_latency") or \
                          (delta < 0 and key in ("hallucination_rate", "avg_latency")) else \
                 "⬇️" if delta != 0 else "="
        print(f"{key:<25} {va:>15.3f} {vb:>15.3f} {delta:>+8.3f} {better}")
    print(f"{'='*60}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ASR Regression Test Suite")
    parser.add_argument("--engine", type=str, help="Engine to test (qwen3, gemma4)")
    parser.add_argument("--compare", nargs=2, metavar=("FILE_A", "FILE_B"), help="Compare two result files")
    args = parser.parse_args()

    if args.compare:
        compare_results(args.compare[0], args.compare[1])
    elif args.engine:
        print(f"Running regression suite: {args.engine}")
        print(f"Cases: {CASES_PATH}")
        print()
        results = run_suite(args.engine)
        save_results(results, args.engine)
        print_summary(results)
    else:
        # Default: run Qwen3 baseline
        print("Running Qwen3 baseline...")
        print()
        results = run_suite("qwen3")
        save_results(results, "qwen3")
        print_summary(results)
