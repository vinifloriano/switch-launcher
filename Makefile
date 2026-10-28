.PHONY: build test app dist install run clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

dist:
	./scripts/build-app.sh --dist

install:
	./scripts/build-app.sh --install

run: app
	open "build/Switch Launcher.app"

clean:
	swift package clean
	rm -rf build dist
