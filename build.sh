#!/bin/bash

set -e # 遇到错误立即退出

# ================= 配置区域 =================
# 远程下载地址 (建议填 Gitee Release 链接，或者官方链接)
REMOTE_URL="https://download.dameng.com/eco/adapter/DM8/202512/dm8_20251203_x86_Ubuntu22_64.zip"
# 模拟的来源页面 (根据你的下载源修改，比如达梦官网首页)
FAKE_REFERER="https://www.dameng.com/"
# 模拟的浏览器 UA (这里使用最新的 Chrome on Windows)
FAKE_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
# 如果不想下载，把下面这行改成 true
FORCE_DOWNLOAD=false
# =============================================

BUILD_DIR="./build_context"
IMAGE_NAME="dameng8-ubuntu22:latest"

# 1. 清理并创建构建目录
echo "🧹 清理构建目录..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
# 1. 创建构建目录
mkdir -p "$BUILD_DIR"

# 2. 核心逻辑：检查是否已经解压好了 DMInstall.bin
# 如果这个文件存在，说明我们已经准备好安装环境了，直接跳过下载和解压
# 2. 核心逻辑：检测本地文件
# 优先检测当前目录（与 Dockerfile 同级）是否有 DMInstall.bin
if [ -f "./DMInstall.bin" ]; then
    echo "✅ 发现本地已解压的安装文件 (./DMInstall.bin)，直接使用，跳过下载和解压。"

    # 直接复制到构建目录
    # 注意：DMInstall.bin 通常位于 ISO 解压后的根目录
    cp ./DMInstall.bin "$BUILD_DIR/"

    # 如果还有其他必须的依赖文件（如 install 目录等），也建议在这里判断并复制
    # 但通常达梦安装只需要 DMInstall.bin 和同级的一些 xml 文件
    # 如果你是把整个 ISO 内容都解压出来了，建议复制整个目录结构，或者只复制必要的
else
    echo "⚠️ 未找到安装文件，开始准备下载和解压..."

    # --- 下载阶段 ---
    PACKAGE_FILE=$(basename "$REMOTE_URL")

    # 如果本地当前目录没有压缩包，则下载
    if [ ! -f "$PACKAGE_FILE" ]; then
        echo "📥 正在下载安装包..."
        curl -L \
             -A "$FAKE_UA" \
             -e "$FAKE_REFERER" \
             -H "Connection: keep-alive" \
             -H "Accept: */*" \
             -H "Accept-Encoding: gzip, deflate, br" \
             -o "$PACKAGE_FILE" \
             "$REMOTE_URL"
    else
        echo "📦 本地已存在压缩包 $PACKAGE_FILE，跳过下载。"
    fi

    # --- 校验阶段 ---
    # 检查下载的文件大小
    if [ -f "$PACKAGE_FILE" ]; then
        FILE_SIZE=$(stat -c%s "$PACKAGE_FILE" 2>/dev/null || stat -f%z "$PACKAGE_FILE") # 兼容 Linux/Mac
        echo "🔍 下载文件校验中... 文件大小: $FILE_SIZE 字节"

        # 如果文件小于 1MB (1048576 字节)，极有可能是下载失败（如 HTML 错误页）
        if [ "$FILE_SIZE" -lt 1048576 ]; then
            echo "❌ 错误：下载的文件过小 (< 1MB)，可能不是有效的安装包。"
            echo "👇 以下是文件内容预览（用于调试）："
            echo "--------------------------------"
            # 使用 head 防止文件过大刷屏，cat 查看完整内容
            head -n 50 "$PACKAGE_FILE"
            echo "--------------------------------"
            exit 1
        fi
    fi

    # --- 解压阶段 ---
    echo "📦 正在解压安装包到 $BUILD_DIR ..."

    # 确保安装了 p7zip
    if ! command -v 7z &> /dev/null; then
        echo "❌ 错误：未找到 7z 命令，请安装 p7zip-full (sudo apt install p7zip-full)"
        exit 1
    fi

    if [[ "$PACKAGE_FILE" == *.zip ]]; then
        # 处理 ZIP -> ISO -> 文件
        echo "检测到 ZIP 格式，正在提取 ISO..."
        unzip -q -o "$PACKAGE_FILE" "*.iso" -d /tmp/dm_temp_unzip
        ISO_FILE=$(ls /tmp/dm_temp_unzip/*.iso 2>/dev/null | head -n 1)

        if [ -z "$ISO_FILE" ]; then
            echo "❌ 在 ZIP 包中未找到 ISO 文件"
            exit 1
        fi

        echo "正在解压 ISO 内容..."
        7z x "$ISO_FILE" -o"$BUILD_DIR" -y -q
        rm -rf /tmp/dm_temp_unzip

    elif [[ "$PACKAGE_FILE" == *.iso ]]; then
        # 直接解压 ISO
        7z x "$PACKAGE_FILE" -o"$BUILD_DIR" -y -q
    else
        echo "❌ 不支持的文件格式: $PACKAGE_FILE"
        exit 1
    fi

    echo "✅ 解压完成。"
fi

echo "✅ 解压完成，准备构建..."

# 5. 复制必要的配置文件
# 确保 setup.xml 和 entrypoint.sh 也在构建目录中
cp setup.xml "$BUILD_DIR/"
cp entrypoint.sh "$BUILD_DIR/"

# 6. 执行 Docker Build
echo "🚀 开始构建 Docker 镜像..."
docker build -t "$IMAGE_NAME" -f Dockerfile "$BUILD_DIR"

# 7. 清理 (可选，如果想保留解压文件可以注释掉)
# rm -rf "$BUILD_DIR"

echo "🎉 构建成功！镜像名称: $IMAGE_NAME"

# 判断是否要推送 (如果传入了 "push" 参数)
PUSH_FLAG=""
# 使用 buildx 构建
# 如果是 push 模式，直接 --push
# 如果不是 push 模式，需要 --load 到本地 docker 镜像列表，否则后面 docker push 找不到镜像
if [ "$1" == "push" ]; then
    docker buildx build -t "$IMAGE_NAME" -f Dockerfile "$BUILD_DIR" --push
else
    docker buildx build -t "$IMAGE_NAME" -f Dockerfile "$BUILD_DIR" --load
fi
# 执行 Docker Build
# 注意：这里不需要指定 --push，我们用 docker tag 和 docker push 分离处理，或者直接用 buildx
echo "🚀 开始构建 Docker 镜像..."

# 为了保证兼容性，我们先用标准 build 命令
docker build -t "$IMAGE_NAME" -f Dockerfile "$BUILD_DIR"

# 如果要求推送，执行 push 命令
if [ "$1" == "push" ]; then
    echo "📤 正在推送镜像到仓库..."
    docker push "$IMAGE_NAME"
fi

# ... (清理逻辑) ...