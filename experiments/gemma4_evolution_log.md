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

## Updated Comparison Table

| Metric | Qwen3-ASR | Gemma4 2B 4bit | Gemma4 4B 4bit (best) |
|--------|-----------|----------------|----------------------|
| Model | Qwen3-ASR-0.6B | mlx-community/gemma-4-e2b-it-4bit | mlx-community/gemma-4-e4b-it-4bit |
| Size | ~1.6 GB | ~1.5 GB | ~5.2 GB |
| Avg Similarity | 1.000 | 0.569 | 0.581 |
| Keyword Accuracy | 1.000 | 0.344 | 0.469 |
| Avg Latency | ~2-4s | ~0.28s | 0.485s |
