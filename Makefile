# Developer entry points. CI runs these same targets.
CONFIGURATION ?= Debug
ARCH ?= $(shell uname -m)
DERIVED_DATA := .build/xcode
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/NotchDeck.app
SWIFT_SOURCES := App Sources Tests Package.swift
# The commit a build comes from, with "+" when the checkout has uncommitted changes (shown in the menu).
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null)$(shell git diff --quiet HEAD -- 2>/dev/null || echo +)
# Signs with your Apple Development certificate when you have one. macOS ties permissions (Calendar,
# Reminders, folders) to the signature, and an ad-hoc one changes with every build, so updates would
# ask again each time. Without a certificate (CI, most contributors) builds stay ad-hoc signed.
SIGNING_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $$2; exit}')
# Manual style on every target, including SwiftPM's resource bundles, so none of them asks for a team.
SIGNING = $(if $(SIGNING_IDENTITY),CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='$(SIGNING_IDENTITY)')
# More build settings for xcodebuild, such as CI's ONLY_ACTIVE_ARCH=YES to compile one architecture.
XCODEBUILD_ARGS ?=

.PHONY: setup project build run install update test lint format licenses secrets changelog check clean

setup: ## Install developer tools (Brewfile) and fetch submodules
	brew bundle
	git submodule update --init --recursive

project: ## Generate OpenNotch.xcodeproj from project.yml
	git submodule update --init --recursive
	xcodegen generate --quiet

build: project ## Build the app; CONFIGURATION=Debug|Release
	xcodebuild -project OpenNotch.xcodeproj -scheme OpenNotch -configuration $(CONFIGURATION) \
		-destination 'platform=macOS,arch=$(ARCH)' -derivedDataPath $(DERIVED_DATA) \
		OPENNOTCH_COMMIT='$(COMMIT)' $(SIGNING) $(XCODEBUILD_ARGS) -quiet build

run: build ## Build and relaunch the app
	-osascript -e 'quit app "NotchDeck"'
	open $(APP)

# Only NotchDeck is quit and replaced: a real ILoveNotch install is never touched.
install: ## Build a Release app into /Applications and (re)launch it
	$(MAKE) build CONFIGURATION=Release
	@osascript -e 'quit app "NotchDeck"' >/dev/null 2>&1 || true
	@for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x NotchDeck >/dev/null || break; sleep 0.3; done; \
		pkill -x NotchDeck || true
	rm -rf /Applications/NotchDeck.app
	ditto $(DERIVED_DATA)/Build/Products/Release/NotchDeck.app /Applications/NotchDeck.app
	open /Applications/NotchDeck.app

update: ## Pull main when safe, rebuild, reinstall, relaunch (the app's "Update NotchDeck")
	scripts/update.sh

test: ## Run unit and performance tests (warnings are errors in OpenNotch's own targets: Package.swift)
	swift test

lint: ## Fail on formatting drift (config: .swift-format)
	swift format lint --strict --recursive $(SWIFT_SOURCES)

format: ## Apply formatting in place
	swift format --in-place --recursive $(SWIFT_SOURCES)

licenses: ## SPDX headers and third-party notices
	scripts/check-licenses.sh

secrets: ## No keys, certificates, profiles, or credentials files in git
	scripts/check-secrets.sh

# The first MARKETING_VERSION in project.yml is the app's; the vendored helper's comes later.
changelog: ## CHANGELOG.md has release notes for the version in project.yml
	@scripts/release-notes.sh "$$(awk '/^ +MARKETING_VERSION:/ {print $$2; exit}' project.yml)" >/dev/null

check: secrets lint changelog test build licenses ## Everything CI runs

clean:
	rm -rf .build OpenNotch.xcodeproj
