#!/bin/bash
# Reset ClawTalk to fresh onboarding state (uninstall, rebuild, launch)
set -e

SIM="46F49878-3CFB-4F45-B4E4-BCF6F261CAE9"
BUNDLE="com.openclaw.clawtalk"
SCHEME="ClawTalk"
PROJECT="ClawTalk.xcodeproj"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Terminating and uninstalling..."
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$SIM" "$BUNDLE"
xcrun simctl keychain "$SIM" reset

echo "Building..."
xcodebuild -project "$PROJECT_DIR/$PROJECT" -scheme "$SCHEME" \
  -destination "id=$SIM" -quiet build

echo "Installing and launching..."
APP_PATH=$(xcodebuild -project "$PROJECT_DIR/$PROJECT" -scheme "$SCHEME" \
  -destination "id=$SIM" -showBuildSettings 2>/dev/null \
  | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')
xcrun simctl install "$SIM" "$APP_PATH/$SCHEME.app"
xcrun simctl launch "$SIM" "$BUNDLE"

echo "Done — fresh onboarding is running."
