#!/usr/bin/env python3
"""
Gemma 4 End-to-End ASR+Polish Experiment (Gen 4 & Gen 5)
==========================================================

Goal: Beat Qwen3 baseline (sim=0.792) with a single Gemma4 model doing
both transcription AND polishing in one pass (no Qwen3 dependency).

Current SOTA (single-model): Gemma4 4B + t2s = sim=0.736, kw=0.450
Target: sim > 0.792

Approach:
  Gen 4: New end-to-end prompts for 4B model
    a) "请听这段音频，输出说话人说的完整内容。使用简体中文，英文单词保持原样。去除口语填充词，添加标点。"
    b) English prompt variant
    c) Structured instruction variant
    d) Combined best elements from polish_v4_english (which beat Qwen3 at 0.870 with Qwen3 input)
    e) Few-shot style with output format hints

  Gen 5: Test 2B model with best prompts from Gen 4

Usage:
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_e2e_experiment.py
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_e2e_experiment.py --model 2b
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_e2e_experiment.py --model 4b --prompt gen4a
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_e2e_experiment.py --model 4b --prompt all
"""

import json
import os
import sys
import time
import subprocess
import argparse
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

MODELS = {
    "4b": "mlx-community/gemma-4-e4b-it-4bit",
    "2b": "mlx-community/gemma-4-e2b-it-4bit",
}

# Baselines (human-annotated GT)
BASELINE_QWEN3_SIM = 0.792
BASELINE_QWEN3_KW = 0.750
BASELINE_GEMMA4_4B_T2S_SIM = 0.736  # Current SOTA single-model
BASELINE_GEMMA4_4B_T2S_KW = 0.450

# ============================================================
# Gen 4: End-to-End Prompts (ASR + polish in single pass)
# ============================================================

E2E_PROMPTS = {
    # --- Gen 4a: Chinese instruction, clean output ---
    "gen4a_clean_zh": (
        "请听这段音频，输出说话人说的完整内容。"
        "使用简体中文，英文单词保持原样。"
        "去除口语填充词（嗯、啊、呃），添加标点。"
    ),

    # --- Gen 4b: English instruction (inspired by polish_v4_english's success) ---
    "gen4b_clean_en": (
        "Listen to this audio and produce a clean, accurate transcript. "
        "Use simplified Chinese for Chinese speech. "
        "Keep English words as-is. "
        "Remove filler words. Add proper punctuation."
    ),

    # --- Gen 4c: Structured numbered instructions ---
    "gen4c_structured": (
        "你是一个语音转文字助手。请将音频内容转为文字，要求：\n"
        "1. 使用简体中文\n"
        "2. 英文单词和专业术语保持原样（如SDK, CLI, Agent, SOTA, Review）\n"
        "3. 添加标点符号\n"
        "4. 去除'嗯'、'啊'、'呃'等填充词\n"
        "5. 只输出转录文本，不要添加任何解释"
    ),

    # --- Gen 4d: Maximally precise, bilingual-aware ---
    "gen4d_precise_bilingual": (
        "请精确转录这段语音的每一个字。规则：\n"
        "- 中文部分使用简体中文\n"
        "- 英文单词保持原始拼写，不要翻译成中文\n"
        "- 添加恰当的标点符号\n"
        "- 去除口头语和填充词\n"
        "只输出最终文本。"
    ),

    # --- Gen 4e: Short English (minimal, let model figure it out) ---
    "gen4e_minimal_en": (
        "Transcribe this audio verbatim into simplified Chinese. "
        "Keep English words in English. Add punctuation."
    ),

    # --- Gen 4f: Role-play as professional transcriber ---
    "gen4f_role": (
        "You are a professional bilingual transcriber. "
        "Transcribe the audio precisely. Output simplified Chinese for Chinese parts, "
        "keep English words as spelled. "
        "Fix nothing, just transcribe accurately with proper punctuation."
    ),

    # --- Gen 4g: Current best ASR prompt + clean-up instruction ---
    "gen4g_asr_plus_clean": (
        "请精确转录这段语音的每一个字，使用简体中文，保留所有英文单词的原始拼写。"
        "同时去除口语填充词，添加标点符号。"
    ),
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
        capture_output=True, timeout=30,
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


def t2s_convert(text: str) -> str:
    """Convert traditional Chinese to simplified Chinese using OpenCC."""
    try:
        import opencc
        if not hasattr(t2s_convert, "_converter"):
            t2s_convert._converter = opencc.OpenCC("t2s")
        return t2s_convert._converter.convert(text)
    except ImportError:
        log("  [WARN] opencc not installed, skipping t2s conversion")
        return text


# ============================================================
# Model Management
# ============================================================

_model_cache = {}


def _patch_scaled_linear():
    """Monkey-patch ScaledLinear to support quantization for Gemma4 4-bit models."""
    import math
    import mlx.core as mx
    import mlx.nn as nn
    from mlx.nn.layers.quantized import _defaults_for_mode
    from mlx_vlm.models.gemma4.language import ScaledLinear

    if hasattr(ScaledLinear, "_patched"):
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


def load_model(model_id: str):
    global _model_cache
    if model_id in _model_cache:
        return _model_cache[model_id]

    _patch_scaled_linear()

    log(f"\nLoading model: {model_id}")
    t0 = time.time()
    from mlx_vlm.utils import load
    model, processor = load(model_id)
    elapsed = time.time() - t0
    log(f"Model loaded in {elapsed:.1f}s")

    _model_cache[model_id] = (model, processor)
    return model, processor


def transcribe(model, processor, audio_path: str, prompt_text: str, max_tokens: int = 500) -> dict:
    """Run Gemma4 end-to-end: audio -> clean transcript."""
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
        }
    except Exception as e:
        elapsed = time.time() - t0
        return {
            "text": "",
            "latency": round(elapsed, 3),
            "error": str(e),
        }


