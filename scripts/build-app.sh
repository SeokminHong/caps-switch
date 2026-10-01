#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
xcrun swift build --configuration release --jobs 2
binary_dir="$(xcrun swift build --configuration release --show-bin-path)"
app_dir="$project_dir/build/Caps Switch.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/caps-switch" "$app_dir/Contents/MacOS/CapsSwitch"
cp "$project_dir/resources/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir"
/usr/bin/codesign --verify --strict "$app_dir"
print -r -- "$app_dir"
