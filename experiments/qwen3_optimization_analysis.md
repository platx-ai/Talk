# Qwen3 ASR + LLM Pipeline Optimization Analysis

**Date**: 2026-04-03
**Baseline**: Qwen3-ASR raw output, avg_sim=0.792, kw=0.750
**Data**: `regression_results/qwen3_20260406_215947.json` vs `regression_cases.json`

## Error Taxonomy

| Case | sim | Error Type | ASR Output | Ground Truth | Fix Layer |
|------|-----|-----------|------------|-------------|-----------|
| en_short_01 | 0.000 | Language misdetection | "I think it can be used." | "我觉得可以用。" | ASR setting |
| en_short_02 | 0.154 | Language misdetection | "Fei said, \"The car owner...\"" | "飞书的 chanel 怎么不工作了？" | ASR setting |
| zh_medium_04 | 0.796 | Tech term phonetic error | "半尺寸麦克" | "benchmark" | Vocab + LLM |
| zh_long_01 | 0.853 | Tech term phonetic error | "JMAP四", "T Mate" | "Gemma 4", "teamate" | Vocab + LLM |
| zh_medium_01 | 0.895 | Tech term phonetic error | "日税表" | "Review" | Vocab + LLM |
| zh_short_02 | 0.900 | Near-homophone error | "更新一把" | "更新一版" | Vocab + LLM |
| zh_medium_02 | 0.929 | Tech term phonetic error | "搜塔" | "SOTA" | Vocab + LLM |
| mixed_medium_01 | 0.975 | Spelling error | "Cloud Agent SDK" | "Claude Agent SDK" | Vocab (already exists) |

## Simulation Results

### Direction 1: Vocabulary Corrections via LLM Polish

Simulated adding missing corrections as string replacements (mimicking what LLM polish does with `correctionContext`):

| Correction | Case | sim Before | sim After | Delta |
|-----------|------|-----------|----------|-------|
| 更新一把 -> 更新一版 | zh_short_02 | 0.900 | 1.000 | +0.100 |
| 日税表 -> Review | zh_medium_01 | 0.895 | 0.981 | +0.086 |
| 搜塔 -> SOTA | zh_medium_02 | 0.929 | 0.982 | +0.053 |
| 半尺寸麦克 -> benchmark, 例如->比如 | zh_medium_04 | 0.796 | 0.980 | +0.184 |
| JMAP四 -> Gemma 4, T Mate -> teamate | zh_long_01 | 0.853 | 0.963 | +0.110 |
| Cloud Agent SDK -> Claude Agent SDK | mixed_medium_01 | 0.975 | 1.000 | +0.025 |

**Result: avg_sim = 0.841 (+0.049)**

Note: `Cloud Agent SDK -> Claude Agent SDK` is already in vocabulary.json but the regression test measures raw ASR output (no LLM polish). If polish is applied, this case should already be fixed.

### Direction 2: Language Detection Fix

The 2 language misdetection cases (en_short_01, en_short_02) are the largest source of score loss, contributing -1.638 total similarity. These are Chinese audio that Qwen3 ASR transcribed as English.

If `asrLanguage` is changed from `auto` to `zh`:
- en_short_01: 0.000 -> ~1.000 (simple sentence, likely correct)
- en_short_02: 0.154 -> ~0.914 (assumes "channel" -> "chanel" minor diff)

**Result: avg_sim = 0.985 (+0.193 from baseline)**

### Direction 3: Combined Impact Breakdown

```
Baseline (Qwen3 raw):           0.792
+ Vocab corrections (LLM):      0.841  (+0.049)
+ Language fix (ASR setting):    0.985  (+0.144 additional)
Total potential improvement:             +0.193
```

## Current Vocabulary Coverage

Existing vocabulary.json has 16 entries. **None** of the needed corrections are present:

| Needed | Status |
|--------|--------|
| 日税表 -> Review | MISSING |
| 搜塔 -> SOTA | MISSING |
| 半尺寸麦克 -> benchmark | MISSING |
| JMAP四 -> Gemma 4 | MISSING |
| T Mate -> teamate | MISSING |
| 更新一把 -> 更新一版 | MISSING |
| Cloud Agent SDK -> Claude Agent SDK | EXISTS (freq=4) |

## Recommendations (Priority Order)

### 1. [HIGH] Fix Language Detection (est. +0.144 avg_sim)

**Option A**: Change default `asrLanguage` from `.auto` to `.chinese`
- Pro: Fixes 2 worst cases immediately
- Con: Breaks actual English audio input
- Verdict: Bad for general use

**Option B**: Post-ASR language validation
- Detect output language vs expected language
- If mismatch, re-run ASR with forced language
- Pro: Handles edge cases without breaking defaults
- Con: Adds latency for retry cases

**Option C**: Improve ASR prompt/config for auto detection
- Qwen3-ASR may have a language hint parameter
- Check if `language: "auto"` can be replaced with `language: "zh,en"` (prefer zh)
- Best balance of correctness and flexibility

### 2. [MEDIUM] Add Vocabulary Entries (est. +0.049 avg_sim)

Add these to vocabulary.json (or let the auto-hotword-learning system learn them):
```json
{"word": "日税表", "correctedForm": "Review"}
{"word": "搜塔", "correctedForm": "SOTA"}
{"word": "半尺寸麦克", "correctedForm": "benchmark"}
{"word": "JMAP四", "correctedForm": "Gemma 4"}
{"word": "T Mate", "correctedForm": "teamate"}
{"word": "更新一把", "correctedForm": "更新一版"}
```

**Important caveat**: These corrections are specific to the test audio. Adding them to vocabulary.json would improve regression scores but amounts to overfitting the test set. The auto-hotword-learning system (described in `docs/DESIGN-auto-hotword-learning.md`) is the correct long-term mechanism -- it learns from user edits organically.

However, adding *generic* tech terms like `SOTA`, `benchmark`, `Review` (as code review) is legitimate since they're common in the user's domain.

### 3. [LOW] Prompt Enhancement (uncertain impact)

The current prompt already has rule 8: "结合上下文理解专有名词（技术术语 ASR 容易听错，如 "la laam" -> "LLM"）"

Could strengthen to:
```
8. 结合上下文理解专有名词。ASR 经常把英文技术术语听错为中文谐音词，例如：
   - "la laam" -> "LLM"
   - 中文里突然出现不合语境的词，考虑是否是英文术语的谐音
```

**Risk**: This is prompt-level guidance, not deterministic. LLM may or may not follow it. Vocabulary corrections are more reliable.

### 4. [HARDLINE] Do NOT inject test-specific keywords into prompt

Per zh_medium_03 ground truth: "有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词...这样的是一个作弊的行为。"

Adding "SOTA", "benchmark", "Gemma 4" directly to the system prompt is cheating. The vocabulary system is the correct mechanism.

## Achievable Target

| Scenario | avg_sim | kw_accuracy |
|----------|---------|-------------|
| Current baseline | 0.792 | 0.750 |
| + Vocab only (realistic) | 0.841 | 0.900 |
| + Lang fix (optimistic) | 0.985 | ~0.975 |
| Realistic target | **0.84-0.87** | **0.85-0.90** |

The realistic target without ASR-layer changes is **~0.84** (vocab corrections through LLM polish). With language detection improvement at the ASR layer, the ceiling is **~0.98**.
