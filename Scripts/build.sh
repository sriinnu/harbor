#!/bin/bash
#
# Harbor Build Script
# Ensures all build artifacts go to the build/ directory
#

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🔨 Building Harbor..."
echo "📁 Build artifacts will be in: $PROJECT_ROOT/build/"

# Use xcodebuild with explicit derivedDataPath
xcodebuild \
    -scheme Harbor \
    -destination 'platform=macOS,arch=arm64' \
    -configuration Debug \
    -derivedDataPath "$PROJECT_ROOT/build" \
    clean build

echo "✅ Build complete!"
echo "🚀 Run Harbor: $PROJECT_ROOT/build/Build/Products/Debug/Harbor"
