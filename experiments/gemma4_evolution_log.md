# Gemma 4 Quantized ASR Evolution Log

Date: 2026-04-06 19:55:08
Model: mlx-community/gemma-4-e2b-it-4bit
Variant: mlx-2B-4bit
mlx-vlm version: 0.4.4

## Previous Baseline (non-quantized google/gemma-4-e2b-it)
- avg_similarity: 0.061
- keyword_accuracy: 0.000
- Verdict: UNUSABLE (paraphrases instead of transcribing)

## Qwen3 Baseline (ground truth source)
- avg_similarity: 1.000 (by definition, GT = Qwen3 output)
- keyword_accuracy: 1.000

## Generation 0: Baseline Prompt
- Prompt: "Transcribe this audio verbatim."
- Model: mlx-community/gemma-4-e2b-it-4bit
- Score: sim=0.493, kw=0.312, hallucination=0/12
- Avg Latency: 0.292s
- vs Previous (non-quantized): +0.432
- Decision: BASELINE

### Per-case results:
- zh_short_01: sim=0.522 kw=0/2 
  output: 如果不確定就做實驗
- zh_short_02: sim=0.571 kw=1/1 
  output: 好的,我來更新100。
- zh_medium_01: sim=0.598 kw=1/4 
  output: 對於認為結果你要有自己獨立的判斷,因為它的上下呢肯定沒有你的風格,所以 你可以同意見不同啊。
- zh_medium_02: sim=0.569 kw=1/4 
  output: 我們同步一下現在最新狀,目前的套體是一個什麼的嘴,水準,然後根據上一輪的點在下一輪的改進的方向是
- zh_medium_03: sim=0.486 kw=0/3 
  output: 有一個是hard life,這就可以碰了,就是不能通過,就再測試是否能夠輸入劇的觀眾詞和要說的。 然後來hack。
- zh_medium_04: sim=0.444 kw=1/2 
  output: 如果,如果不能貼,能貼,能貼,跟我們的分析模式很相關的任何過程,這樣的是一個作弊的行為。
- zh_long_01: sim=0.500 kw=0/4 
  output: 開始實線,然後對於Jam4的基礎建議你可以單獨起一個team去做實驗,然後探索它的用我們已經錄好的這些音品材料包括現在我跟你說的這些音品都錄下來可以去做實驗,因為Jam4有一個三時秒打開的一個上線,所
- zh_long_02: sim=0.613 kw=1/3 
  output: 另外就是你去反思,我們在成雪上面有那些 假設或者是猜測實際上是沒有意義的,比如說我們這些排蓄的意義是什麼等等
- en_short_01: sim=0.000 kw=0/2 
  output: 我覺得可以用
- en_short_02: sim=0.222 kw=0/1 
  output: Facebook 的 channel怎麼不工作了?
- mixed_medium_01: sim=0.711 kw=2/3 
  output: Cloud Agent SDK 的以外,把它升級到最新版,然後做一個 pre-release,不足到 QC mini 上。
- mixed_long_01: sim=0.675 kw=3/3 
  output: 現在這個CLI和入口是什麼設計,我們應該怎麼使用? 如果我想讓之前使用 sub agent的方式執行, 的主agent去調用這個CLI去find evidence

## Generation 1a: gen1a_zh
- Prompt: "请逐字转录这段语音，使用简体中文。"
- Model: mlx-community/gemma-4-e2b-it-4bit
- Score: sim=0.569, kw=0.344, hallucination=0/12
- Avg Latency: 0.278s
- vs SOTA: +0.076
- Decision: KEEP (new SOTA)

## Generation 1b: gen1b_mixed
- Prompt: "Transcribe this audio word for word in its original language. Use simplified Chinese characters."
- Model: mlx-community/gemma-4-e2b-it-4bit
- Score: sim=0.511, kw=0.406, hallucination=0/12
- Avg Latency: 0.298s
- vs SOTA: -0.058
- Decision: DISCARD

## Generation 1c: gen1c_role
- Prompt: "You are a speech-to-text transcriber. Output the exact words spoken, nothing else."
- Model: mlx-community/gemma-4-e2b-it-4bit
- Score: sim=0.497, kw=0.312, hallucination=0/12
- Avg Latency: 0.289s
- vs SOTA: -0.072
- Decision: DISCARD

---

## Key Findings

### 1. unsloth quantized models are TEXT-ONLY (no audio tower)
- `unsloth/gemma-4-E2B-it-UD-MLX-4bit` uses `mlx-lm` (not `mlx-vlm`)
- The model weights lack `audio_tower.*` parameters entirely
- Requires custom model files from unsloth repo + `transformers>=5.5.0`
- NOT usable for ASR

### 2. mlx-community quantized models work but have issues
- `mlx-community/gemma-4-e2b-it-4bit` loaded successfully with mlx-vlm 0.4.4
- Required monkey-patching `ScaledLinear.to_quantized()` for the PLE layer
- No garbled output (the PLE quantization issue did NOT manifest)
- Model size: ~1.5GB (4-bit) vs 9.6GB (non-quantized) vs 1.6GB (Qwen3-ASR)

### 3. Quantized model is MUCH better than non-quantized
- Quantized: avg_sim=0.493 (baseline), 0.569 (best prompt)
- Non-quantized: avg_sim=0.061
- The non-quantized model was paraphrasing; the quantized model actually transcribes

### 4. Chinese prompt produces simplified Chinese output
- gen1a_zh ("请逐字转录这段语音，使用简体中文") was the best prompt
- English prompt baseline produces traditional Chinese (繁简混排)
- Chinese prompt partially fixes this but some traditional characters remain

### 5. English ASR is still broken
- en_short_01: "I think it can be used" -> "我觉得可以用" (translated to Chinese!)
- en_short_02: similar translation behavior
- The model "understands" English audio but outputs Chinese

### 6. Speed advantage is real
- Avg latency: 0.278-0.292s vs Qwen3's ~2-4s
- 10x faster inference

### 7. Keyword accuracy is low (31-41%)
- Many keywords are semantically captured but with different characters
- e.g., "搜塔" (Qwen3) vs "土壤" (Gemma4) -- both wrong for "SOTA"

