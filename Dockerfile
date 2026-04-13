# --- 阶段 1: 安装 ---
FROM ubuntu:resolute AS installer

# 安装依赖
RUN apt-get update && \
    apt-get install -y libaio1 || apt-get install -y libaio1t64 && \
    rm -rf /var/lib/apt/lists/*

# 创建用户
RUN groupadd dinstall -g 2001 && \
    useradd -G dinstall -m -d /home/dmdba -s /bin/bash -u 2001 dmdba && \
    chmod 777 /tmp

# 复制文件
# 注意：这里直接复制 build.sh 解压好的所有内容
# 因为 build.sh 已经把 ISO 内容解压到了构建上下文根目录
COPY . /mnt/dmiso

# 复制静默安装配置文件
COPY setup.xml /tmp/setup.xml

# 执行安装
RUN echo "🔧 正在安装达梦数据库..." && \
    chmod +x /mnt/dmiso/DMInstall.bin && \
    runuser -l dmdba -c '/mnt/dmiso/DMInstall.bin -q /tmp/setup.xml' && \
    echo "✅ 安装完成。"

# --- 阶段 2: 运行 ---
FROM ubuntu:resolute

# 安装运行时依赖
RUN apt-get update && \
    (apt-get install -y libaio1 || apt-get install -y libaio1t64) && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd dinstall -g 2001 && \
    useradd -G dinstall -m -d /home/dmdba -s /bin/bash -u 2001 dmdba && \
    chmod 777 /tmp

# 复制安装好的程序
COPY --from=installer /home/dmdba/dmdb /home/dmdba/dmdbms

# 复制启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER dmdba
WORKDIR /home/dmdba

EXPOSE 5236
ENTRYPOINT ["/entrypoint.sh"]