# ============================================================
# Experiment Runner
# ============================================================

def run_e2e_experiment(model, processor, model_key: str, prompt_name: str, prompt_text: str) -> dict:
    """Run end-to-end ASR+polish experiment on all regression cases."""
    with open(CASES_PATH) as f:
        suite = json.load(f)

    results = {
        "engine": f"gemma4-e2e-{model_key}",
        "model": MODELS[model_key],
        "prompt_name": prompt_name,
        "prompt_text": prompt_text,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "cases": [],
        "summary": {},
    }

    total_sim = 0
    total_sim_raw = 0  # before t2s
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

        # Always apply t2s post-processing
        raw_output = r["text"]
        output_t2s = t2s_convert(raw_output)

        gt = case["ground_truth"]
        sim = char_similarity(gt, output_t2s)
        sim_raw = char_similarity(gt, raw_output)
        kw_hits, kw_total = keyword_score(output_t2s, case.get("keywords", []))
        hallucinated = is_hallucination(output_t2s)

        case_result = {
            "id": case["id"],
            "similarity": round(sim, 3),
            "similarity_raw": round(sim_raw, 3),
            "t2s_delta": round(sim - sim_raw, 3),
            "keyword_hits": kw_hits,
            "keyword_total": kw_total,
            "keyword_score": round(kw_hits / max(kw_total, 1), 3),
            "hallucination": hallucinated,
            "latency": r["latency"],
            "output_raw": raw_output[:300],
            "output_t2s": output_t2s[:300],
            "ground_truth": gt[:300],
            "error": r["error"],
        }
        results["cases"].append(case_result)

        total_sim += sim
        total_sim_raw += sim_raw
        total_kw_hits += kw_hits
        total_kw_total += kw_total
        total_hallucinations += 1 if hallucinated else 0
        total_latency += r["latency"]
        n += 1

        marker = "HALLUC" if hallucinated else ("GOOD" if sim > 0.8 else ("OK" if sim > 0.6 else "LOW"))
        log(f"    {marker} sim={sim:.3f} (raw={sim_raw:.3f}, t2s_delta={sim-sim_raw:+.3f}) kw={kw_hits}/{kw_total} {r['latency']:.2f}s")
        log(f"    output: {output_t2s[:120]}")

    avg_sim = total_sim / max(n, 1)
    avg_sim_raw = total_sim_raw / max(n, 1)

    results["summary"] = {
        "total_cases": n,
        "avg_similarity": round(avg_sim, 3),
        "avg_similarity_raw": round(avg_sim_raw, 3),
        "t2s_improvement": round(avg_sim - avg_sim_raw, 3),
        "keyword_accuracy": round(total_kw_hits / max(total_kw_total, 1), 3),
        "hallucination_count": total_hallucinations,
        "hallucination_rate": round(total_hallucinations / max(n, 1), 3),
        "total_latency": round(total_latency, 2),
        "avg_latency": round(total_latency / max(n, 1), 3),
        "vs_qwen3": round(avg_sim - BASELINE_QWEN3_SIM, 3),
        "vs_gemma4_4b_t2s": round(avg_sim - BASELINE_GEMMA4_4B_T2S_SIM, 3),
    }

    return results


# ============================================================
# Evolution Log
# ============================================================

