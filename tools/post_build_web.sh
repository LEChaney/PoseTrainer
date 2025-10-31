#!/bin/bash
# Post-build processing for Flutter web to enable proper cache busting
# Based on: https://lukasnevosad.medium.com/our-flutter-web-strategy-for-deferred-loading-instant-updates-happy-users-45ed90a7727c
# 
# Compatible with Linux, macOS, and Windows (Git Bash)

set -e

# Configuration
BUILD_FOLDER="build/web"
DIST_FOLDER="dist"

# Check if build folder exists
if [ ! -d "$BUILD_FOLDER" ]; then
  echo "Error: Build folder '$BUILD_FOLDER' not found. Run 'flutter build web' first."
  exit 1
fi

# Check if version.json exists
if [ ! -f "$BUILD_FOLDER/version.json" ]; then
  echo "Error: version.json not found in '$BUILD_FOLDER'. Make sure Flutter build completed successfully."
  exit 1
fi

echo "Starting post-build processing for Flutter web..."

# Extract version and build_number from version.json
# Example: "version":"1.0.0","build_number":"123" -> 1.0.0+123
VERSION_BASE=$(sed -n 's|.*"version":"\([^"]*\)".*|\1|p' "$BUILD_FOLDER/version.json")
BUILD_NUMBER=$(sed -n 's|.*"build_number":"\([^"]*\)".*|\1|p' "$BUILD_FOLDER/version.json")

if [ -z "$VERSION_BASE" ]; then
  echo "Error: Could not extract version from version.json"
  exit 1
fi

if [ -z "$BUILD_NUMBER" ]; then
  echo "Error: Could not extract build_number from version.json"
  exit 1
fi

# Combine into full version string
VERSION="${VERSION_BASE}+${BUILD_NUMBER}"

echo "Detected version: $VERSION"

# Clean and create distribution directory
rm -rf "$DIST_FOLDER"
mkdir -p "$DIST_FOLDER"

# Move entire build output to versioned subdirectory
echo "Moving build output to versioned directory: $DIST_FOLDER/$VERSION/"
mv "$BUILD_FOLDER" "$DIST_FOLDER/$VERSION"

# Copy version.json to root (so it can be checked for updates)
echo "Copying version.json to root..."
cp "$DIST_FOLDER/$VERSION/version.json" "$DIST_FOLDER/version.json"

# Move index.html to root
echo "Moving index.html to root..."
mv "$DIST_FOLDER/$VERSION/index.html" "$DIST_FOLDER/index.html"

# Modify <base href> in index.html to point to versioned directory
echo "Updating <base href> to point to /$VERSION/..."

# Different sed syntax for different platforms
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS requires -i with extension
  sed -i.bak "s|<base href=\"/\"|<base href=\"/$VERSION/\"|g" "$DIST_FOLDER/index.html"
  rm -f "$DIST_FOLDER/index.html.bak"
else
  # Linux
  sed -i "s|<base href=\"/\"|<base href=\"/$VERSION/\"|g" "$DIST_FOLDER/index.html"
fi

echo "Post-build processing complete!"
echo ""
echo "Distribution structure:"
echo "  $DIST_FOLDER/"
echo "    ├── index.html         (with <base href=\"/$VERSION/\">)"
echo "    ├── version.json       (for update checks)"
echo "    └── $VERSION/"
echo "        ├── flutter.js"
echo "        ├── flutter_bootstrap.js"
echo "        ├── main.dart.js"
echo "        ├── *.part.js      (deferred chunks)"
echo "        └── assets/"
echo ""
echo "Deploy the contents of '$DIST_FOLDER/' to your hosting provider."
