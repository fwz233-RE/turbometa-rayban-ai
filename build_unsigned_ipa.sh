#!/bin/bash

# TurboMeta 无签名 IPA 构建脚本
# 使用方法: ./build_unsigned_ipa.sh
# 
# 生成的 IPA 可以使用以下工具签名安装:
# - AltStore (https://altstore.io/)
# - Sideloadly (https://sideloadly.io/)
# - 其他第三方签名工具

set -e

# 配置
PROJECT_NAME="CameraAccess"
SCHEME_NAME="TurboMeta"
BUILD_DIR="build"
OUTPUT_DIR="output"
IPA_NAME="TurboMeta"

echo "🚀 开始构建 TurboMeta 无签名 IPA..."
echo "================================================"

# 清理之前的构建
echo "📁 清理之前的构建文件..."
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# 检查 xcodebuild 是否可用
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误: xcodebuild 未找到"
    echo "请确保已安装 Xcode 并运行: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# 构建项目 (Release 配置，目标为真机)
echo ""
echo "🔨 正在构建项目 (Release 配置)..."
echo "这可能需要几分钟，请耐心等待..."

xcodebuild \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    clean build 2>&1 | tee build.log

# 检查构建是否成功
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "❌ 构建失败！请检查 build.log 文件查看详细错误信息"
    exit 1
fi

# 查找生成的 .app 文件
APP_PATH=$(find "$BUILD_DIR" -name "*.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ 错误: 未找到构建生成的 .app 文件"
    exit 1
fi

echo ""
echo "✅ 构建成功！"
echo "📦 .app 路径: $APP_PATH"

# 创建 IPA 包
echo ""
echo "📦 正在打包 IPA..."

# 创建 Payload 目录
mkdir -p "$OUTPUT_DIR/Payload"

# 复制 .app 到 Payload
cp -r "$APP_PATH" "$OUTPUT_DIR/Payload/"

# 进入输出目录并压缩
cd "$OUTPUT_DIR"
zip -r -q "${IPA_NAME}.ipa" Payload

# 清理 Payload 目录
rm -rf Payload

# 回到项目目录
cd ..

echo ""
echo "================================================"
echo "🎉 构建完成！"
echo ""
echo "📱 IPA 文件位置: $(pwd)/$OUTPUT_DIR/${IPA_NAME}.ipa"
echo ""
echo "📥 安装方法:"
echo "   1. 使用 AltStore: https://altstore.io/"
echo "   2. 使用 Sideloadly: https://sideloadly.io/"
echo "   3. 其他第三方签名工具"
echo ""
echo "💡 提示: 接收者需要用自己的 Apple ID 签名才能安装"
echo "================================================"
