# Stage 1: 鎖定 F5 OTel Collector 版本 v0.9.6 (避免 latest 風險)
FROM ghcr.io/f5devcentral/application-study-tool/otel_custom_collector:v0.9.6 AS source

# Stage 2: 使用 Ubuntu 22.04 確保 glibc 相容性
FROM ubuntu:22.04

# 設定非互動模式
ENV DEBIAN_FRONTEND=noninteractive

# 安裝 jq (解析 JSON), bash (執行腳本), ca-certificates (HTTPS)
RUN apt-get update && apt-get install -y \
    jq \
    bash \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 複製 F5 執行檔
COPY --from=source /otelcol-custom /usr/local/bin/otelcol-custom

# 複製並授權啟動腳本
COPY run.sh /run.sh
RUN chmod +x /run.sh

WORKDIR /app
CMD [ "/run.sh" ]