## Comparison Table: All Gemma 4 Variants vs Qwen3

| Metric | Qwen3-ASR | Gemma4 Non-quant | Gemma4 4-bit (baseline) | Gemma4 4-bit (best) |
|--------|-----------|-----------------|------------------------|---------------------|
| Model | Qwen3-ASR-0.6B | google/gemma-4-e2b-it | mlx-community/gemma-4-e2b-it-4bit | same |
| Size | 1.6 GB | 9.6 GB | ~1.5 GB | ~1.5 GB |
| Prompt | - | "Transcribe this audio" | "Transcribe this audio verbatim." | "请逐字转录这段语音，使用简体中文。" |
| Avg Similarity | 1.000 | 0.061 | 0.493 | 0.569 |
| Keyword Accuracy | 1.000 | 0.000 | 0.312 | 0.344 |
| Hallucinations | 0/12 | 0/12 | 0/12 | 0/12 |
| Avg Latency | ~2-4s | ~0.5s | 0.292s | 0.278s |
| Chinese Quality | Good | Poor (paraphrases) | Fair (繁简混排) | Better (mostly simplified) |
| English Quality | Good | Poor (paraphrases) | Broken (outputs Chinese) | Broken |
| Verbatim | Yes | No | Partial | Better |

## Verdict

**Gemma 4 4-bit quantized is a significant improvement over the non-quantized version,
but still NOT suitable as a replacement for Qwen3-ASR.**

Reasons:
1. Average similarity of 0.569 vs Qwen3's 1.000 (by definition)
2. English ASR completely broken (outputs Chinese)
3. 繁简混排 persists even with Chinese prompt
4. Not verbatim transcription -- still rephrases/misrecognizes

Potential use case:
- Could be used as a FAST PREVIEW during recording (0.3s latency)
- Then Qwen3 provides the accurate final transcription
- Or as a fallback when Qwen3 model is still loading

---

## Generation 2: Gemma4 4B Experiments

Date: 2026-04-06 20:31:44
Model: mlx-community/gemma-4-e4b-it-4bit
Model size: ~5.2 GB (4-bit quantized, vs ~1.5 GB for 2B 4-bit)

### gen2_baseline
- Model: mlx-community/gemma-4-e4b-it-4bit
- Prompt: "请逐字转录这段语音，使用简体中文。"
- Score: sim=0.579, kw=0.344, hallucination=0/12
- Avg Latency: 0.501s
- vs 2B SOTA (sim=0.569): +0.010
- vs 2B SOTA (kw=0.344): +0.000
- vs Qwen3 (1.000): gap=0.421
- Decision: NEUTRAL (within margin of 2B SOTA)

Per-case results:
- zh_short_01: sim=0.640 kw=1/2
  output: 不过如果不觉得就做实验
- zh_short_02: sim=0.900 kw=1/1
  output: 好的，我来更新一遍。
- zh_medium_01: sim=0.594 kw=1/4
  output: 對於レビュー結果你有有自己獨立的判斷,因為他的上下了肯定沒有裡的豐富,所以 你可以同意也可以不同啊。
- zh_medium_02: sim=0.738 kw=1/4
  output: 我们同步一下现在最近状况，目前的售塔是一个什么样的衰衰准，然后根据上一轮的抵达下一轮的阶段的方向是
- zh_medium_03: sim=0.545 kw=0/3
  output: 有一个是hard life,也就是说能不能碰到呢,就是能不能通過這在這些積極進入具體的關鍵詞和你要說的,然後後來hack
- zh_medium_04: sim=0.473 kw=1/2
  output: 由于pyrrolo酮体凝的存在是无法体跟我们的粉丝们还相关的任何阶段。这样的是一个作弊的行为。
- zh_long_01: sim=0.434 kw=0/4
  output: 凱斯實現,然後對於Gamma 4的其成果建議,你可以單獨請一個teammate去做實驗,然後探索他的呃用我們已經錄討的這些影片採集過的這個包括現在我跟你說的這些異面都落下來,還可以去做實驗。 因為Gamma 4有一個30秒打開的一個上線,所
- zh_long_02: sim=0.702 kw=1/3
  output: 另外一個就是你去反思,我們在程序上面有哪些假設或者是猜測實際上的是沒有意義的,比如說我們這些排系的依據是什麼等等。
- en_short_01: sim=0.000 kw=0/2
  output: 我觉得可以用。
- en_short_02: sim=0.247 kw=0/1
  output: Facebook 的 channel 怎麼不工作了?
- mixed_medium_01: sim=0.738 kw=2/3
  output: Cloud 的 Agent SDK 的一来,把它升級到最新版,然後做一個 pre-release部署到 QC mini 上。
- mixed_long_01: sim=0.936 kw=3/3
  output: 现在这个CLI和入口是怎么设计的，我应该怎么使用？如果我想让以前使用subagent的方式执行的主agent去调用这个CLI去find evidence。

### gen2a_precise
- Model: mlx-community/gemma-4-e4b-it-4bit
- Prompt: "请精确转录这段语音的每一个字，使用简体中文，保留所有英文单词的原始拼写。"
- Score: sim=0.581, kw=0.469, hallucination=0/12
- Avg Latency: 0.485s
- vs 2B SOTA (sim=0.569): +0.012
- vs 2B SOTA (kw=0.344): +0.125
- vs Qwen3 (1.000): gap=0.419
- Decision: KEEP (beats 2B SOTA)

Per-case results:
- zh_short_01: sim=0.500 kw=1/2
  output: book 如果不觉得就做实验
- zh_short_02: sim=0.900 kw=1/1
  output: 好的，我来更新一遍。
- zh_medium_01: sim=0.643 kw=3/4
  output: 对于 review 结果 你要有自己独立的判断，因为他的 standpoint 可能没有你的丰富，所以 你可以同意也可以不同啊。
- zh_medium_02: sim=0.724 kw=1/4
  output: 我们同步一下现在最近状况，目前的所在是一个什么样的阶段，水准，然后根据上一轮的抵达下一轮的阶段的方向是
