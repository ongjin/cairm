SHELL := /bin/bash

PROJECT := apps/Cairn.xcodeproj
SCHEME  := Cairn
CONFIG  := Debug
DERIVED := build/DerivedData
APP     := $(DERIVED)/Build/Products/$(CONFIG)/Cairn.app
WATCH_SOURCES := apps/Sources crates

XCBUILD := xcodebuild \
              -project $(PROJECT) \
              -scheme $(SCHEME) \
              -configuration $(CONFIG) \
              -destination "platform=macOS" \
              -derivedDataPath $(CURDIR)/$(DERIVED) \
              CODE_SIGNING_REQUIRED=NO \
              CODE_SIGN_IDENTITY=""

.PHONY: help rust swift build run dev test clean

help: ## 사용 가능한 타겟 목록
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

rust: ## Rust FFI universal static lib 빌드 + Swift 바인딩 동기화
	./scripts/build-rust.sh
	@./scripts/gen-bindings.sh

swift: rust ## xcodegen regenerate + Swift 앱 빌드
	@cd apps && xcodegen generate
	@$(XCBUILD) build

build: swift ## 풀 빌드 (Rust + Swift)
	@echo "built: $(APP)"

run: build ## 빌드 후 기존 인스턴스 종료, 인덱스 캐시 청소, 앱 실행
	@pkill -f "Cairn.app/Contents/MacOS/Cairn" 2>/dev/null || true
	@sleep 0.3
	@# 매 실행마다 fresh index. 캐시는 폴더당 sha256 키라 어차피 navigation에서
	@# 자동 재생성됨; 여기서 비우면 partial-walk 잔여물이 남지 않음.
	@rm -rf "$(HOME)/Library/Caches/Cairn/index"
	@open "$(APP)"

dev: ## 소스 변경 감시 → 자동 rebuild & relaunch (fswatch 필요)
	@command -v fswatch >/dev/null 2>&1 || { echo "fswatch 없음: brew install fswatch"; exit 1; }
	@$(MAKE) run
	@echo "▶ watching: $(WATCH_SOURCES)"
	@fswatch -o -l 1 $(WATCH_SOURCES) | while read -r _; do \
		clear; echo "▶ change detected, rebuilding..."; \
		$(MAKE) run || true; \
	done

test: ## cargo test --workspace + xcodebuild test
	cargo test --workspace
	@$(XCBUILD) test

clean: ## cargo clean + xcodebuild clean + DerivedData 삭제
	cargo clean
	@rm -rf $(DERIVED)
	@echo "cleaned"
