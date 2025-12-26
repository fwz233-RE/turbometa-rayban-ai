#!/bin/bash

# TurboMeta 签名 IPA 构建脚本
# 使用方法: ./build_signed_ipa.sh
#
# 前提条件:
# 1. 在 Xcode 中登录了 Apple ID
# 2. 启用了自动签名 (Automatically manage signing)

set -e

# 配置
PROJECT_NAME="CameraAccess"
SCHEME_NAME="TurboMeta"
BUILD_DIR="build_signed"
OUTPUT_DIR="output"
IPA_NAME="TurboMeta_signed"

echo "🚀 开始构建 TurboMeta 签名 IPA..."
echo "================================================"

# 清理之前的构建
echo "📁 清理之前的构建文件..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# 检查 xcodebuild 是否可用
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误: xcodebuild 未找到"
    echo "请确保已安装 Xcode 并运行: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

# 检查是否有有效的签名证书
IDENTITY_COUNT=$(security find-identity -v -p codesigning | grep "valid identities found" | awk '{print $1}')
if [ "$IDENTITY_COUNT" == "0" ]; then
    echo "❌ 错误: 未找到有效的代码签名证书"
    echo ""
    echo "请在 Xcode 中完成以下步骤:"
    echo "  1. 打开 Xcode → Settings → Accounts"
    echo "  2. 添加您的 Apple ID"
    echo "  3. 打开项目，选择 Target，在 Signing & Capabilities 中启用自动签名"
    echo "  4. 选择您的 Team"
    exit 1
fi

echo ""
echo "✅ 找到有效的签名证书"

# 构建并归档项目
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
    -allowProvisioningUpdates \
    clean build 2>&1 | tee build_signed.log

# 检查构建是否成功
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "❌ 构建失败！请检查 build_signed.log 文件查看详细错误信息"
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

# 验证签名
echo ""
echo "🔍 验证代码签名..."
codesign -vvv --deep --strict "$APP_PATH" 2>&1 || {
    echo "⚠️ 警告: 代码签名验证失败"
}

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
echo "   1. 直接通过 Xcode 安装到您的设备 (推荐)"
echo "   2. 使用 Apple Configurator 2"
echo "   3. 通过 Finder 同步到设备"
echo ""
echo "⚠️ 注意: 此 IPA 使用开发证书签名，仅能安装到您的设备上"
echo "   如需分发给他人，请使用 Ad Hoc 或 App Store 证书"
echo "================================================"
