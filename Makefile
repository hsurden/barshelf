.PHONY: build check dmg install local-build local-dmg run

build:
	./scripts/build-app.sh

local-build:
	./scripts/build-local-clt.sh

check:
	xcodegen generate
	xcodebuild -quiet -project BarShelf.xcodeproj -scheme BarShelf -configuration Debug -derivedDataPath .xcode-build CODE_SIGNING_ALLOWED=NO test

dmg:
	./scripts/build-dmg.sh

local-dmg: local-build
	SKIP_BUILD=1 ./scripts/build-dmg.sh

install:
	./scripts/install-local-hs.sh

run: install
