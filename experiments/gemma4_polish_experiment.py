#!/usr/bin/env python3
"""
Gemma 4 Audio-Aware Polish Experiment
======================================

Core hypothesis: Gemma4 receives BOTH the raw audio AND Qwen3's rough transcription,
then corrects ASR errors because it can hear what was actually said.

Current pipeline: Audio → Qwen3-ASR(transcription) → Qwen3-LLM(text-only polish) → output
New pipeline:     Audio → Qwen3-ASR(transcription) → Gemma4(audio+text → polish) → output

Evolution targets:
  - Beat Qwen3 raw (sim=0.792) → this approach has value
  - Beat Gemma4 ASR only (sim=0.581) → at least better than pure Gemma4 ASR

Usage:
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_polish_experiment.py
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_polish_experiment.py --model 2b
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_polish_experiment.py --model 4b
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_polish_experiment.py --prompt precise
    /opt/homebrew/Caskroom/miniforge/base/bin/python3 experiments/gemma4_polish_experiment.py --prompt all
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
HISTORY_PATH = Path.home() / "Library" / "Application Support" / "Talk" / "history.json"
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
BASELINE_GEMMA4_ASR_SIM = 0.581  # Gemma4 4B ASR-only best (gen2a_precise)
BASELINE_GEMMA4_ASR_KW = 0.469

# ============================================================
# Polish Prompts
# ============================================================

POLISH_PROMPTS = {
    "polish_v1": (
        "以下是语音识别系统的粗转录结果，可能有错字、同音字错误或英文词识别错误。\n"
        "请根据音频内容修正转录文本。只输出修正后的文本，不要解释。\n\n"
        "粗转录：{qwen3_output}"
    ),
    "polish_v2_concise": (
        "修正以下语音转录中的错误：{qwen3_output}"
    ),
    "polish_v3_keywords": (
        "以下是语音识别系统的粗转录结果，可能包含同音字错误。"
        "请对照音频修正文本，可能包含的术语：Review, SOTA, benchmark, Gemma 4, Agent, CLI, SDK。\n"
        "只输出修正后的文本。\n\n"
        "粗转录：{qwen3_output}"
    ),
    "polish_v4_english": (
        "Correct the following speech transcription errors based on the audio. "
        "Fix homophone errors, preserve English words, and output simplified Chinese. "
        "Only output the corrected text, no explanation.\n\n"
        "Rough transcription: {qwen3_output}"
    ),
    "polish_v5_precise": (
        "你是一个语音转录校对助手。下面是ASR系统的粗转录和原始音频。\n"
        "请根据音频修正转录中的错误，包括：\n"
        "1. 同音字错误（如'日税表'应为'Review'）\n"
        "2. 英文专有名词拼写（如SOTA, benchmark, Agent SDK）\n"
        "3. 多余或遗漏的字\n"
        "使用简体中文，保留英文原词。只输出修正后的文本。\n\n"
        "粗转录：{qwen3_output}"
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


def load_qwen3_raw_texts() -> dict:
    """Load Qwen3 raw transcriptions from Talk's history.json, keyed by audio filename."""
    if not HISTORY_PATH.exists():
        log(f"  [WARN] history.json not found at {HISTORY_PATH}")
        return {}
    with open(HISTORY_PATH) as f:
        history = json.load(f)
    return {
        item.get("audioFilePath", ""): item.get("rawText", "")
        for item in history
        if item.get("audioFilePath")
    }


# ============================================================
# Model Management
# ============================================================

_model_cache = {}  # keyed by model_id


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


def polish_with_audio(model, processor, audio_path: str, prompt_text: str, max_tokens: int = 500) -> dict:
    """Run Gemma4 polish: audio + Qwen3 rough text -> corrected text."""
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