def append_evolution_log(all_results: list, model_key: str, gen_label: str):
    """Append results to evolution log."""
    existing = ""
    if LOG_PATH.exists():
        with open(LOG_PATH) as f:
            existing = f.read()

    lines = [
        "",
        "---",
        "",
        f"## {gen_label}: End-to-End ASR+Polish ({model_key.upper()})",
        f"",
        f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"Model: {MODELS[model_key]}",
        f"Approach: Single model, one-pass ASR+polish (no Qwen3 dependency)",
        f"Post-processing: OpenCC t2s on all outputs",
        f"",
        f"### Baselines (human-annotated GT)",
        f"- Qwen3 raw: sim={BASELINE_QWEN3_SIM}, kw={BASELINE_QWEN3_KW}",
        f"- Gemma4 4B + t2s (prev SOTA): sim={BASELINE_GEMMA4_4B_T2S_SIM}, kw={BASELINE_GEMMA4_4B_T2S_KW}",
        f"",
    ]

    best_sim = 0
    best_prompt = None

    for results in all_results:
        s = results["summary"]
        prompt_name = results["prompt_name"]

        if s["avg_similarity"] > BASELINE_QWEN3_SIM:
            verdict = "BEATS QWEN3!"
        elif s["avg_similarity"] > BASELINE_GEMMA4_4B_T2S_SIM:
            verdict = "New single-model SOTA"
        elif s["avg_similarity"] > BASELINE_GEMMA4_4B_T2S_SIM - 0.01:
            verdict = "Comparable to prev SOTA"
        else:
            verdict = "Below prev SOTA"

        lines.extend([
            f"### {prompt_name}",
            f"- Prompt: \"{results['prompt_text'][:150]}\"",
            f"- Score: sim={s['avg_similarity']:.3f} (raw={s['avg_similarity_raw']:.3f}, t2s+{s['t2s_improvement']:.3f}), kw={s['keyword_accuracy']:.3f}, hallucination={s['hallucination_count']}/{s['total_cases']}",
            f"- Avg Latency: {s['avg_latency']:.3f}s",
            f"- vs Qwen3 (sim={BASELINE_QWEN3_SIM}): {s['vs_qwen3']:+.3f}",
            f"- vs prev SOTA (sim={BASELINE_GEMMA4_4B_T2S_SIM}): {s['vs_gemma4_4b_t2s']:+.3f}",
            f"- Verdict: {verdict}",
            f"",
            f"Per-case results:",
        ])
        for c in results["cases"]:
            halluc_tag = " HALLUC" if c.get("hallucination") else ""
            lines.append(
                f"- {c['id']}: sim={c['similarity']:.3f} (raw={c['similarity_raw']:.3f}) "
                f"kw={c['keyword_hits']}/{c['keyword_total']}{halluc_tag}"
            )
            lines.append(f"  output: {c['output_t2s'][:120]}")
        lines.append("")

        if s["avg_similarity"] > best_sim:
            best_sim = s["avg_similarity"]
            best_prompt = prompt_name

    # Summary table
    lines.extend([
        f"### Summary Table ({model_key.upper()})",
        f"",
        f"| Prompt | Avg Sim | Raw Sim | t2s+ | Kw Acc | vs Qwen3 | vs Prev SOTA | Verdict |",
        f"|--------|---------|---------|------|--------|----------|--------------|---------|",
    ])
    for results in all_results:
        s = results["summary"]
        if s["avg_similarity"] > BASELINE_QWEN3_SIM:
            verdict = "BEATS QWEN3"
        elif s["avg_similarity"] > BASELINE_GEMMA4_4B_T2S_SIM:
            verdict = "New SOTA"
        else:
            verdict = "Below"
        lines.append(
            f"| {results['prompt_name']} | {s['avg_similarity']:.3f} | {s['avg_similarity_raw']:.3f} "
            f"| +{s['t2s_improvement']:.3f} | {s['keyword_accuracy']:.3f} "
            f"| {s['vs_qwen3']:+.3f} | {s['vs_gemma4_4b_t2s']:+.3f} | {verdict} |"
        )
    lines.extend([
        f"",
        f"Best prompt: {best_prompt} (sim={best_sim:.3f})",
        f"",
    ])

    with open(LOG_PATH, "w") as f:
        f.write(existing + "\n".join(lines))
    log(f"\nEvolution log updated: {LOG_PATH}")


