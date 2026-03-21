.PHONY: build build-release test run clean resolve download-models lint help

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

test: ## Run unit tests
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test $(SIGN_FLAGS) \
		-destination 'platform=macOS' \
		-only-testing:TalkTests 2>&1 | tail -20

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
