#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
task_build_dir=$(mktemp -d /private/tmp/WattsBuild.XXXXXX)
trap 'rm -rf "$task_build_dir"' EXIT
mkdir -p "$task_build_dir/Fluxa.app/Contents/MacOS" "$task_build_dir/Fluxa.app/Contents/Resources"
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macos13.0 -framework AppKit -framework IOKit -framework ServiceManagement -import-objc-header Sources/IOReport.h -lIOReport -framework SwiftUI -framework WidgetKit Shared/*.swift Sources/*.swift -o "$task_build_dir/Fluxa.app"/Contents/MacOS/Fluxa
cat > "$task_build_dir/Fluxa.app"/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Fluxa</string>
<key>CFBundleIdentifier</key><string>local.hanchao.Watts</string>
<key>CFBundleName</key><string>Fluxa</string>
<key>CFBundleDisplayName</key><string>Fluxa</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4.1</string>
<key>CFBundleVersion</key><string>11</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Fluxa Devices</string><key>CFBundleURLSchemes</key><array><string>fluxa</string></array></dict></array>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>Fluxa</string>
</dict></plist>
PLIST
if [[ -f Resources/Fluxa.icns ]]; then cp Resources/Fluxa.icns "$task_build_dir/Fluxa.app"/Contents/Resources/; fi
task_runtime="$task_build_dir/Fluxa.app/Contents/Resources/libimobiledevice"
mkdir -p "$task_runtime/bin" "$task_runtime/lib"
cp Resources/libimobiledevice/lib/*.dylib "$task_runtime/lib/"
cp Resources/libimobiledevice/bin/idevice_id "$task_runtime/bin/"
xcrun clang -Os -target arm64-apple-macos13.0 Tools/device_probe.c -o "$task_runtime/bin/FluxaDeviceProbe"
for task_binary in "$task_runtime"/lib/*.dylib "$task_runtime"/bin/*; do
  if [[ $(lipo -archs "$task_binary") == *x86_64* ]]; then
    lipo "$task_binary" -thin arm64 -output "$task_binary.thin"
    mv "$task_binary.thin" "$task_binary"
  fi
  codesign --force --sign - "$task_binary"
done
if [[ -d Licenses ]]; then ditto --norsrc --noextattr Licenses "$task_build_dir/Fluxa.app/Contents/Resources/Licenses"; fi
if [[ -f THIRD_PARTY_NOTICES.md ]]; then cp THIRD_PARTY_NOTICES.md "$task_build_dir/Fluxa.app/Contents/Resources/"; fi
task_widget="$task_build_dir/Fluxa.app/Contents/PlugIns/FluxaWidget.appex"
xcodebuild -project FluxaWidget.xcodeproj -target FluxaWidget -configuration Release -sdk macosx -jobs 2 CONFIGURATION_BUILD_DIR="$task_build_dir/WidgetBuild" OBJROOT="$task_build_dir/WidgetObjects" CODE_SIGNING_ALLOWED=NO build > build/widget-build.log 2>&1
mkdir -p "$task_build_dir/Fluxa.app/Contents/PlugIns"
ditto --norsrc --noextattr "$task_build_dir/WidgetBuild/FluxaWidget.appex" "$task_widget"
codesign --force --sign - --entitlements Widget/Widget.entitlements "$task_widget"
xattr -cr "$task_build_dir/Fluxa.app"
codesign --force --sign - --identifier local.hanchao.Watts "$task_build_dir/Fluxa.app"
codesign --verify --strict "$task_build_dir/Fluxa.app"
mkdir -p build
stable_build_dir="$HOME/Library/Caches/local.hanchao.Watts/Build"
mkdir -p "$stable_build_dir"
rm -rf "$stable_build_dir/Fluxa.app"
ditto --norsrc --noextattr "$task_build_dir/Fluxa.app" "$stable_build_dir/Fluxa.app"
codesign --verify --strict "$stable_build_dir/Fluxa.app"
print -r -- "$stable_build_dir/Fluxa.app" > build/APP_PATH.txt
print "已生成：$stable_build_dir/Fluxa.app"