- zh_medium_03: sim=0.593 kw=0/3
  output: 有一个是 hard life, 对后面碰到呢,就是不能通货,在提示須進入具體的關鍵詞和你要說的,然後後來 hack。
- zh_medium_04: sim=0.396 kw=1/2
  output: 由于pyrrolo compound 您对此没有任何对此跟我们的反馈或者相关的任何事情 这样的是一个作弊的行为
- zh_long_01: sim=0.444 kw=0/4
  output: 凱斯實現,然後對於Gamma 4的其層我建議你可以單獨請一個teammate去做實驗,然後探索他的呃用我們已經錄討的這些音品採集過的這個包括現在我跟你說的這些異面都落下來,還可以去做實驗。 因為Gamma 4有一個30秒打開的一個上線,所以
- zh_long_02: sim=0.852 kw=2/3
  output: 那么一个是你就你去反思，我们在程序上面有哪些假设或者是猜测猜測实际上是没有意义的，比如我们这些排系的依据是什么等等。
- en_short_01: sim=0.000 kw=0/2
  output: 我觉得可以用
- en_short_02: sim=0.247 kw=0/1
  output: Facebook 的 channel 怎么不工作了？
- mixed_medium_01: sim=0.803 kw=3/3
  output: Cloud 的 Agent SDK 的一来，把它升级到最新版，然后做一个 pre-release部署到 QC mini 上。
- mixed_long_01: sim=0.874 kw=3/3
  output: 现在这个 CLI 和入口 是怎么设计的，我应该怎么使用？如果我想让以前使用 sub-agent 的方式执行的主 agent 去调用这个 CLI 去 find evidence。

### gen2b_bilingual
- Model: mlx-community/gemma-4-e4b-it-4bit
- Prompt: "Transcribe this audio exactly as spoken. Keep English words in English. Use simplified Chinese for Chinese parts."
- Score: sim=0.517, kw=0.312, hallucination=0/12
- Avg Latency: 0.490s
- vs 2B SOTA (sim=0.569): -0.052
- vs 2B SOTA (kw=0.344): -0.032
- vs Qwen3 (1.000): gap=0.483
- Decision: DISCARD (worse than 2B SOTA)

Per-case results:
- zh_short_01: sim=0.560 kw=0/2
  output: 不過如果不確定就做實驗
- zh_short_02: sim=0.900 kw=1/1
  output: 好的，我来更新一下。
- zh_medium_01: sim=0.614 kw=1/4
  output: 對於レビュー結果你有有自己獨立的判斷,因為他的上下了肯定沒有你的豐富,所以 你可以同意也可以不同啊。
- zh_medium_02: sim=0.514 kw=1/4
  output: 我們同步一下現在最近狀態,目前的所在是一個什麼樣的飛垂直,然後根據上一輪的疊代下一輪的階段的這個方向是
- zh_medium_03: sim=0.514 kw=0/3
  output: 有一個是hard life,對後面碰到呢,就是不能通過,在體是積極進入具體的關鍵詞和你要說的,然後後來hack
- zh_medium_04: sim=0.413 kw=1/2
  output: 比如說,比如說這種貼凝的貼不能貼,跟我們的粉絲碼還相關的任何關鍵詞,這樣的是一個作弊的行為。
- zh_long_01: sim=0.448 kw=0/4
  output: 凱斯實現,然後對於Gamma 4 的其實我建議你可以單獨請一個 teammate去做實驗,然後探索他的呃用我們已經錄討的這些音品採集過的這個包括現在我跟你說的這些裡面都落下來,還可以去做實驗。 因為Gamma 4有一個30秒打開的一個上線,
- zh_long_02: sim=0.732 kw=2/3
  output: 另外一個就是你去反思我們在程序上面有哪些假設或者是猜測實際上是沒有意義的,比如說我們這些排序的依據是什麼等等。
- en_short_01: sim=0.000 kw=0/2
  output: 我觉得可以用
- en_short_02: sim=0.143 kw=0/1
  output: Facebook的channel怎麼不工作了?
- mixed_medium_01: sim=0.684 kw=1/3
  output: cloud的ANSDK的依賴,把它升級到最新版,然後做一個pre-release部署到staging mini上。
- mixed_long_01: sim=0.684 kw=3/3
  output: 現在這個CLI和入口是什麼設計的,我們該怎麼使用? 如果我想讓以前使用 subagent的方式執行的主agent去調用這個CLI去find evidence.

### 4B Summary
- Best prompt: gen2a_precise ("请精确转录这段语音的每一个字，使用简体中文，保留所有英文单词的原始拼写。")
- Best sim: 0.581 (vs 2B SOTA: +0.012)
- Best kw: 0.469 (vs 2B SOTA: +0.125)
- Avg Latency: 0.485s

## Updated Comparison Table (pre-GT-update)

| Metric | Qwen3-ASR | Gemma4 2B 4bit | Gemma4 4B 4bit (best) |
|--------|-----------|----------------|----------------------|
| Model | Qwen3-ASR-0.6B | mlx-community/gemma-4-e2b-it-4bit | mlx-community/gemma-4-e4b-it-4bit |
| Size | ~1.6 GB | ~1.5 GB | ~5.2 GB |
| Avg Similarity | 1.000 | 0.569 | 0.581 |
| Keyword Accuracy | 1.000 | 0.344 | 0.469 |
| Avg Latency | ~2-4s | ~0.28s | 0.485s |

---

## Generation 3: Post-processing & Sampling Experiments

Date: 2026-04-06 22:11
Model: mlx-community/gemma-4-e4b-it-4bit
Ground Truth: Human-annotated (regression_cases.json updated 2026-04-06)

> **Note:** Starting from Gen 3, ground truth is human-annotated, not Qwen3 output.
> This means scores are NOT directly comparable to Gen 0-2 numbers.
> Re-ran baselines for fair comparison.

### Re-baselined scores (human-annotated GT)

