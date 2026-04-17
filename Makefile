.PHONY: build build-release test run clean resolve download-models lint help prompt-regress

PROJECT = Talk.xcodeproj
SCHEME = Talk
BUILD_DIR = $(HOME)/Library/Developer/Xcode/DerivedData
APP_PATH = $(shell find $(BUILD_DIR) -path "*/Talk-*/Build/Products/Debug/Talk.app" -maxdepth 5 2>/dev/null | head -1)

# Code signing flags for CLI builds (ad-hoc)
SIGN_FLAGS = CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

resolve: ## Resolve SPM dependencies
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -resolvePackageDependencies

build: ## Build Debug configuration
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build $(SIGN_FLAGS)

build-release: ## Build Release configuration
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build $(SIGN_FLAGS)

test: ## Run unit tests (excludes benchmarks and prompt regression — both need models)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test $(SIGN_FLAGS) \
		-destination 'platform=macOS' \
		-only-testing:TalkTests \
		-skip-testing:TalkTests/ASRBenchmarks \
		-skip-testing:TalkTests/LLMBenchmarks \
		-skip-testing:TalkTests/PipelineBenchmarks \
		-skip-testing:TalkTests/QwenPromptRegressionTests \
		-skip-testing:TalkTests/Gemma4PromptRegressionTests 2>&1 | tail -20

prompt-regress: ## Run LLM prompt regression tests (requires Qwen + Gemma4 models)
	@echo "Running LLM prompt regression suite..."
	@echo "Loads real Qwen3.5 + Gemma4 models — first run may be slow."
	@echo ""
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test $(SIGN_FLAGS) \
		-destination 'platform=macOS' \
		-only-testing:TalkTests/QwenPromptRegressionTests \
		-only-testing:TalkTests/Gemma4PromptRegressionTests 2>&1 | grep -E "passed|failed|Test Suite|got:" | tail -40

benchmark: ## Run performance benchmarks (requires models downloaded)
	@echo "Running Talk benchmarks..."
	@echo "Models must be downloaded first: make download-models"
	@echo "Results will be written to /tmp/talk-benchmark-results.txt"
	@echo ""
	@rm -f /tmp/talk-benchmark-results.txt
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test $(SIGN_FLAGS) \
		-destination 'platform=macOS' \
		-only-testing:TalkTests/ASRBenchmarks \
		-only-testing:TalkTests/LLMBenchmarks \
		-only-testing:TalkTests/PipelineBenchmarks 2>&1 | grep -E "BENCH:|passed|failed|error:" | sed 's/.*BENCH: //'
	@echo ""
	@echo "===== Full Results ====="
	@cat /tmp/talk-benchmark-results.txt 2>/dev/null || echo "(no results file found)"

run: build ## Build and run the app
	@$(eval APP := $(shell find $(BUILD_DIR) -path "*/Talk-*/Build/Products/Debug/Talk.app" -maxdepth 5 2>/dev/null | head -1))
	@if [ -n "$(APP)" ]; then \
		pkill -x Talk 2>/dev/null || true; \
		sleep 0.5; \
		open "$(APP)"; \
		echo "Talk.app launched"; \
	else \
		echo "Error: Talk.app not found. Run 'make build' first."; \
		exit 1; \
	fi

clean: ## Clean build artifacts
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	rm -rf $(BUILD_DIR)/Talk-*
	@echo "Build artifacts cleaned"

download-models: ## Download ML models from HuggingFace
	@command -v uv >/dev/null 2>&1 || { echo "Error: uv not found. Install with: brew install uv"; exit 1; }
	@echo "Downloading ASR model (Qwen3-ASR-0.6B-4bit)..."
	uv run --with huggingface_hub python3 -c "from huggingface_hub import snapshot_download; print(snapshot_download('mlx-community/Qwen3-ASR-0.6B-4bit'))"
	@echo "Downloading LLM model (Qwen3-4B-Instruct-2507-4bit)..."
	uv run --with huggingface_hub python3 -c "from huggingface_hub import snapshot_download; print(snapshot_download('mlx-community/Qwen3-4B-Instruct-2507-4bit'))"
	@echo "Models downloaded to ~/.cache/huggingface/"

lint: ## Run SwiftLint (if installed)
	@command -v swiftlint >/dev/null 2>&1 && swiftlint lint Talk/ || echo "SwiftLint not installed. Install with: brew install swiftlint"

setup: resolve download-models ## Full setup: resolve deps + download models
	@echo "Setup complete. Run 'make build' to build."

package-lite: ## Package + sign + notarize Talk-lite.dmg (app only, ~20 MB)
	./scripts/package.sh lite

package-full: ## Package + sign + notarize Talk-full.dmg (app + models, ~2.5 GB)
	./scripts/package.sh full
