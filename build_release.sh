#!/bin/bash
#
# Release build script for Sloth
# Must be run from src root
#

XCODE_PROJ="Sloth.xcodeproj"

if [ ! -e "${XCODE_PROJ}" ]; then
    echo "Build script must be run from src root"
    exit 1
fi

SRC_DIR=$PWD
BUILD_DIR="/tmp/"
REMOTE_DIR="root@sveinbjorn.org:/www/sveinbjorn/html/files/software/sloth/"
REMOTE_ZIP_PATH="root@sveinbjorn.org:/www/sveinbjorn/html/files/software/sloth.zip"
REMOTE_SRC_ZIP_PATH="root@sveinbjorn.org:/www/sveinbjorn/html/files/software/sloth.zip"

VERSION=`/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" resources/Info.plist`
APP_NAME="Sloth"
APP_NAME_LC=`echo "${APP_NAME}" | perl -ne 'print lc'` # lowercase name
APP_BUNDLE_NAME="${APP_NAME}.app"

APP_ZIP_NAME="${APP_NAME_LC}-${VERSION}.zip"
APP_SRC_ZIP_NAME="${APP_NAME_LC}-${VERSION}.src.zip"

#echo $VERSION
#echo $APP_NAME
#echo $APP_NAME_LC
#
#echo $APP_FOLDER_NAME
#echo $APP_BUNDLE_NAME
#
#echo $APP_ZIP_NAME
#echo $APP_SRC_ZIP_NAME

echo "Building ${APP_NAME} version ${VERSION}"

xcodebuild  -parallelizeTargets \
            -project "${XCODE_PROJ}" \
            -target "${APP_NAME}" \
            -configuration "Release" \
            CONFIGURATION_BUILD_DIR="${BUILD_DIR}" \
            clean \
            build
#1> /dev/null

# Check if build succeeded
if test $? -eq 0
then
    echo "Build successful"
else
    echo "Build failed"
    exit
fi

# Strip executables
echo "Stripping binary"
strip -x "${BUILD_DIR}/${APP_BUNDLE_NAME}/Contents/MacOS/Sloth"

# # Remove DS_Store junk
find "${BUILD_DIR}/${APP_BUNDLE_NAME}/" -name ".DS_Store" -exec rm -f "{}" \;

# # Create zip archive and move to desktop
echo "Creating application archive ${APP_ZIP_NAME}..."
cd "${BUILD_DIR}"
zip -q --symlinks "${APP_ZIP_NAME}" -r "${APP_BUNDLE_NAME}"

if [ $1 ]
then
    echo "Uploading application archive ..."
    scp "${APP_ZIP_NAME}" "${REMOTE_DIR}"
    scp "${APP_ZIP_NAME}" "${REMOTE_ZIP_PATH}"
fi

FINAL_APP_ARCHIVE_PATH=~/Desktop/${APP_ZIP_NAME}

echo "Moving application archive to Desktop"
mv "${APP_ZIP_NAME}" ${FINAL_APP_ARCHIVE_PATH}

# Create source archive
echo "Creating source archive ${APP_SRC_ZIP_NAME}..."
cd "${SRC_DIR}"
zip -q --symlinks -r "${APP_SRC_ZIP_NAME}" "." -x *.git* -x *.zip* -x *.tgz* -x *.gz* -x *.DS_Store* -x *dsa_priv.pem* -x *Sparkle/dsa_priv.pem* -x \*build/\* -x \*Releases\*

if [ $1 ]
then
    echo "Uploading source archive ..."
    scp "${APP_SRC_ZIP_NAME}" "${REMOTE_DIR}"
    scp "${APP_SRC_ZIP_NAME}" "${REMOTE_SRC_ZIP_PATH}"
fi

FINAL_SRC_ARCHIVE_PATH=~/Desktop/${APP_SRC_ZIP_NAME}

echo "Moving source archive to Desktop"
mv "${APP_SRC_ZIP_NAME}" ${FINAL_SRC_ARCHIVE_PATH}

echo "Generating Sparkle signature"
if [ ! -e "sparkle/dsa_priv.pem" ]; then
    echo "Missing private key sparkle/dsa_priv.pem"
    exit 1
fi
ruby "sparkle/sign_update.rb" ~/Desktop/${APP_ZIP_NAME} "sparkle/dsa_priv.pem"

echo "Archive Sizes:"
du -hs ${FINAL_APP_ARCHIVE_PATH}
du -hs ${FINAL_SRC_ARCHIVE_PATH}
