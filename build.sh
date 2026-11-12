#!/bin/bash
# DrawShot.app をビルドするスクリプト
# 必要なもの: Xcode Command Line Tools (xcode-select --install)
set -e

APP_NAME="DrawShot"
BUNDLE_ID="com.example.drawshot"

echo "==> Swift コードをコンパイル中..."
swiftc -O DrawShot.swift -o "$APP_NAME" -framework Cocoa -framework Carbon -framework ScreenCaptureKit -framework ServiceManagement

echo "==> アプリバンドルを作成中..."
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mv "$APP_NAME" "$APP_NAME.app/Contents/MacOS/"

cat > "$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

# ad-hoc 署名(画面収録の許可をアプリに紐付けるため)
codesign --force --deep --sign - "$APP_NAME.app"

echo ""
echo "✅ 完了! 以下で起動できます:"
echo "   open $APP_NAME.app"
echo ""
echo "※ 初回のスクショ保存時に「画面収録」の権限を求められます。"
echo "   システム設定 > プライバシーとセキュリティ > 画面収録 で DrawShot を許可後、アプリを再起動してください。"
