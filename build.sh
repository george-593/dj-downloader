#!/bin/bash
# Builds DJ.app (Apple Silicon + Intel) and a zip ready to send to people.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/DJ.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -enable-bare-slash-regex -target "$arch-apple-macos13.0" DJ.swift -o "build/obj/DJ-$arch"
done
lipo -create build/obj/DJ-* -output "$APP/Contents/MacOS/DJ"

cp install-dj.command "$APP/Contents/Resources/"
swift make-icon.swift build/obj/icon.png
mkdir build/obj/DJ.iconset
for size in 16 32 128 256 512; do
  sips -z $size $size build/obj/icon.png --out "build/obj/DJ.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) build/obj/icon.png --out "build/obj/DJ.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/obj/DJ.iconset -o "$APP/Contents/Resources/DJ.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DJ</string>
  <key>CFBundleDisplayName</key><string>DJ</string>
  <key>CFBundleIdentifier</key><string>com.george.dj</string>
  <key>CFBundleExecutable</key><string>DJ</string>
  <key>CFBundleIconFile</key><string>DJ</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Ad-hoc sign so macOS treats the bundle as intact after zipping
codesign --force --deep --sign - "$APP"
ditto -c -k --keepParent "$APP" build/DJ.zip
rm -rf build/obj
echo "Built $APP and build/DJ.zip"
