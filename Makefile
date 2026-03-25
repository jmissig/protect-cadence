BINARY := protect-cadence
BUILD_DIR ?= build
CONFIGURATION ?= debug
BINDIR ?= $(HOME)/bin

.PHONY: build release test install clean show-bin

build:
	swift build --build-path $(BUILD_DIR) --product $(BINARY)

release:
	swift build -c release --build-path $(BUILD_DIR) --product $(BINARY)

test:
	swift test --build-path $(BUILD_DIR)

install: release
	install -d $(BINDIR)
	install -m 0755 $(BUILD_DIR)/release/$(BINARY) $(BINDIR)/$(BINARY)
	@echo "Installed $(BINARY) to $(BINDIR)/$(BINARY)"

clean:
	rm -rf $(BUILD_DIR)

show-bin:
	@echo $(BUILD_DIR)/$(CONFIGURATION)/$(BINARY)