def run_polish_experiment(model, processor, model_key: str, prompt_name: str, prompt_template: str) -> dict:
    """Run polish experiment on all regression cases."""
    with open(CASES_PATH) as f:
        suite = json.load(f)

    qwen3_raw = load_qwen3_raw_texts()

    results = {
        "engine": f"gemma4-polish-{model_key}",
        "model": MODELS[model_key],
        "prompt_name": prompt_name,
        "prompt_template": prompt_template,
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

        # Get Qwen3 raw transcription for this case
        raw_text = qwen3_raw.get(case["file"], "")
        if not raw_text:
            log(f"  SKIP {case['id']}: no Qwen3 raw text in history")
            continue

        # Format prompt with Qwen3 output
        prompt_text = prompt_template.format(qwen3_output=raw_text)

        log(f"  {case['id']} ({case['duration']}s, {case['lang']})...")
        log(f"    qwen3_raw: {raw_text[:100]}")

        r = polish_with_audio(model, processor, audio_path, prompt_text)

        # Apply t2s post-processing (always, since Gemma4 often outputs traditional)
        raw_output = r["text"]
        polished = t2s_convert(raw_output)

        gt = case["ground_truth"]
        sim = char_similarity(gt, polished)
        sim_before_t2s = char_similarity(gt, raw_output)
        sim_qwen3_raw = char_similarity(gt, raw_text)
        kw_hits, kw_total = keyword_score(polished, case.get("keywords", []))
        kw_hits_qwen3, _ = keyword_score(raw_text, case.get("keywords", []))
        hallucinated = is_hallucination(polished)

        case_result = {
            "id": case["id"],
            "similarity": round(sim, 3),
            "similarity_before_t2s": round(sim_before_t2s, 3),
            "similarity_qwen3_raw": round(sim_qwen3_raw, 3),
            "similarity_delta_vs_qwen3": round(sim - sim_qwen3_raw, 3),
            "keyword_hits": kw_hits,
            "keyword_total": kw_total,
            "keyword_score": round(kw_hits / max(kw_total, 1), 3),
            "keyword_hits_qwen3": kw_hits_qwen3,
            "hallucination": hallucinated,
            "latency": r["latency"],
            "qwen3_raw": raw_text[:300],
            "output_raw": raw_output[:300],
            "output_t2s": polished[:300],
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

        delta = sim - sim_qwen3_raw
        marker = "HALLUC" if hallucinated else ("BETTER" if delta > 0.01 else ("SAME" if abs(delta) <= 0.01 else "WORSE"))
        log(f"    {marker} sim={sim:.3f} (qwen3={sim_qwen3_raw:.3f}, delta={delta:+.3f}) kw={kw_hits}/{kw_total} {r['latency']:.2f}s")
        log(f"    output: {polished[:120]}")

    results["summary"] = {
        "total_cases": n,
        "avg_similarity": round(total_sim / max(n, 1), 3),
        "keyword_accuracy": round(total_kw_hits / max(total_kw_total, 1), 3),
        "hallucination_count": total_hallucinations,
        "hallucination_rate": round(total_hallucinations / max(n, 1), 3),
        "total_latency": round(total_latency, 2),
        "avg_latency": round(total_latency / max(n, 1), 3),
        "vs_qwen3_raw_sim": round(total_sim / max(n, 1) - BASELINE_QWEN3_SIM, 3),
        "vs_gemma4_asr_sim": round(total_sim / max(n, 1) - BASELINE_GEMMA4_ASR_SIM, 3),
    }

    return results


# ============================================================
# Evolution Log
# ============================================================

def append_evolution_log(all_results: list, model_key: str):
    """Append polish experiment results to evolution log."""
    existing = ""
    if LOG_PATH.exists():
        with open(LOG_PATH) as f:
            existing = f.read()

    lines = [
        "",
        "---",
        "",
        f"## Generation 4: Audio-Aware Polish Experiment ({model_key.upper()})",
        f"",
        f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"Model: {MODELS[model_key]}",
        f"Approach: Qwen3 ASR + Gemma4 audio-aware polish (audio + rough text -> corrected text)",
        f"Post-processing: OpenCC t2s on all outputs",
        f"",
        f"### Baselines (human-annotated GT)",
        f"- Qwen3 raw: sim={BASELINE_QWEN3_SIM}, kw={BASELINE_QWEN3_KW}",
        f"- Gemma4 4B ASR-only: sim={BASELINE_GEMMA4_ASR_SIM}, kw={BASELINE_GEMMA4_ASR_KW}",
        f"",
    ]

    best_sim = 0
    best_prompt = None

    for results in all_results:
        s = results["summary"]
        prompt_name = results["prompt_name"]

        delta_qwen3 = s["vs_qwen3_raw_sim"]
        delta_gemma4 = s["vs_gemma4_asr_sim"]

        if s["avg_similarity"] > BASELINE_QWEN3_SIM:
            verdict = "BEATS QWEN3 -- this approach has value!"
        elif s["avg_similarity"] > BASELINE_GEMMA4_ASR_SIM:
            verdict = "Beats Gemma4 ASR, but not Qwen3"
        else:
            verdict = "Worse than Gemma4 ASR-only"

        lines.extend([
            f"### {prompt_name}",
            f"- Prompt: \"{results['prompt_template'][:150]}\"",
            f"- Score: sim={s['avg_similarity']:.3f}, kw={s['keyword_accuracy']:.3f}, hallucination={s['hallucination_count']}/{s['total_cases']}",
            f"- Avg Latency: {s['avg_latency']:.3f}s",
            f"- vs Qwen3 raw (sim={BASELINE_QWEN3_SIM}): {delta_qwen3:+.3f}",
            f"- vs Gemma4 ASR (sim={BASELINE_GEMMA4_ASR_SIM}): {delta_gemma4:+.3f}",
            f"- Verdict: {verdict}",
            f"",
            f"Per-case results:",
        ])
        for c in results["cases"]:
            delta = c["similarity_delta_vs_qwen3"]
            marker = "BETTER" if delta > 0.01 else ("SAME" if abs(delta) <= 0.01 else "WORSE")
            lines.append(
                f"- {c['id']}: sim={c['similarity']:.3f} (qwen3={c['similarity_qwen3_raw']:.3f} {delta:+.3f} {marker}) "
                f"kw={c['keyword_hits']}/{c['keyword_total']}"
            )
            lines.append(f"  qwen3_raw: {c['qwen3_raw'][:100]}")
            lines.append(f"  polished:  {c['output_t2s'][:100]}")
        lines.append("")

        if s["avg_similarity"] > best_sim:
            best_sim = s["avg_similarity"]
            best_prompt = prompt_name

    # Summary table
    lines.extend([
        f"### Polish Experiment Summary ({model_key.upper()})",
        f"",
        f"| Prompt | Avg Sim | Kw Acc | vs Qwen3 | vs Gemma4 ASR | Verdict |",
        f"|--------|---------|--------|----------|---------------|---------|",
    ])
    for results in all_results:
        s = results["summary"]
        if s["avg_similarity"] > BASELINE_QWEN3_SIM:
            verdict = "BEATS QWEN3"
        elif s["avg_similarity"] > BASELINE_GEMMA4_ASR_SIM:
            verdict = "Beats G4 ASR"
        else:
            verdict = "Below G4 ASR"
        lines.append(
            f"| {results['prompt_name']} | {s['avg_similarity']:.3f} | {s['keyword_accuracy']:.3f} "
            f"| {s['vs_qwen3_raw_sim']:+.3f} | {s['vs_gemma4_asr_sim']:+.3f} | {verdict} |"
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
    parser = argparse.ArgumentParser(description="Gemma4 Audio-Aware Polish Experiment")
    parser.add_argument(
        "--model", choices=["4b", "2b"], default="4b",
        help="Model size: 4b (default) or 2b",
    )
    parser.add_argument(
        "--prompt", default="all",
        help="Prompt variant to test (or 'all' for all prompts)",
    )
    args = parser.parse_args()

    model_key = args.model
    model_id = MODELS[model_key]

    # Select prompts
    if args.prompt == "all":
        prompts = POLISH_PROMPTS
    elif args.prompt in POLISH_PROMPTS:
        prompts = {args.prompt: POLISH_PROMPTS[args.prompt]}
    else:
        log(f"Unknown prompt: {args.prompt}. Available: {list(POLISH_PROMPTS.keys())}")
        sys.exit(1)

    log(f"{'=' * 72}")
    log(f"Gemma 4 Audio-Aware Polish Experiment")
    log(f"Model: {model_id}")
    log(f"Prompts: {list(prompts.keys())}")
    log(f"Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    log(f"Baselines: Qwen3 raw sim={BASELINE_QWEN3_SIM}, Gemma4 ASR sim={BASELINE_GEMMA4_ASR_SIM}")
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

    for prompt_name, prompt_template in prompts.items():
        log(f"\n{'=' * 72}")
        log(f"Testing: {prompt_name}")
        log(f"Template: \"{prompt_template[:120]}...\"")
        log(f"{'=' * 72}")

        results = run_polish_experiment(model, processor, model_key, prompt_name, prompt_template)
        all_results.append(results)

        s = results["summary"]
        log(f"\n  Summary for {prompt_name}:")
        log(f"    Avg Similarity:     {s['avg_similarity']:.3f}")
        log(f"    Keyword Accuracy:   {s['keyword_accuracy']:.3f}")
        log(f"    Hallucinations:     {s['hallucination_count']}/{s['total_cases']}")
        log(f"    Avg Latency:        {s['avg_latency']:.3f}s")
        log(f"    vs Qwen3 raw:       {s['vs_qwen3_raw_sim']:+.3f}")
        log(f"    vs Gemma4 ASR only: {s['vs_gemma4_asr_sim']:+.3f}")

        # Save individual result
        ts = time.strftime("%Y%m%d_%H%M%S")
        path = RESULTS_DIR / f"gemma4_polish_{model_key}_{prompt_name}_{ts}.json"
        with open(path, "w") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        log(f"  Saved: {path}")

    # Final summary
    log(f"\n{'=' * 72}")
    log(f"FINAL RESULTS")
    log(f"{'=' * 72}")
    log(f"{'Prompt':<25} {'Sim':>8} {'KW':>8} {'vs Qwen3':>10} {'vs G4 ASR':>10}")
    log(f"{'-' * 72}")
    for r in all_results:
        s = r["summary"]
        log(
            f"{r['prompt_name']:<25} {s['avg_similarity']:>8.3f} {s['keyword_accuracy']:>8.3f} "
            f"{s['vs_qwen3_raw_sim']:>+10.3f} {s['vs_gemma4_asr_sim']:>+10.3f}"
        )

    # Append to evolution log
    append_evolution_log(all_results, model_key)


if __name__ == "__main__":
    main()
