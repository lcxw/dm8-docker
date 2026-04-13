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

# 2. 寻找安装包函数
find_package() {
    # 优先找当前目录下的 zip 或 iso
    if [ -f "dm8.zip" ]; then echo "dm8.zip"; return 0; fi
    if [ -f "DM8.zip" ]; then echo "DM8.zip"; return 0; fi
    # 达梦官方文件名通常很长，这里用通配符查找
    local file=$(ls dm8_*.zip 2>/dev/null | head -n 1)
    if [ -n "$file" ]; then echo "$file"; return 0; fi

    local iso=$(ls dm8_*.iso 2>/dev/null | head -n 1)
    if [ -n "$iso" ]; then echo "$iso"; return 0; fi

    return 1
}

# 3. 获取安装包 (本地查找 或 远程下载)
PACKAGE_FILE=""

if [ "$FORCE_DOWNLOAD" = false ]; then
    PACKAGE_FILE=$(find_package) || true
fi

if [ -n "$PACKAGE_FILE" ]; then
    echo "✅ 发现本地安装包: $PACKAGE_FILE"
else
    echo "⚠️ 本地未找到安装包，开始从远程下载..."
    # 提取文件名
    PACKAGE_FILE=$(basename "$REMOTE_URL")

    # 使用 curl 下载
    if [ -f "$PACKAGE_FILE" ]; then
        echo "文件已存在，跳过下载"
    else
        curl -v \
             -L \
             -A "$FAKE_UA" \
             -e "$FAKE_REFERER" \
             --compressed \
             -H "Connection: keep-alive" \
             -H "Accept: */*" \
             -H "Accept-Encoding: gzip, deflate, br" \
             -o "$PACKAGE_FILE" \
             "$REMOTE_URL"
    fi

    # 简单校验文件大小 (防止下载了 HTML 错误页面)
    if [ ! -s "$PACKAGE_FILE" ]; then
        echo "❌ 下载失败：文件为空或不存在"
        exit 1
    fi
    echo "✅ 下载完成: $PACKAGE_FILE"
fi

# 4. 解压安装包
# 达梦安装通常需要 ISO 内的完整目录结构，所以我们把 ISO 内容解压出来
echo "📦 正在解压安装包到 $BUILD_DIR ..."

if [[ "$PACKAGE_FILE" == *.zip ]]; then
    # 如果是 ZIP，先解压出 ISO，再解压 ISO
    # 注意：这里假设 ZIP 里只有一个 ISO，或者我们只取第一个 ISO
    unzip -q "$PACKAGE_FILE" "*.iso" -d /tmp/dm_temp_unzip
    ISO_FILE=$(ls /tmp/dm_temp_unzip/*.iso | head -n 1)

    # 解压 ISO 内容到构建目录
    7z x "$ISO_FILE" -o"$BUILD_DIR" -y -q

    # 清理临时文件
    rm -rf /tmp/dm_temp_unzip

elif [[ "$PACKAGE_FILE" == *.iso ]]; then
    # 如果是 ISO，直接解压
    7z x "$PACKAGE_FILE" -o"$BUILD_DIR" -y -q
else
    echo "❌ 不支持的文件格式: $PACKAGE_FILE"
    exit 1
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