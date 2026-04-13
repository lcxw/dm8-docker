# --- 阶段 1: 准备环境与安装 ---
FROM ubuntu:22.04 AS builder

# 设置非交互模式，避免安装时卡住
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y curl ca-certificates genisoimage sudo && \
    rm -rf /var/lib/apt/lists/*

# 创建达梦用户和组
RUN groupadd dinstall -g 2001 && \
    useradd -G dinstall -m -d /home/dmdba -s /bin/bash -u 2001 dmdba && \
    mkdir -p /mnt/dmiso && \
    chmod 777 /tmp

# 从外部传入下载地址和预期的 SHA256 (由 GitHub Actions 注入)
ARG DM_DOWNLOAD_URL
ARG DM_EXPECTED_SHA256

WORKDIR /tmp

# 1. 下载 ZIP 包
RUN echo "Downloading DM8..." && \
    curl -L -o dm8.zip ${DM_DOWNLOAD_URL} && \
    echo "Download completed."

# 2. 校验 SHA256
RUN echo "Verifying SHA256..." && \
    # 提取 ZIP 中的校验文件内容，并与传入的参数对比
    unzip -p dm8.zip $(unzip -Z1 dm8.zip | grep -i SHA256.txt) | cut -d' ' -f1 > actual_sha256.txt && \
    echo "Expected: ${DM_EXPECTED_SHA256}" && \
    echo "Actual: $(cat actual_sha256.txt)" && \
    # 简单的字符串对比，如果失败则报错
    if [ "$(cat actual_sha256.txt)" != "${DM_EXPECTED_SHA256}" ]; then \
        echo "ERROR: SHA256 mismatch! Possible file corruption or tampering."; \
        exit 1; \
    fi && \
    echo "SHA256 verified successfully."

# 3. 解压 ISO 文件
RUN echo "Extracting ISO from ZIP..." && \
    # 解压 ZIP 中的 ISO 文件
    unzip dm8.zip $(unzip -Z1 dm8.zip | grep .iso) && \
    # 挂载 ISO 镜像 (需要特权模式，但在构建阶段通常可行，或者使用 unsquashfs 方式，这里使用简单的复制)
    # 由于 Docker BuildKit 支持 --mount=type=cache，但为了通用性，我们直接解压 ISO 内容
    mkdir /tmp/dmiso-content && \
    # 使用 7z 或 mount，但为了兼容性，推荐安装 archivemount 或直接解包 (这里使用 7z 方案)
    apt-get update && apt-get install -y p7zip-full && \
    7z x *.iso -o/tmp/dmiso-content -y && \
    # 清理下载包节省空间
    rm dm8.zip *.iso

# --- 阶段 2: 安装 ---
FROM ubuntu:22.04 AS installer

# 安装依赖
RUN apt-get update && \
    apt-get install -y sudo libaio1 && \
    rm -rf /var/lib/apt/lists/*

# 创建用户
RUN groupadd dinstall -g 2001 && \
    useradd -G dinstall -m -d /home/dmdba -s /bin/bash -u 2001 dmdba && \
    chmod 777 /tmp

# 从 builder 阶段复制解压出来的安装文件
COPY --from=builder /tmp/dmiso-content /mnt/dmiso

# 复制静默安装配置文件 (需在 Git 中)
COPY setup.xml /tmp/setup.xml

# 执行静默安装
RUN echo "Starting DM8 Installation..." && \
    # 确保安装文件有执行权限
    chmod +x /mnt/dmiso/DMInstall.bin && \
    # 以 dmdba 用户身份运行安装程序
    runuser -l dmdba -c '/mnt/dmiso/DMInstall.bin -q /tmp/setup.xml' && \
    echo "Installation completed."

# --- 阶段 3: 运行 ---
FROM ubuntu:22.04

# 安装运行时依赖
RUN apt-get update && \
    apt-get install -y sudo libaio1 && \
    rm -rf /var/lib/apt/lists/*

# 创建用户
RUN groupadd dinstall -g 2001 && \
    useradd -G dinstall -m -d /home/dmdba -s /bin/bash -u 2001 dmdba && \
    mkdir -p /opt/dmdbms && \
    chmod 777 /tmp

# 从 installer 阶段复制安装好的程序
COPY --from=installer /home/dmdba/dmdbms /home/dmdba/dmdbms

# 复制启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 切换用户
USER dmdba
WORKDIR /home/dmdba

EXPOSE 5236
ENTRYPOINT ["/entrypoint.sh"]