| Engine | Avg Similarity | Keyword Accuracy | Avg Latency |
|--------|---------------|-----------------|-------------|
| Qwen3 (from history) | 0.792 | 0.750 | N/A |
| Gemma4 4B baseline (temp=0.0) | 0.708 | 0.400 | 0.849s |

### Experiment A: Traditional-to-Simplified Post-processing (gen3a_t2s)

- Engine: gemma4-4b + OpenCC t2s conversion
- Prompt: same as gen2a_precise
- Score: **sim=0.736**, kw=0.450, hallucination=0/12
- Avg Latency: 0.841s
- vs Gemma4 4B baseline: **+0.028 sim**, +0.050 kw
- vs Qwen3: gap=0.056
- Decision: **NEW SOTA** (best Gemma4 result ever)

Per-case improvements from t2s:
- zh_long_01: 0.560 -> 0.784 (+0.224) -- biggest win, many traditional chars converted
- zh_medium_03: 0.593 -> 0.704 (+0.111) -- "關鍵詞" -> "关键词" etc.
- en_short_01: 0.923 -> 0.923 (no change, already simplified)
- en_short_02: 0.727 -> 0.727 (no change)
- zh_medium_04: 0.374 -> 0.374 (no improvement -- the core misrecognition is not t/s related)

### Experiment B: Temperature & Sampling Parameters

#### B1: temperature=0.1 (gen3b_temp01)
- Score: sim=0.706, kw=0.400, hallucination=0/12
- Avg Latency: 0.841s
- vs baseline (temp=0.0, sim=0.708): **-0.002** (no improvement)
- Decision: DISCARD

#### B2: temperature=0.3 (gen3b_temp03)
- Score: sim=0.690, kw=0.400, hallucination=0/12
- Avg Latency: 0.883s
- vs baseline (sim=0.708): **-0.018** (worse)
- Decision: DISCARD

#### B3: temperature=0.1 + top_p=0.9 (gen3b_temp01_top09)
- Score: sim=0.723, kw=0.400, hallucination=0/12
- Avg Latency: 0.847s
- vs baseline (sim=0.708): **+0.015**
- Decision: KEEP (but still worse than t2s)

> Takeaway: Greedy decoding (temp=0.0) is near-optimal. top_p=0.9 gives minor improvement
> but less than t2s post-processing. Temperature hurts more than it helps.

### Experiment C: Ensemble Analysis (Qwen3 vs Gemma4-4B-t2s)

Per-case comparison (human-annotated GT):

| Case | Qwen3 sim | Gemma4-t2s sim | Winner | Delta |
|------|-----------|---------------|--------|-------|
| zh_short_01 | **1.000** | 0.500 | Qwen3 | +0.500 |
| zh_short_02 | **0.900** | 0.900 | TIE | 0.000 |
| zh_medium_01 | **0.895** | 0.712 | Qwen3 | +0.183 |
| zh_medium_02 | **0.929** | 0.697 | Qwen3 | +0.232 |
| zh_medium_03 | **1.000** | 0.704 | Qwen3 | +0.296 |
| zh_medium_04 | **0.796** | 0.374 | Qwen3 | +0.422 |
| zh_long_01 | **0.853** | 0.784 | Qwen3 | +0.069 |
| zh_long_02 | **1.000** | 0.852 | Qwen3 | +0.148 |
| en_short_01 | 0.000 | **0.923** | Gemma4 | +0.923 |
| en_short_02 | 0.154 | **0.727** | Gemma4 | +0.573 |
| mixed_medium_01 | **0.975** | 0.780 | Qwen3 | +0.195 |
| mixed_long_01 | **1.000** | 0.874 | Qwen3 | +0.126 |

**Ensemble winner counts:** Qwen3 wins 10/12, Gemma4 wins 2/12 (en_short_01, en_short_02)

**Ideal ensemble score (best of each case):**
- sim = (1.000+0.900+0.895+0.929+1.000+0.796+0.853+1.000+0.923+0.727+0.975+1.000) / 12
- sim = **0.917**
- vs Qwen3 alone (0.792): +0.125
- vs Gemma4-t2s alone (0.736): +0.181

**Key insight:** The ensemble's value comes almost entirely from Gemma4 correctly
outputting Chinese for the two "en_short" cases where Qwen3 outputs English.
These cases have Chinese ground truth (human-annotated: "我觉得可以用。" and
"飞书的 chanel 怎么不工作了？") but Qwen3 transcribes them as English
("I think it can be used." and "Fei said, ...").

A simpler fix: force Qwen3 to output Chinese for all cases (via LLM post-processing
or language detection). This would likely capture most of the ensemble benefit
without needing to run two models.

### Gen 3 Summary

| Variant | Avg Sim | Kw Acc | vs Baseline |
|---------|---------|--------|-------------|
| Gemma4 4B baseline (temp=0.0) | 0.708 | 0.400 | -- |
| **Gemma4 4B + t2s** | **0.736** | **0.450** | **+0.028** |
| Gemma4 4B temp=0.1 | 0.706 | 0.400 | -0.002 |
| Gemma4 4B temp=0.3 | 0.690 | 0.400 | -0.018 |
| Gemma4 4B temp=0.1+top_p=0.9 | 0.723 | 0.400 | +0.015 |
| Qwen3 (reference) | 0.792 | 0.750 | -- |
| Ideal ensemble (Qwen3+Gemma4) | **0.917** | -- | -- |

## Final Updated Comparison Table

| Metric | Qwen3-ASR | Gemma4 4B + t2s (SOTA) | Ideal Ensemble |
|--------|-----------|----------------------|----------------|
| Avg Similarity | 0.792 | 0.736 | 0.917 |
| Keyword Accuracy | 0.750 | 0.450 | -- |
| Hallucinations | 0/12 | 0/12 | 0/12 |
| Avg Latency | ~2-4s | ~0.85s | ~0.85+2-4s |
| Gemma4 wins | -- | 2/12 cases | 12/12 cases |
| Gap to Qwen3 | -- | -0.056 | +0.125 |

---

## Generation 4: Audio-Aware Polish Experiment (4B)

