#!/bin/bash

set -e

echo "🚀 Starting multi-platform build process..."

# Get version from package.json
VERSION=$(node -p "require('./package.json').version")
echo "📦 Version: $VERSION"

# Create output directory
OUTPUT_DIR="dist/platforms"
mkdir -p "$OUTPUT_DIR"

# Build core OpenClaw (required for all platforms)
echo "🔧 Building core OpenClaw..."
pnpm build
pnpm ui:build

# Create npm package
echo "📦 Creating npm package..."
npm pack
cp "openclaw-$VERSION.tgz" "$OUTPUT_DIR/"

# macOS builds
if [[ "$BUILD_MACOS" != "false" ]]; then
  echo "🍎 Building macOS packages..."
  
  # Build macOS app
  pnpm mac:package
  
  # Create DMG if the script exists
  if [[ -f "scripts/create-dmg.sh" ]]; then
    echo "💾 Creating DMG file..."
    bash scripts/create-dmg.sh
    if [[ -f "dist/OpenClaw-$VERSION.dmg" ]]; then
      cp "dist/OpenClaw-$VERSION.dmg" "$OUTPUT_DIR/"
    fi
  fi
  
  # Create ZIP archive
  if [[ -d "dist/OpenClaw.app" ]]; then
    echo "🗃️ Creating ZIP archive..."
    pushd dist
    zip -r "../$OUTPUT_DIR/OpenClaw-$VERSION-mac.zip" "OpenClaw.app"
    popd
  fi
fi

# Linux builds (tar.gz)
if [[ "$BUILD_LINUX" != "false" ]]; then
  echo "🐧 Creating Linux tarball..."
  tar -czf "$OUTPUT_DIR/openclaw-$VERSION-linux.tar.gz" -C dist .
fi

# Android builds
if [[ "$BUILD_ANDROID" != "false" && -d "apps/android" ]]; then
  echo "🤖 Building Android APK..."
  pnpm android:assemble
  if [[ -f "apps/android/app/build/outputs/apk/debug/app-debug.apk" ]]; then
    cp "apps/android/app/build/outputs/apk/debug/app-debug.apk" "$OUTPUT_DIR/openclaw-$VERSION-android.apk"
  fi
fi

# iOS builds (requires Xcode, so we'll just prepare the project)
if [[ "$BUILD_IOS" != "false" && -d "apps/ios" ]]; then
  echo "📱 Preparing iOS project..."
  pnpm ios:gen
  # iOS apps need to be built on macOS with proper signing
  # We'll create a zip of the project for manual building
  if [[ -f "apps/ios/OpenClaw.xcodeproj/project.pbxproj" ]]; then
    pushd apps/ios
    zip -r "../../../$OUTPUT_DIR/openclaw-$VERSION-ios-project.zip" .
    popd
  fi
fi

echo "✅ Multi-platform build completed!"
echo "📁 Output directory: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"

# Create checksums
echo "🔐 Generating checksums..."
pushd "$OUTPUT_DIR"
sha256sum * > "SHA256SUMS-$VERSION.txt"
popd

echo "📋 Build summary:"
echo "- npm package: openclaw-$VERSION.tgz"
if [[ "$BUILD_MACOS" != "false" ]]; then
  echo "- macOS app: OpenClaw.app (in ZIP)"
  echo "- macOS DMG: OpenClaw-$VERSION.dmg (if created)"
fi
if [[ "$BUILD_LINUX" != "false" ]]; then
  echo "- Linux tarball: openclaw-$VERSION-linux.tar.gz"
fi
if [[ "$BUILD_ANDROID" != "false" ]]; then
  echo "- Android APK: openclaw-$VERSION-android.apk"
fi
if [[ "$BUILD_IOS" != "false" ]]; then
  echo "- iOS project: openclaw-$VERSION-ios-project.zip"
fi