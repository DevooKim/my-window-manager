.PHONY: build app run release publish bump-patch bump-minor bump-major

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)

build:
	swift build

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
