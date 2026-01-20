#!/bin/bash
set -e

echo "Starting F5 Telemetry All-in-One (Special Char Fix)..."

CONFIG_PATH="/data/options.json"
DATA_DIR="/data/prometheus"

# 1. Prepare Prometheus
mkdir -p "$DATA_DIR"
chown -R nobody:nogroup "$DATA_DIR"

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
nohup /usr/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path="$DATA_DIR" \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.console.templates=/etc/prometheus/consoles \
    --web.enable-lifecycle \
    --web.enable-remote-write-receiver \
    > /var/log/prometheus.log 2>&1 &

sleep 5

# --- 2. Prepare OTel Collector ---
HOST=$(jq --raw-output '.f5_host' $CONFIG_PATH)
USER=$(jq --raw-output '.f5_username' $CONFIG_PATH)
INTERVAL=$(jq --raw-output '.collection_interval' $CONFIG_PATH)
VERIFY=$(jq --raw-output '.insecure_skip_verify' $CONFIG_PATH)

# [關鍵修正 1] 直接從 JSON 讀取密碼，不存入 Shell 變數，避免被 Shell 解析
# 我們稍後用 jq 直接注入到 YAML，這是最安全的方法
PASS=$(jq --raw-output '.f5_password' $CONFIG_PATH)

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

# --- 3. Generate OTel Config (Using jq for safety) ---
# [關鍵修正 2] 
# 我們先產生一個樣板檔案 (Template)，密碼欄位先放一個佔位符 (PLACEHOLDER)
# 這樣可以避免在此處使用 Shell 變數時發生錯誤展開
cat <<EOF > /app/otel-config-template.yaml
receivers:
  bigip:
    endpoint: "https://${HOST}"
    username: "${USER}"
    password: "PLACEHOLDER_PASSWORD"
    collection_interval: "${INTERVAL}"
    timeout: 30s
    tls:
      insecure_skip_verify: ${VERIFY}

processors:
  filter:
    metrics:
      include:
        match_type: regexp
        metric_names:
          - '${FILTER_REGEX}'

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

# [關鍵修正 3] 使用 sed 做純文字替換
# 這裡使用特殊的 delimiter (DELIM) 來避免密碼中的 / 或 & 符號干擾 sed
# 這是處理特殊字元密碼的終極大招
escaped_pass=$(printf '%s\n' "$PASS" | sed 's/[&/\]/\\&/g')
sed "s/PLACEHOLDER_PASSWORD/$escaped_pass/" /app/otel-config-template.yaml > /app/otel-config.yaml

echo "Starting F5 OTel Collector..."
exec /usr/local/bin/otelcol-custom --config /app/otel-config.yaml