# ============================================================
# Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="Gemma4 End-to-End ASR+Polish Experiment")
    parser.add_argument(
        "--model", choices=["4b", "2b"], default="4b",
        help="Model size: 4b (default) or 2b",
    )
    parser.add_argument(
        "--prompt", default="all",
        help="Prompt variant to test (or 'all' for all prompts). Use comma-separated for multiple.",
    )
    args = parser.parse_args()

    model_key = args.model
    model_id = MODELS[model_key]

    # Select prompts
    if args.prompt == "all":
        prompts = E2E_PROMPTS
    else:
        prompt_names = [p.strip() for p in args.prompt.split(",")]
        prompts = {}
        for pn in prompt_names:
            if pn in E2E_PROMPTS:
                prompts[pn] = E2E_PROMPTS[pn]
            else:
                log(f"Unknown prompt: {pn}. Available: {list(E2E_PROMPTS.keys())}")
                sys.exit(1)

    gen_label = "Generation 4" if model_key == "4b" else "Generation 5"

    log(f"{'=' * 72}")
    log(f"Gemma 4 End-to-End ASR+Polish Experiment ({gen_label})")
    log(f"Model: {model_id}")
    log(f"Prompts: {list(prompts.keys())}")
    log(f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    log(f"Baselines: Qwen3 sim={BASELINE_QWEN3_SIM}, Gemma4-4B-t2s sim={BASELINE_GEMMA4_4B_T2S_SIM}")
    log(f"{'=' * 72}")

    # Load model
    try:
        model, processor = load_model(model_id)
    except Exception as e:
        log(f"\nFAILED to load model: {e}")
        import traceback
        traceback.print_exc()
        return

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    all_results = []

    for prompt_name, prompt_text in prompts.items():
        log(f"\n{'=' * 72}")
        log(f"Testing: {prompt_name}")
        log(f"Prompt: \"{prompt_text[:150]}\"")
        log(f"{'=' * 72}")

        results = run_e2e_experiment(model, processor, model_key, prompt_name, prompt_text)
        all_results.append(results)

        s = results["summary"]
        log(f"\n  Summary for {prompt_name}:")
        log(f"    Avg Similarity:     {s['avg_similarity']:.3f} (raw={s['avg_similarity_raw']:.3f}, t2s+{s['t2s_improvement']:.3f})")
        log(f"    Keyword Accuracy:   {s['keyword_accuracy']:.3f}")
        log(f"    Hallucinations:     {s['hallucination_count']}/{s['total_cases']}")
        log(f"    Avg Latency:        {s['avg_latency']:.3f}s")
        log(f"    vs Qwen3:           {s['vs_qwen3']:+.3f}")
        log(f"    vs prev SOTA:       {s['vs_gemma4_4b_t2s']:+.3f}")

        # Save individual result
        ts = time.strftime("%Y%m%d_%H%M%S")
        path = RESULTS_DIR / f"gemma4_e2e_{model_key}_{prompt_name}_{ts}.json"
        with open(path, "w") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        log(f"  Saved: {path}")

    # Final summary
    log(f"\n{'=' * 72}")
    log(f"FINAL RESULTS ({gen_label})")
    log(f"{'=' * 72}")
    log(f"{'Prompt':<30} {'Sim':>6} {'Raw':>6} {'t2s+':>6} {'KW':>6} {'vs Q3':>8} {'vs SOTA':>8} {'Lat':>6}")
    log(f"{'-' * 90}")
    best_sim = 0
    best_name = None
    for r in all_results:
        s = r["summary"]
        marker = " ***" if s["avg_similarity"] > BASELINE_QWEN3_SIM else (" *" if s["avg_similarity"] > BASELINE_GEMMA4_4B_T2S_SIM else "")
        log(
            f"{r['prompt_name']:<30} {s['avg_similarity']:>6.3f} {s['avg_similarity_raw']:>6.3f} "
            f"+{s['t2s_improvement']:>5.3f} {s['keyword_accuracy']:>6.3f} "
            f"{s['vs_qwen3']:>+8.3f} {s['vs_gemma4_4b_t2s']:>+8.3f} {s['avg_latency']:>5.2f}s{marker}"
        )
        if s["avg_similarity"] > best_sim:
            best_sim = s["avg_similarity"]
            best_name = r["prompt_name"]

    log(f"\nBest: {best_name} (sim={best_sim:.3f})")
    if best_sim > BASELINE_QWEN3_SIM:
        log(f"  >>> BEATS QWEN3 by {best_sim - BASELINE_QWEN3_SIM:+.3f}!")
    elif best_sim > BASELINE_GEMMA4_4B_T2S_SIM:
        log(f"  >>> New single-model SOTA by {best_sim - BASELINE_GEMMA4_4B_T2S_SIM:+.3f}")
    else:
        log(f"  >>> Below prev SOTA by {best_sim - BASELINE_GEMMA4_4B_T2S_SIM:+.3f}")

    # Append to evolution log
    append_evolution_log(all_results, model_key, gen_label)


if __name__ == "__main__":
    main()
