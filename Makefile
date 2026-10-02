CONFIG ?= release
APP := build/Wakeful.app

.PHONY: build app test install uninstall dist clean

build:
	swift build -c $(CONFIG)

# Assembles an ad-hoc signed app bundle with the watchdog inside it.
app: build
	@bin="$$(swift build -c $(CONFIG) --show-bin-path)"; \
	rm -rf $(APP); \
	mkdir -p $(APP)/Contents/MacOS; \
	cp Resources/Info.plist $(APP)/Contents/Info.plist; \
	cp "$$bin/Wakeful" "$$bin/wakeful-watchdog" $(APP)/Contents/MacOS/; \
	codesign --force --sign - $(APP)/Contents/MacOS/wakeful-watchdog; \
	codesign --force --sign - $(APP); \
	echo "Built $(APP)"

# Some toolchains (seen with Command Line Tools, Swift 6.4) keep the Swift Testing macro plugin in
# a plugins/testing subfolder and intermittently fail to load it on a clean build. Pointing the
# compiler at it explicitly fixes that and is harmless elsewhere.
TESTING_PLUGINS := $(shell dirname "$$(xcrun --find swift 2>/dev/null)" 2>/dev/null)/../lib/swift/host/plugins/testing

test:
	@if [ -d "$(TESTING_PLUGINS)" ]; then \
		swift test -Xswiftc -plugin-path -Xswiftc "$(TESTING_PLUGINS)"; \
	else \
		swift test; \
	fi

install:
	scripts/install.sh

uninstall:
	scripts/uninstall.sh

# Zips the committed source (no build output, no git history) for sharing.
dist:
	@mkdir -p build
	git archive --format=zip --prefix=wakeful/ -o build/wakeful.zip HEAD
	@echo "Wrote build/wakeful.zip ($$(du -h build/wakeful.zip | cut -f1)). Uncommitted changes are not included."

clean:
	rm -rf build .build
