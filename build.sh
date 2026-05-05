#!/bin/bash

# Build script for RootCAInjector
# Creates a Magisk/KernelSU module zip file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(grep "^version=" "$SCRIPT_DIR/module.prop" | cut -d'=' -f2)

echo "Building RootCAInjector $VERSION..."

# Create release directory
mkdir -p "$SCRIPT_DIR/release"

# Remove old zip if exists
rm -f "$SCRIPT_DIR/release/RootCAInjector.zip"
rm -f "$SCRIPT_DIR/release/RootCAInjector_$VERSION.zip"

# Create zip excluding unnecessary files
cd "$SCRIPT_DIR"

zip -r "release/RootCAInjector.zip" . \
    -x ".git/*" \
    -x ".github/*" \
    -x "release/*" \
    -x "*.md" \
    -x "LICENSE" \
    -x ".gitignore" \
    -x "build.sh"

# Also create versioned zip
cp "release/RootCAInjector.zip" "release/RootCAInjector_$VERSION.zip"

echo ""
echo "Build complete!"
echo "Output:"
echo "  - release/RootCAInjector.zip"
echo "  - release/RootCAInjector_$VERSION.zip"
echo ""
echo "Install via Magisk/KernelSU/APatch or adb:"
echo "  adb push release/RootCAInjector.zip /sdcard/Download/"
