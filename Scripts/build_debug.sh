#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project TeleFeed.xcodeproj -scheme TeleFeed -configuration Debug -destination platform=macOS build