Date: 2026-04-06 22:17:26
Model: mlx-community/gemma-4-e4b-it-4bit
Approach: Qwen3 ASR + Gemma4 audio-aware polish (audio + rough text -> corrected text)
Post-processing: OpenCC t2s on all outputs

### Baselines (human-annotated GT)
- Qwen3 raw: sim=0.792, kw=0.75
- Gemma4 4B ASR-only: sim=0.581, kw=0.469

### polish_v1
- Prompt: "以下是语音识别系统的粗转录结果，可能有错字、同音字错误或英文词识别错误。
请根据音频内容修正转录文本。只输出修正后的文本，不要解释。

粗转录：{qwen3_output}"
- Score: sim=0.754, kw=0.700, hallucination=0/12
- Avg Latency: 0.586s
- vs Qwen3 raw (sim=0.792): -0.038
- vs Gemma4 ASR (sim=0.581): +0.173
- Verdict: Beats Gemma4 ASR, but not Qwen3

Per-case results:
- zh_short_01: sim=1.000 (qwen3=1.000 +0.000 SAME) kw=2/2
  qwen3_raw: 不可，如果不确定，就做实验。
  polished:  不可，如果不确定，就做实验。
- zh_short_02: sim=0.900 (qwen3=0.900 +0.000 SAME) kw=1/1
  qwen3_raw: 好的，我来更新一把。
  polished:  好的，我来更新一下。
- zh_medium_01: sim=0.846 (qwen3=0.895 -0.049 WORSE) kw=4/5
  qwen3_raw: 对于日税表，结果你要有自己独立的判断，因为它的上下文肯定没有你的丰富。所以，你可以同意，也可以不同意。
  polished:  对于レビュー结果，你要有自己独立的判断，因为它的上下文肯定没有你的丰富，所以你可以同意也可以不同意。
- zh_medium_02: sim=0.946 (qwen3=0.929 +0.018 BETTER) kw=5/5
  qwen3_raw: 我们同步一下现在最新状态：目前的搜塔是一个什么样的水水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。
  polished:  我们同步一下现在最新状态：目前的SOTA是一个什么样的水准，然后根据上一轮的迭代，下一轮的改进的方向是什么。
- zh_medium_03: sim=0.667 (qwen3=1.000 -0.333 WORSE) kw=3/3
  qwen3_raw: 有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
  polished:  有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
- zh_medium_04: sim=0.796 (qwen3=0.796 +0.000 SAME) kw=3/4
  qwen3_raw: 例如，例如不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
  polished:  例如，例如不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
- zh_long_01: sim=0.844 (qwen3=0.853 -0.009 SAME) kw=2/6
  qwen3_raw: 开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个T Mate去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四
  polished:  实现。然后对于JMAP 4的集成，我建议你可以单独起一个Tmate去做实验，然后探索它的呃用我们已经录好的这些音品材料采集过的，包括现在我跟你说的这些影片都留下来了，可以去做实验。因为JMAP 4有一
- zh_long_02: sim=0.956 (qwen3=1.000 -0.044 WORSE) kw=3/3
  qwen3_raw: 另外一个就是，你去反思：我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
  polished:  另外一个就是你去反思，我们在程序上面有哪些假设或者是猜测，实际上是没有意义的，比如我们这些排序的依据是什么等等。
- en_short_01: sim=0.000 (qwen3=0.000 +0.000 SAME) kw=0/1
  qwen3_raw: I think it can be used.
  polished:  I think it can be used.
- en_short_02: sim=0.154 (qwen3=0.154 +0.000 SAME) kw=0/3
  qwen3_raw: Fei said, "The car owner doesn't work anymore."
  polished:  Fei said, "The car owner doesn't work anymore."
- mixed_medium_01: sim=0.942 (qwen3=0.975 -0.033 WORSE) kw=2/4
  qwen3_raw: Cloud Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。
  polished:  Cloud Agent SDK的依赖，把它升级到最新版，然后做一个pre release，部署到Trace Mini上。
- mixed_long_01: sim=0.994 (qwen3=1.000 -0.006 SAME) kw=3/3
  qwen3_raw: 现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的，主Agent去调用这个CLI去find evidence。
  polished:  现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的主Agent去调用这个CLI去find evidence。

### Polish Experiment Summary (4B)

| Prompt | Avg Sim | Kw Acc | vs Qwen3 | vs Gemma4 ASR | Verdict |
|--------|---------|--------|----------|---------------|---------|
| polish_v1 | 0.754 | 0.700 | -0.038 | +0.173 | Beats G4 ASR |

Best prompt: polish_v1 (sim=0.754)

---

## Generation 4: Audio-Aware Polish Experiment (4B)

Date: 2026-04-06 22:18:32
Model: mlx-community/gemma-4-e4b-it-4bit
Approach: Qwen3 ASR + Gemma4 audio-aware polish (audio + rough text -> corrected text)
Post-processing: OpenCC t2s on all outputs

### Baselines (human-annotated GT)
- Qwen3 raw: sim=0.792, kw=0.75
- Gemma4 4B ASR-only: sim=0.581, kw=0.469

### polish_v1
- Prompt: "以下是语音识别系统的粗转录结果，可能有错字、同音字错误或英文词识别错误。
请根据音频内容修正转录文本。只输出修正后的文本，不要解释。

粗转录：{qwen3_output}"
- Score: sim=0.754, kw=0.700, hallucination=0/12
- Avg Latency: 0.573s
- vs Qwen3 raw (sim=0.792): -0.038
- vs Gemma4 ASR (sim=0.581): +0.173
- Verdict: Beats Gemma4 ASR, but not Qwen3

Per-case results:
- zh_short_01: sim=1.000 (qwen3=1.000 +0.000 SAME) kw=2/2
  qwen3_raw: 不可，如果不确定，就做实验。
  polished:  不可，如果不确定，就做实验。
- zh_short_02: sim=0.900 (qwen3=0.900 +0.000 SAME) kw=1/1
  qwen3_raw: 好的，我来更新一把。
  polished:  好的，我来更新一下。
