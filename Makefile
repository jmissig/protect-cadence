BINARY := protect-cadence
SKILL_NAME := protect-cadence
SKILL_DIR := skills/$(SKILL_NAME)
BUILD_DIR ?= build
CONFIGURATION ?= debug
PREFIX ?= $(HOME)
BINDIR ?= $(PREFIX)/bin
OPENCLAW_SKILLS_DIR ?= $(HOME)/.openclaw/skills
SKILL_DEST := $(OPENCLAW_SKILLS_DIR)/$(SKILL_NAME)
SWIFT_FLAGS ?= --disable-sandbox

.PHONY: build release test install install-skill clean show-bin

build:
	swift build $(SWIFT_FLAGS) --build-path $(BUILD_DIR) --product $(BINARY)

release:
	swift build $(SWIFT_FLAGS) -c release --build-path $(BUILD_DIR) --product $(BINARY)

test:
	swift test $(SWIFT_FLAGS) --build-path $(BUILD_DIR)

install: release
	install -d $(BINDIR)
	install -m 0755 $(BUILD_DIR)/release/$(BINARY) $(BINDIR)/$(BINARY)
	@echo "Installed $(BINARY) to $(BINDIR)/$(BINARY)"

install-skill:
	@test -f "$(SKILL_DIR)/SKILL.md" || (echo "Missing $(SKILL_DIR)/SKILL.md" && exit 1)
	mkdir -p "$(OPENCLAW_SKILLS_DIR)"
	rm -rf "$(SKILL_DEST)"
	cp -R "$(SKILL_DIR)" "$(SKILL_DEST)"
	@echo "Installed skill $(SKILL_NAME) to $(SKILL_DEST)"

clean:
	rm -rf $(BUILD_DIR)

show-bin:
	@echo $(BUILD_DIR)/$(CONFIGURATION)/$(BINARY)
