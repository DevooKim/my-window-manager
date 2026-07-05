.PHONY: build test app run release publish bump-patch bump-minor bump-major

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)

# Swift Testing under Command Line Tools (no Xcode): Testing.framework ships
# inside CLT but SPM doesn't add its search paths automatically. With full
# Xcode selected these flags are unnecessary, so they're added only when
# xcode-select points at CLT.
CLT := /Library/Developer/CommandLineTools
ifeq ($(shell xcode-select -p),$(CLT))
TESTFLAGS := -Xswiftc -F$(CLT)/Library/Developer/Frameworks \
	-Xlinker -F$(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
endif

build:
	swift build

test:
	swift test $(TESTFLAGS)

app:
	bash scripts/bundle.sh

run: app
	open "dist/My Window Manager.app"

# ditto preserves symlinks, extended attributes, and the code signature —
# required for distributing .app bundles.
release: app
	ditto -c -k --keepParent "dist/My Window Manager.app" "dist/My-Window-Manager-v$(VERSION).zip"
	@echo "Created: dist/My-Window-Manager-v$(VERSION).zip"

# Builds the zip, tags v$(VERSION), pushes, and publishes a GitHub release
# with a commit-based changelog (see scripts/publish.sh).
# Bump CFBundleShortVersionString in Info.plist first.
publish: release
	@bash scripts/publish.sh

# Bump CFBundleShortVersionString (semver) and CFBundleVersion (build
# number), then commit. Release flow: make bump-minor && make publish
bump-patch:
	@bash scripts/bump.sh patch

bump-minor:
	@bash scripts/bump.sh minor

bump-major:
	@bash scripts/bump.sh major
