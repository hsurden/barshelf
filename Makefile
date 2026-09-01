.PHONY: build check dmg install local-build run

build:
	./scripts/build-app.sh

local-build:
	./scripts/build-local-clt.sh

check:
	xcodegen generate
	xcodebuild -quiet -project Barkeep.xcodeproj -scheme Barkeep -configuration Debug -derivedDataPath .xcode-build CODE_SIGNING_ALLOWED=NO test

dmg:
	./scripts/build-dmg.sh

install:
	./scripts/install-local.sh

run: install
