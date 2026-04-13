FROM ubuntu:22.04 AS installer

RUN groupadd dinstall -g 2001 && \
    useradd -G dinstall -m -d /home/dmdba -s /bin/bash -u 2001 dmdba && \
    chmod 777 /tmp && \
    apt-get update && apt-get install sudo -y && rm -rf /var/lib/apt/lists/*

COPY DMInstall.bin /mnt/DMInstall.bin
COPY setup.xml /tmp/setup.xml
RUN sudo -u dmdba /mnt/DMInstall.bin -q /tmp/setup.xml

FROM ubuntu:22.04
RUN groupadd dinstall -g 2001 && \
    useradd -G dinstall -m -d /home/dmdba -s /bin/bash -u 2001 dmdba && \
    chmod 777 /tmp && \
    apt-get update && apt-get install sudo -y && rm -rf /var/lib/apt/lists/*
COPY --from=installer /home/dmdba/ /home/dmdba/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
USER root
EXPOSE 5236
ENTRYPOINT [ "/entrypoint.sh" ]