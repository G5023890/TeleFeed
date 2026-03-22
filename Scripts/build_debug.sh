#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Telega.xcodeproj -scheme Telega -configuration Debug -destination platform=macOS build

