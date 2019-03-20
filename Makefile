# Makefile for Sloth

XCODE_PROJ := "Sloth.xcodeproj"
BUILD_DIR := "products"

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" resources/Info.plist)
APP_NAME := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleName" resources/Info.plist)
APP_NAME_LC := $(shell echo "${APP_NAME}" | tr '[:upper:]' '[:lower:]') # lowercase name
APP_BUNDLE_NAME := "$(APP_NAME).app"

#APP_ZIP_NAME := $(APP_NAME_LC)
APP_ZIP_NAME := $(APP_NAME_LC:=-${VERSION}).zip
APP_SRC_ZIP_NAME := $(APP_NAME_LC:=-${VERSION}).src.zip
APP_PATH := $(BUILD_DIR:=/${APP_BUNDLE_NAME})

all: clean build_unsigned

release: clean build_signed archives size

build_unsigned:
	mkdir -p $(BUILD_DIR)
	xcodebuild  -parallelizeTargets \
	            -project "$(XCODE_PROJ)" \
	            -target "$(APP_NAME)" \
	            -configuration "Release" \
	            CONFIGURATION_BUILD_DIR="$(BUILD_DIR)" \
	            CODE_SIGN_IDENTITY="" \
                CODE_SIGNING_REQUIRED=NO \
	            clean build

build_signed:
	mkdir -p $(BUILD_DIR)
	xcodebuild  -parallelizeTargets \
	            -project "$(XCODE_PROJ)" \
	            -target "$(APP_NAME)" \
	            -configuration "Release" \
	            CONFIGURATION_BUILD_DIR="$(BUILD_DIR)" \
	            clean build

archives:
	@echo "Creating application archive ${APP_ZIP_NAME}..."
	@cd $(BUILD_DIR); zip -q --symlinks $(APP_ZIP_NAME) -r $(APP_BUNDLE_NAME)

	@echo "Creating source archive ${APP_SRC_ZIP_NAME}..."
	@cd $(BUILD_DIR); zip -q --symlinks -r "${APP_SRC_ZIP_NAME}" ".." -x \*.git\* -x \*.zip\* -x \*.DS_Store\* -x \*dsa_priv.pem\* -x \*Sparkle/dsa_priv.pem\* -x \*products/\* -x \*build/\* -x \*xcuserdata\*

	@echo "Generating Sparkle signature"
	@ruby "sparkle/sign_update.rb" $(APP_PATH) "sparkle/dsa_priv.pem" 2> /dev/null

size:
	@echo "App bundle size:"
	@du -hs $(APP_PATH)
	@echo "Binary size:"
	@stat -f %z $(APP_PATH)/Contents/MacOS/*
	@echo "Archive Sizes:"
	@cd $(BUILD_DIR); du -hs $(APP_ZIP_NAME)
	@cd $(BUILD_DIR); du -hs $(APP_SRC_ZIP_NAME)

clean:
	xcodebuild -project "$(XCODE_PROJ)" clean
	rm -rf products/* 2> /dev/null
