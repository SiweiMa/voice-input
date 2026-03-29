APP_NAME := VoiceInput
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
EXECUTABLE := .build/release/$(APP_NAME)

.PHONY: build run install clean

build:
	swift build -c release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(EXECUTABLE) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp AppResources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	codesign --force --deep --sign - $(APP_BUNDLE)

run: build
	open $(APP_BUNDLE)

install: build
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_BUNDLE) /Applications/$(APP_NAME).app

clean:
	swift package clean
	rm -rf $(BUILD_DIR)
