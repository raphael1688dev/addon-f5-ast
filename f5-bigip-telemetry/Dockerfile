# Stage 1: F5 Official Binary
FROM ghcr.io/f5devcentral/application-study-tool/otel_custom_collector:v0.9.6 AS source

# Stage 2: Runtime (Ubuntu)
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install dependencies (curl, sed, jq)
# 注意：我們移除了 'prometheus'，改手動安裝
RUN apt-get update && apt-get install -y \
    jq \
    bash \
    ca-certificates \
    curl \
    sed \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Official Prometheus (v2.50.1)
# 下載 -> 解壓 -> 移動執行檔 -> 移動設定檔
RUN curl -LO https://github.com/prometheus/prometheus/releases/download/v2.50.1/prometheus-2.50.1.linux-amd64.tar.gz \
    && tar -xvf prometheus-2.50.1.linux-amd64.tar.gz \
    && mv prometheus-2.50.1.linux-amd64/prometheus /usr/local/bin/ \
    && mv prometheus-2.50.1.linux-amd64/promtool /usr/local/bin/ \
    && mkdir -p /etc/prometheus \
    && mv prometheus-2.50.1.linux-amd64/consoles /etc/prometheus/ \
    && mv prometheus-2.50.1.linux-amd64/console_libraries /etc/prometheus/ \
    && rm -rf prometheus-2.50.1.linux-amd64.tar.gz prometheus-2.50.1.linux-amd64

# Copy OTel binary
COPY --from=source /otelcol-custom /usr/local/bin/otelcol-custom

# Copy script
COPY run.sh /run.sh
RUN chmod +x /run.sh

WORKDIR /app
CMD [ "/run.sh" ]
