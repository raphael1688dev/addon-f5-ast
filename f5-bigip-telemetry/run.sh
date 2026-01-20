#!/bin/bash
set -e

echo "Starting F5 Telemetry All-in-One (OTel + Prometheus)..."

CONFIG_PATH="/data/options.json"
DATA_DIR="/data/prometheus" # 持久化資料目錄

# 1. Prepare Prometheus Environment
mkdir -p "$DATA_DIR"
chown -R nobody:nogroup "$DATA_DIR" # 確保權限正確

# 產生 Prometheus 設定檔 (最小化設定)
# 注意：我們開啟了 remote-write receiver，這樣 OTel 才能寫入
cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
EOF

echo "Starting Built-in Prometheus..."
# 啟動 Prometheus 放在背景 (&)
# --web.enable-remote-write-receiver: 關鍵！允許 OTel 推資料進來
# --storage.tsdb.path: 關鍵！資料存在 /data 才不會消失
nohup /usr/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path="$DATA_DIR" \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.console.templates=/etc/prometheus/consoles \
    --web.enable-lifecycle \
    --web.enable-remote-write-receiver \
    > /var/log/prometheus.log 2>&1 &

# 等待 5 秒確保 Prometheus 啟動完成
sleep 5

# --- 2. Prepare OTel Collector ---
HOST=$(jq --raw-output '.f5_host' $CONFIG_PATH)
USER=$(jq --raw-output '.f5_username' $CONFIG_PATH)
PASS=$(jq --raw-output '.f5_password' $CONFIG_PATH)
INTERVAL=$(jq --raw-output '.collection_interval' $CONFIG_PATH)
VERIFY=$(jq --raw-output '.insecure_skip_verify' $CONFIG_PATH)
export F5_PASSWORD="$PASS"

# Log Level
RAW_LOG=$(jq --raw-output '.log_level' $CONFIG_PATH)
if [[ -z "$RAW_LOG" ]] || [[ "$RAW_LOG" == "null" ]]; then LOG="info"; else LOG=$(echo "$RAW_LOG" | tr '[:upper:]' '[:lower:]'); fi
if [[ ! "$LOG" =~ ^(debug|info|warn|error)$ ]]; then LOG="info"; fi

# Filter Logic
FILTER_REGEX="bigip\.scraper.*"

ENABLE_SYSTEM=$(jq --raw-output '.enable_system' $CONFIG_PATH)
[ "$ENABLE_SYSTEM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip\.(cpu|memory|system|disk|filesystem).*"

ENABLE_LTM=$(jq --raw-output '.enable_ltm' $CONFIG_PATH)
[ "$ENABLE_LTM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip\.(virtual_server|pool|node|rule).*"

ENABLE_NET=$(jq --raw-output '.enable_net' $CONFIG_PATH)
[ "$ENABLE_NET" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip\.(interface|vlan|arp).*"

# Security Modules
ENABLE_ASM=$(jq --raw-output '.enable_asm' $CONFIG_PATH)
[ "$ENABLE_ASM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip\.asm.*"

ENABLE_GTM=$(jq --raw-output '.enable_gtm' $CONFIG_PATH)
[ "$ENABLE_GTM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip\.(gtm|wideip|dns).*"

ENABLE_APM=$(jq --raw-output '.enable_apm' $CONFIG_PATH)
[ "$ENABLE_APM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip\.(apm|access).*"

ENABLE_AFM=$(jq --raw-output '.enable_afm' $CONFIG_PATH)
[ "$ENABLE_AFM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip\.(afm|firewall|dos).*"

echo "Target F5: $HOST"
echo "Internal Prometheus: http://127.0.0.1:9090/api/v1/write"
echo "Filter Regex: $FILTER_REGEX"

# Generate OTel Config
# 重點：Endpoint 指向本機 localhost:9090
cat <<EOF > /app/otel-config.yaml
receivers:
  bigip:
    endpoint: "https://${HOST}"
    username: "${USER}"
    password: "\${env:F5_PASSWORD}"
    collection_interval: "${INTERVAL}"
    tls:
      insecure_skip_verify: ${VERIFY}

processors:
  filter:
    metrics:
      include:
        match_type: regexp
        metric_names:
          - "${FILTER_REGEX}"

exporters:
  prometheusremotewrite:
    endpoint: "http://127.0.0.1:9090/api/v1/write"
    tls:
      insecure: true

service:
  telemetry:
    logs:
      level: "${LOG}"
  pipelines:
    metrics:
      receivers: [bigip]
      processors: [filter]
      exporters: [prometheusremotewrite]
EOF

echo "Starting F5 OTel Collector..."
exec /usr/local/bin/otelcol-custom --config /app/otel-config.yaml