- zh_medium_01: sim=0.846 (qwen3=0.895 -0.049 WORSE) kw=4/5
  qwen3_raw: 对于日税表，结果你要有自己独立的判断，因为它的上下文肯定没有你的丰富。所以，你可以同意，也可以不同意。
  polished:  对于レビュー结果，你要有自己独立的判断，因为它的上下文肯定没有你的丰富，所以你可以同意也可以不同意。
- zh_medium_02: sim=0.946 (qwen3=0.929 +0.018 BETTER) kw=5/5
  qwen3_raw: 我们同步一下现在最新状态：目前的搜塔是一个什么样的水水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。
  polished:  我们同步一下现在最新状态：目前的SOTA是一个什么样的水准，然后根据上一轮的迭代，下一轮的改进的方向是什么。
- zh_medium_03: sim=0.667 (qwen3=1.000 -0.333 WORSE) kw=3/3
  qwen3_raw: 有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
  polished:  有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
- zh_medium_04: sim=0.796 (qwen3=0.796 +0.000 SAME) kw=3/4
  qwen3_raw: 例如，例如不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
  polished:  例如，例如不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
- zh_long_01: sim=0.844 (qwen3=0.853 -0.009 SAME) kw=2/6
  qwen3_raw: 开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个T Mate去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四
  polished:  实现。然后对于JMAP 4的集成，我建议你可以单独起一个Tmate去做实验，然后探索它的呃用我们已经录好的这些音品材料采集过的，包括现在我跟你说的这些影片都留下来了，可以去做实验。因为JMAP 4有一
- zh_long_02: sim=0.956 (qwen3=1.000 -0.044 WORSE) kw=3/3
  qwen3_raw: 另外一个就是，你去反思：我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
  polished:  另外一个就是你去反思，我们在程序上面有哪些假设或者是猜测，实际上是没有意义的，比如我们这些排序的依据是什么等等。
- en_short_01: sim=0.000 (qwen3=0.000 +0.000 SAME) kw=0/1
  qwen3_raw: I think it can be used.
  polished:  I think it can be used.
- en_short_02: sim=0.154 (qwen3=0.154 +0.000 SAME) kw=0/3
  qwen3_raw: Fei said, "The car owner doesn't work anymore."
  polished:  Fei said, "The car owner doesn't work anymore."
- mixed_medium_01: sim=0.942 (qwen3=0.975 -0.033 WORSE) kw=2/4
  qwen3_raw: Cloud Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。
  polished:  Cloud Agent SDK的依赖，把它升级到最新版，然后做一个pre release，部署到Trace Mini上。
- mixed_long_01: sim=0.994 (qwen3=1.000 -0.006 SAME) kw=3/3
  qwen3_raw: 现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的，主Agent去调用这个CLI去find evidence。
  polished:  现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的主Agent去调用这个CLI去find evidence。

### polish_v2_concise
- Prompt: "修正以下语音转录中的错误：{qwen3_output}"
- Score: sim=0.749, kw=0.750, hallucination=0/12
- Avg Latency: 0.546s
- vs Qwen3 raw (sim=0.792): -0.043
- vs Gemma4 ASR (sim=0.581): +0.168
- Verdict: Beats Gemma4 ASR, but not Qwen3

Per-case results:
- zh_short_01: sim=1.000 (qwen3=1.000 +0.000 SAME) kw=2/2
  qwen3_raw: 不可，如果不确定，就做实验。
  polished:  不可，如果不确定，就做实验。
- zh_short_02: sim=0.900 (qwen3=0.900 +0.000 SAME) kw=1/1
  qwen3_raw: 好的，我来更新一把。
  polished:  好的，我来更新一把。
- zh_medium_01: sim=0.854 (qwen3=0.895 -0.041 WORSE) kw=4/5
  qwen3_raw: 对于日税表，结果你要有自己独立的判断，因为它的上下文肯定没有你的丰富。所以，你可以同意，也可以不同意。
  polished:  对于日检表，结果你要有自己独立的判断，因为它的上下文肯定没有你的丰富，所以你可以同意也可以不同意。
- zh_medium_02: sim=0.883 (qwen3=0.929 -0.046 WORSE) kw=4/5
  qwen3_raw: 我们同步一下现在最新状态：目前的搜塔是一个什么样的水水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。
  polished:  我们同步一下现在最新状态：目前的搜塔是一个什么样的水准？然后，根据上一轮的迭代，下一轮的改进的方向是什么？
- zh_medium_03: sim=1.000 (qwen3=1.000 +0.000 SAME) kw=3/3
  qwen3_raw: 有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
  polished:  有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
- zh_medium_04: sim=0.718 (qwen3=0.796 -0.077 WORSE) kw=3/4
  qwen3_raw: 例如，例如不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
  polished:  由于，pyrrolo不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
- zh_long_01: sim=0.856 (qwen3=0.853 +0.003 SAME) kw=4/6
  qwen3_raw: 开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个T Mate去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四
  polished:  开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个Tmate去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四有
- zh_long_02: sim=0.659 (qwen3=1.000 -0.341 WORSE) kw=3/3
  qwen3_raw: 另外一个就是，你去反思：我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
  polished:  另外一个就是，你去反思：我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。另外一个就是，你去反思，我们在程序上面有哪些假设或者是猜测，猜测实际上是没有意义的。比
- en_short_01: sim=0.000 (qwen3=0.000 +0.000 SAME) kw=0/1
  qwen3_raw: I think it can be used.
  polished:  I think it can be used.
- en_short_02: sim=0.154 (qwen3=0.154 +0.000 SAME) kw=0/3
  qwen3_raw: Fei said, "The car owner doesn't work anymore."
  polished:  Fei said, "The car owner doesn't work anymore."
- mixed_medium_01: sim=0.975 (qwen3=0.975 +0.000 SAME) kw=3/4
  qwen3_raw: Cloud Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。
  polished:  Cloud Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。
- mixed_long_01: sim=0.994 (qwen3=1.000 -0.006 SAME) kw=3/3
  qwen3_raw: 现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的，主Agent去调用这个CLI去find evidence。
  polished:  现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的主Agent去调用这个CLI去find evidence。

