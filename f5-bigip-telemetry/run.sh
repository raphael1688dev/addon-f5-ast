#!/bin/bash
set -e

echo "Starting F5 Telemetry All-in-One (v2.1.4 Final Success)..."

CONFIG_PATH="/data/options.json"
DATA_DIR="/data/prometheus"

# --- 1. Start Internal Prometheus ---
mkdir -p "$DATA_DIR"
mkdir -p /etc/prometheus

# Generate Prometheus Config
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
/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path="$DATA_DIR" \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.console.templates=/etc/prometheus/consoles \
    --web.enable-lifecycle \
    --web.enable-remote-write-receiver \
    --web.listen-address="0.0.0.0:9090" \
    &

sleep 5

# --- 2. Prepare Variables ---
HOST=$(jq --raw-output '.f5_host' $CONFIG_PATH)
USER=$(jq --raw-output '.f5_username' $CONFIG_PATH)
PASS=$(jq --raw-output '.f5_password' $CONFIG_PATH)
INTERVAL=$(jq --raw-output '.collection_interval' $CONFIG_PATH)
VERIFY=$(jq --raw-output '.insecure_skip_verify' $CONFIG_PATH)

# Log Level
RAW_LOG=$(jq --raw-output '.log_level' $CONFIG_PATH)
if [[ -z "$RAW_LOG" ]] || [[ "$RAW_LOG" == "null" ]]; then LOG="info"; else LOG=$(echo "$RAW_LOG" | tr '[:upper:]' '[:lower:]'); fi
if [[ ! "$LOG" =~ ^(debug|info|warn|error)$ ]]; then LOG="info"; fi

# --- [關鍵修正] Filter Regex ---
# 改為最寬鬆的規則：只要是 bigip 開頭的指標，全部放行！
# 這保證了 Grafana 一定會有資料
FILTER_REGEX="bigip.*"

echo "Target F5: $HOST"
echo "Log Level: $LOG"
echo "Filter Regex: $FILTER_REGEX (Allow All)"

# --- 3. Generate OTel Config ---
SAFE_PASS=$(echo "$PASS" | jq -R .)

cat <<EOF > /app/otel-config.yaml
receivers:
  bigip:
    endpoint: "https://${HOST}"
    username: "${USER}"
    password: ${SAFE_PASS}
    collection_interval: "${INTERVAL}"
    timeout: 60s
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

echo "Starting F5 OTel Collector..."
exec /usr/local/bin/otelcol-custom --config /app/otel-config.yaml
