# Talk Performance Benchmarks

## How to Run

```bash
# Prerequisites: models must be downloaded
make download-models

# Run benchmarks (Release build for accurate numbers)
make benchmark
```

## What's Measured

| Benchmark | Description |
|-----------|-------------|
| **ASR Model Load** | Time to load Qwen3-ASR-0.6B-4bit from HuggingFace cache |
| **ASR Inference (3s)** | Transcribe 3 seconds of silence |
| **ASR Inference (5s)** | Transcribe 5 seconds of ambient noise |
| **LLM Model Load** | Time to load Qwen3-4B-Instruct-2507-4bit |
| **LLM Polish (short)** | Polish a short sentence (~30 chars) |
| **LLM Polish (long)** | Polish a long paragraph (~120 chars) |
| **Full Pipeline** | ASR → LLM end-to-end latency |
| **Memory (loaded)** | RSS with both models in memory |
| **Memory (unloaded)** | RSS after unloading both models |

## Metrics

- **Load time**: seconds to load model weights from disk
- **Inference time**: seconds from input to output
- **Real-time factor (RTF)**: `audio_duration / inference_time` — values > 1.0x mean faster than real-time
- **Memory delta**: additional RSS consumed by loading a model
- **Total memory**: process RSS at measurement point

## Latest Results

> Run on: MacBook Pro (Apple Silicon)
> Date: 2026-03-21
> macOS: 26.3.1

| Benchmark | Result | Status |
|-----------|--------|--------|
| ASR Model Load | 1.97s | ✅ |
| ASR Inference (3s silence) | 0.07-0.18s (RTF 17-44x) | ✅ |
| ASR Inference (5s noise) | 0.10-0.17s (RTF 30-51x) | ✅ |
| **LLM Model Load** | **9.4-10.5s** | ❌ **bottleneck** |
| LLM Polish (short, 26 chars) | 0.35-0.50s | ✅ |
| LLM Polish (long, 122 chars) | 1.12-1.21s | ✅ |
| Full Pipeline (ASR+LLM) | 1.05s | ✅ |
| ASR Memory | ~1.6 GB | ⚠️ |
| LLM Memory | ~9.6 GB | ❌ **too high** |
| Memory after unload | 0 MB freed | ❌ **leak** |

### Key Findings

1. **LLM model load is the bottleneck** — 10s cold load blocks the user experience
2. **LLM memory is excessive** — ~9.6 GB for a 4-bit 4B model, likely includes Metal buffers
3. **Memory is not freed on unload** — MLX/Metal buffers persist after model deallocation
4. **Inference is fast** — once loaded, ASR is near-instant, LLM < 1.5s even for long text
5. **ASR is extremely fast** — RTF 17-51x, not a bottleneck at all

## Reproducing

1. Clone the repo: `git clone https://github.com/platx-ai/Talk.git && cd Talk`
2. Download models: `make download-models`
3. Run benchmarks: `make benchmark`
4. Copy the output and paste it in an issue or PR

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| ASR Model Load | < 3s | Cold load from SSD |
| LLM Model Load | < 5s | Cold load from SSD |
| ASR Inference (5s audio) | < 2s | RTF > 2.5x |
| LLM Polish (short) | < 3s | For responsive UX |
| Total Pipeline | < 8s | From stop-recording to text-injected |
| Memory (both models) | < 4GB | Fit in 8GB Mac |