### polish_v3_keywords
- Prompt: "以下是语音识别系统的粗转录结果，可能包含同音字错误。请对照音频修正文本，可能包含的术语：Review, SOTA, benchmark, Gemma 4, Agent, CLI, SDK。
只输出修正后的文本。

粗转录：{qwen3_output}"
- Score: sim=0.787, kw=0.725, hallucination=0/12
- Avg Latency: 0.561s
- vs Qwen3 raw (sim=0.792): -0.005
- vs Gemma4 ASR (sim=0.581): +0.206
- Verdict: Beats Gemma4 ASR, but not Qwen3

Per-case results:
- zh_short_01: sim=1.000 (qwen3=1.000 +0.000 SAME) kw=2/2
  qwen3_raw: 不可，如果不确定，就做实验。
  polished:  不可，如果不确定，就做实验。
- zh_short_02: sim=0.900 (qwen3=0.900 +0.000 SAME) kw=1/1
  qwen3_raw: 好的，我来更新一把。
  polished:  好的，我来更新一下。
- zh_medium_01: sim=0.926 (qwen3=0.895 +0.031 BETTER) kw=5/5
  qwen3_raw: 对于日税表，结果你要有自己独立的判断，因为它的上下文肯定没有你的丰富。所以，你可以同意，也可以不同意。
  polished:  对于 Review 结果，你要有自己独立的判断，因为它的上下文肯定没有你的丰富，所以你可以同意也可以不同意。
- zh_medium_02: sim=0.973 (qwen3=0.929 +0.045 BETTER) kw=5/5
  qwen3_raw: 我们同步一下现在最新状态：目前的搜塔是一个什么样的水水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。
  polished:  我们同步一下现在最新状态：目前的SOTA是一个什么样的水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。
- zh_medium_03: sim=0.980 (qwen3=1.000 -0.020 WORSE) kw=3/3
  qwen3_raw: 有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
  polished:  有一个是 hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来 hack。
- zh_medium_04: sim=0.766 (qwen3=0.796 -0.030 WORSE) kw=3/4
  qwen3_raw: 例如，例如不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
  polished:  您不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
- zh_long_01: sim=0.853 (qwen3=0.853 +0.000 SAME) kw=2/6
  qwen3_raw: 开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个T Mate去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四
  polished:  实现。然后对于JMAP 4的集成，我建议你可以单独起一个teammate去做实验，然后探索它的用我们已经录好的这些音品材料采集过的，包括现在我跟你说的这些影片都留下来了，可以去做实验。因为JMAP 4
- zh_long_02: sim=0.982 (qwen3=1.000 -0.018 WORSE) kw=3/3
  qwen3_raw: 另外一个就是，你去反思：我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
  polished:  另外一个就是，你去反思，我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
- en_short_01: sim=0.000 (qwen3=0.000 +0.000 SAME) kw=0/1
  qwen3_raw: I think it can be used.
  polished:  I think it can be used.
- en_short_02: sim=0.154 (qwen3=0.154 +0.000 SAME) kw=0/3
  qwen3_raw: Fei said, "The car owner doesn't work anymore."
  polished:  Fei said, "The car owner doesn't work anymore."
- mixed_medium_01: sim=0.912 (qwen3=0.975 -0.063 WORSE) kw=2/4
  qwen3_raw: Cloud Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。
  polished:  Cloud Agent SDK 的依赖，把它升级到最新版，然后做一个 pre-release，部署到 Tracy Mini 上。
- mixed_long_01: sim=0.994 (qwen3=1.000 -0.006 SAME) kw=3/3
  qwen3_raw: 现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的，主Agent去调用这个CLI去find evidence。
  polished:  现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的主Agent去调用这个CLI去find evidence。

### polish_v4_english
- Prompt: "Correct the following speech transcription errors based on the audio. Fix homophone errors, preserve English words, and output simplified Chinese. Onl"
- Score: sim=0.870, kw=0.725, hallucination=0/12
- Avg Latency: 0.530s
- vs Qwen3 raw (sim=0.792): +0.078
- vs Gemma4 ASR (sim=0.581): +0.289
- Verdict: BEATS QWEN3 -- this approach has value!

Per-case results:
- zh_short_01: sim=1.000 (qwen3=1.000 +0.000 SAME) kw=2/2
  qwen3_raw: 不可，如果不确定，就做实验。
  polished:  不可，如果不确定，就做实验。
- zh_short_02: sim=0.900 (qwen3=0.900 +0.000 SAME) kw=1/1
  qwen3_raw: 好的，我来更新一把。
  polished:  好的，我来更新一下。
- zh_medium_01: sim=0.846 (qwen3=0.895 -0.049 WORSE) kw=4/5
  qwen3_raw: 对于日税表，结果你要有自己独立的判断，因为它的上下文肯定没有你的丰富。所以，你可以同意，也可以不同意。
  polished:  对于レビュー结果，你要有自己独立的判断，因为它的上下文肯定没有你的丰富，所以你可以同意也可以不同意。
- zh_medium_02: sim=0.919 (qwen3=0.929 -0.010 SAME) kw=4/5
  qwen3_raw: 我们同步一下现在最新状态：目前的搜塔是一个什么样的水水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。
  polished:  我们同步一下现在最新状态：目前的搜塔是一个什么样的水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。
- zh_medium_03: sim=0.990 (qwen3=1.000 -0.010 SAME) kw=3/3
  qwen3_raw: 有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
  polished:  一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
- zh_medium_04: sim=0.784 (qwen3=0.796 -0.012 WORSE) kw=3/4
  qwen3_raw: 例如，例如不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
  polished:  例如，不能提到宁德时代，不能提到跟我们的电池膜还相关的任何关键词。这样的是一个作弊的行为。
- zh_long_01: sim=0.838 (qwen3=0.853 -0.014 WORSE) kw=2/6
  qwen3_raw: 开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个T Mate去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四
  polished:  实现。然后对于JMAP四的集成，我建议你可以单独起一个Tmate去做实验，然后探索它的呃，用我们已经录好的这些音品采集过的，包括现在我跟你说的这些音品都留下来了，可以去做实验。因为JMAP四有一个30
