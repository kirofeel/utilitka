#!/bin/zsh
# Builds a Release copy of Utilitka and packs it into dist/Utilitka.zip for a GitHub release.
# The app is signed ad hoc ("Sign to Run Locally"), not notarized: see README for what users see on first launch.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen" >&2; exit 1; }

xcodegen generate --quiet
xcodebuild -project Utilitka.xcodeproj -scheme Utilitka -configuration Release \
  -derivedDataPath build -quiet build

rm -rf dist && mkdir dist
ditto -c -k --keepParent build/Build/Products/Release/Utilitka.app dist/Utilitka.zip
shasum -a 256 dist/Utilitka.zip | tee dist/Utilitka.zip.sha256
echo "Ready: dist/Utilitka.zip"
