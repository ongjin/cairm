SHELL := /bin/bash

PROJECT := apps/Cairn.xcodeproj
SCHEME  := Cairn
CONFIG  := Debug
DERIVED := build/DerivedData
APP     := $(DERIVED)/Build/Products/$(CONFIG)/Cairn.app
WATCH_SOURCES := apps/Sources crates

# Code signing.
#
# Default: ad-hoc linker-signed. Fast and dependency-free, but macOS TCC
# re-prompts for Desktop/Documents/Apple Music/etc. on every rebuild because
# the CDHash changes and TCC treats each build as a new app.
#
# To persist TCC grants across rebuilds, set DEV_IDENTITY in your shell to
# the SHA1 of a codesigning certificate (free Apple ID "Apple Development"
# cert is enough). Discover with:
#
#   security find-identity -v -p codesigning
#
# Then export it, e.g.:
#
#   export DEV_IDENTITY=5AF97180F6DFA9E09C25339E6999161857A9A6BB
#
# The SHA1-based form is preferred over the human name ("Apple Development")
# because Xcode's automatic signing insists on a provisioning profile for
# named identities, which requires a paid Developer Program membership.
DEV_IDENTITY ?=
ifeq ($(strip $(DEV_IDENTITY)),)
  SIGNING := CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
  SIGNING_BANNER := "signing: ad-hoc (set DEV_IDENTITY=<cert-SHA1> to persist TCC grants)"
else
  SIGNING := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(DEV_IDENTITY)" PROVISIONING_PROFILE_SPECIFIER=""
  SIGNING_BANNER := "signing: manual / identity $(DEV_IDENTITY)"
endif

XCBUILD := xcodebuild \
              -project $(PROJECT) \
              -scheme $(SCHEME) \
              -configuration $(CONFIG) \
              -destination "platform=macOS" \
              -derivedDataPath $(CURDIR)/$(DERIVED) \
              $(SIGNING)

.PHONY: help rust swift build run dev test install-cli uninstall-cli clean

help: ## 사용 가능한 타겟 목록
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

rust: ## Rust FFI universal static lib 빌드 + Swift 바인딩 동기화
	./scripts/build-rust.sh
	@./scripts/gen-bindings.sh

swift: rust ## xcodegen regenerate + Swift 앱 빌드
	@cd apps && xcodegen generate
	@echo $(SIGNING_BANNER)
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

install-cli: ## Install the `cairn` CLI to /usr/local/bin (sudo may be required).
	@install -m 0755 cli/cairn /usr/local/bin/cairn
	@echo "installed: /usr/local/bin/cairn"

uninstall-cli: ## Remove the `cairn` CLI from /usr/local/bin.
	@rm -f /usr/local/bin/cairn
	@echo "removed: /usr/local/bin/cairn"

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