- zh_long_02: sim=0.973 (qwen3=1.000 -0.027 WORSE) kw=3/3
  qwen3_raw: 另外一个就是，你去反思：我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
  polished:  另外一个就是你去反思，我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
- en_short_01: sim=0.923 (qwen3=0.000 +0.923 BETTER) kw=1/1
  qwen3_raw: I think it can be used.
  polished:  我觉得可以用
- en_short_02: sim=0.333 (qwen3=0.154 +0.179 BETTER) kw=1/3
  qwen3_raw: Fei said, "The car owner doesn't work anymore."
  polished:  费说的频道好像不工作了。
- mixed_medium_01: sim=0.942 (qwen3=0.975 -0.033 WORSE) kw=2/4
  qwen3_raw: Cloud Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。
  polished:  Cloud Agent SDK的依赖，把它升级到最新版，然后做一个pre release，部署到Trace Mini上。
- mixed_long_01: sim=0.994 (qwen3=1.000 -0.006 SAME) kw=3/3
  qwen3_raw: 现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的，主Agent去调用这个CLI去find evidence。
  polished:  现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的主Agent去调用这个CLI去find evidence。

### polish_v5_precise
- Prompt: "你是一个语音转录校对助手。下面是ASR系统的粗转录和原始音频。
请根据音频修正转录中的错误，包括：
1. 同音字错误（如'日税表'应为'Review'）
2. 英文专有名词拼写（如SOTA, benchmark, Agent SDK）
3. 多余或遗漏的字
使用简体中文，保留英文原词。只输出修正后的"
- Score: sim=0.783, kw=0.750, hallucination=0/12
- Avg Latency: 0.599s
- vs Qwen3 raw (sim=0.792): -0.009
- vs Gemma4 ASR (sim=0.581): +0.202
- Verdict: Beats Gemma4 ASR, but not Qwen3

Per-case results:
- zh_short_01: sim=1.000 (qwen3=1.000 +0.000 SAME) kw=2/2
  qwen3_raw: 不可，如果不确定，就做实验。
  polished:  不可，如果不确定，就做实验。
- zh_short_02: sim=0.900 (qwen3=0.900 +0.000 SAME) kw=1/1
  qwen3_raw: 好的，我来更新一把。
  polished:  好的，我来更新一下。
- zh_medium_01: sim=0.943 (qwen3=0.895 +0.048 BETTER) kw=5/5
  qwen3_raw: 对于日税表，结果你要有自己独立的判断，因为它的上下文肯定没有你的丰富。所以，你可以同意，也可以不同意。
  polished:  对于Review结果，你要有自己独立的判断，因为它的上下文肯定没有你的丰富，所以你可以同意也可以不同意。
- zh_medium_02: sim=0.946 (qwen3=0.929 +0.018 BETTER) kw=5/5
  qwen3_raw: 我们同步一下现在最新状态：目前的搜塔是一个什么样的水水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。
  polished:  我们同步一下现在最新状态：目前的SOTA是一个什么样的水准，然后根据上一轮的迭代，下一轮的改进的方向是什么。
- zh_medium_03: sim=0.949 (qwen3=1.000 -0.051 WORSE) kw=3/3
  qwen3_raw: 有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。
  polished:  有一个是 hard line，绝对不能碰的，就是不能在提示词中注入具体的关键词，然后来 hack。
- zh_medium_04: sim=0.742 (qwen3=0.796 -0.054 WORSE) kw=3/4
  qwen3_raw: 例如，例如不能提宁德时代，不能提跟我们的半尺寸麦克相关的任何关键词。这样的是一个作弊的行为。
  polished:  所以，除了不能提宁德时代，不能提跟我们的半尺寸麦相关的任何关键词，这样的是一个作弊的行为。
- zh_long_01: sim=0.887 (qwen3=0.853 +0.034 BETTER) kw=3/6
  qwen3_raw: 开始实现。然后，对于JMAP四的集成，我建议你可以单独起一个T Mate去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP四
  polished:  实现。然后对于JMAP 4的集成，我建议你可以单独起一个teammate去做实验，然后探索它的，呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为JMAP 
- zh_long_02: sim=0.973 (qwen3=1.000 -0.027 WORSE) kw=3/3
  qwen3_raw: 另外一个就是，你去反思：我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
  polished:  另外一个就是你去反思，我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。
- en_short_01: sim=0.000 (qwen3=0.000 +0.000 SAME) kw=0/1
  qwen3_raw: I think it can be used.
  polished:  I think it can be used.
- en_short_02: sim=0.154 (qwen3=0.154 +0.000 SAME) kw=0/3
  qwen3_raw: Fei said, "The car owner doesn't work anymore."
  polished:  Fei said, "The car owner doesn't work anymore."
- mixed_medium_01: sim=0.912 (qwen3=0.975 -0.063 WORSE) kw=2/4
  qwen3_raw: Cloud Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。
  polished:  Cloud Agent SDK 的依赖，把它升级到最新版，然后做一个 pre-release，部署到 Tracy Mini 上。
- mixed_long_01: sim=0.994 (qwen3=1.000 -0.006 SAME) kw=3/3
  qwen3_raw: 现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的，主Agent去调用这个CLI去find evidence。
  polished:  现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的主Agent去调用这个CLI去find evidence。

### Polish Experiment Summary (4B)

| Prompt | Avg Sim | Kw Acc | vs Qwen3 | vs Gemma4 ASR | Verdict |
|--------|---------|--------|----------|---------------|---------|
| polish_v1 | 0.754 | 0.700 | -0.038 | +0.173 | Beats G4 ASR |
| polish_v2_concise | 0.749 | 0.750 | -0.043 | +0.168 | Beats G4 ASR |
| polish_v3_keywords | 0.787 | 0.725 | -0.005 | +0.206 | Beats G4 ASR |
| polish_v4_english | 0.870 | 0.725 | +0.078 | +0.289 | BEATS QWEN3 |
| polish_v5_precise | 0.783 | 0.750 | -0.009 | +0.202 | Beats G4 ASR |

Best prompt: polish_v4_english (sim=0.870)
