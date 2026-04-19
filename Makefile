BINARY := protect-cadence
SKILL_NAME := protect-cadence
SKILL_DIR := skills/$(SKILL_NAME)
VERSION_FILE := VERSION
VERSION_SYNC_FILE := Sources/ProtectCadence/CLI/Commands/ProtectCadenceCLICommand.swift
VERSION := $(shell tr -d '\n' < $(VERSION_FILE))
BUILD_DIR ?= build
CONFIGURATION ?= debug
PREFIX ?= $(HOME)
BINDIR ?= $(PREFIX)/bin
OPENCLAW_SKILLS_DIR ?= $(HOME)/.openclaw/skills
SKILL_DEST := $(OPENCLAW_SKILLS_DIR)/$(SKILL_NAME)

.PHONY: build release test install install-skill sync-version clean show-bin

sync-version:
	@test -f "$(VERSION_FILE)" || (echo "Missing $(VERSION_FILE)" && exit 1)
	python3 -c 'from pathlib import Path; import re; version = Path("$(VERSION_FILE)").read_text().strip() or "0.0.0"; path = Path("$(VERSION_SYNC_FILE)"); text = path.read_text(); text, count = re.subn(r"// VERSION-SYNC-START\n.*?\n// VERSION-SYNC-END", "// VERSION-SYNC-START\nprivate let protectCadenceCLIVersion = \"%s\"\n// VERSION-SYNC-END" % version, text, count=1, flags=re.S); assert count == 1, "version marker not found"; path.write_text(text)'

build: sync-version
	swift build --build-path $(BUILD_DIR) --product $(BINARY)

release: sync-version
	swift build -c release --build-path $(BUILD_DIR) --product $(BINARY)

test: sync-version
	swift test --build-path $(BUILD_DIR)

install: release
	install -d $(BINDIR)
	install -m 0755 $(BUILD_DIR)/release/$(BINARY) $(BINDIR)/$(BINARY)
	@echo "Installed $(BINARY) to $(BINDIR)/$(BINARY)"

install-skill:
	@test -f "$(SKILL_DIR)/SKILL.md" || (echo "Missing $(SKILL_DIR)/SKILL.md" && exit 1)
	@test -f "$(VERSION_FILE)" || (echo "Missing $(VERSION_FILE)" && exit 1)
	mkdir -p "$(OPENCLAW_SKILLS_DIR)"
	rm -rf "$(SKILL_DEST)"
	cp -R "$(SKILL_DIR)" "$(SKILL_DEST)"
	python3 -c 'from pathlib import Path; import re; path = Path("$(SKILL_DEST)/SKILL.md"); text = path.read_text(); text = re.sub(r"\n<!-- repo-version: .*? -->\n?", "\n", text); text = text.rstrip() + "\n\n<!-- repo-version: $(VERSION) -->\n"; path.write_text(text)'
	@echo "Installed skill $(SKILL_NAME) to $(SKILL_DEST)"

clean:
	rm -rf $(BUILD_DIR)

show-bin:
	@echo $(BUILD_DIR)/$(CONFIGURATION)/$(BINARY)
