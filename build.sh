#!/bin/bash
# ============================================================
# DeepSeekTokenMenu 构建脚本
# 编译 Swift 源码并打包为 .app 可执行程序
# ============================================================
set -e

echo "🚀 开始构建 DeepSeek Token Menu..."

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. 检查 Xcode 命令行工具
if ! xcode-select -p &>/dev/null; then
    echo "❌ 错误: 未安装 Xcode 命令行工具"
    echo "   运行: xcode-select --install"
    exit 1
fi

# 2. 编译
echo "📦 编译项目..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ 编译失败"
    exit 1
fi

# 3. 创建 .app 包
APP_NAME="DeepSeekTokenMenu"
BUILD_DIR=".build/release"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "📁 创建 App 包..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 复制可执行文件
cp "${BUILD_DIR}/${APP_NAME}" "$MACOS_DIR/"

# 复制 Info.plist
cp "Info.plist" "$CONTENTS_DIR/"

# 复制图标资源（如果有）
if [ -d "Resources/Assets.xcassets" ]; then
    cp -r "Resources/Assets.xcassets" "$RESOURCES_DIR/"
fi

# 4. 签名（可选，用于本地运行）
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    echo "🔏 签名..."
    codesign --force --sign "$CODE_SIGN_IDENTITY" "$APP_DIR"
fi

echo ""
echo "✅ 构建完成!"
echo "   App: $(pwd)/${APP_DIR}"
echo ""
echo "运行方式:"
echo "   方式一: open ${APP_DIR}"
echo "   方式二: ./${APP_DIR}/Contents/MacOS/${APP_NAME} (前台运行，查看日志)"
echo ""
echo "💡 提示: 将 ${APP_DIR} 拖到「应用程序」文件夹即可安装"
