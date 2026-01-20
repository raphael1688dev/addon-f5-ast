#!/bin/bash
set -e

echo "Starting F5 Telemetry All-in-One (v2.1.3 God Mode)..."

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
RAW_LOG=$(jq --raw-output '.log_level' $CONFIG_PATH)

# Force Debug Level for this test
LOG="debug"

# Regex (Keep the fix)
FILTER_REGEX="bigip[._]scraper.*"
ENABLE_SYSTEM=$(jq --raw-output '.enable_system' $CONFIG_PATH)
[ "$ENABLE_SYSTEM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip[._](cpu|memory|system|disk|filesystem).*"
ENABLE_LTM=$(jq --raw-output '.enable_ltm' $CONFIG_PATH)
[ "$ENABLE_LTM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip[._](virtual_server|pool|node|rule).*"
ENABLE_NET=$(jq --raw-output '.enable_net' $CONFIG_PATH)
[ "$ENABLE_NET" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip[._](interface|vlan|arp).*"
ENABLE_ASM=$(jq --raw-output '.enable_asm' $CONFIG_PATH)
[ "$ENABLE_ASM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip[._]asm.*"
ENABLE_GTM=$(jq --raw-output '.enable_gtm' $CONFIG_PATH)
[ "$ENABLE_GTM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip[._](gtm|wideip|dns).*"
ENABLE_APM=$(jq --raw-output '.enable_apm' $CONFIG_PATH)
[ "$ENABLE_APM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip[._](apm|access).*"
ENABLE_AFM=$(jq --raw-output '.enable_afm' $CONFIG_PATH)
[ "$ENABLE_AFM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|bigip[._](afm|firewall|dos).*"

echo "Target F5: $HOST"
echo "Log Level: $LOG"

# --- 3. Generate OTel Config with DEBUG Exporter ---
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
  # 1. Real output
  prometheusremotewrite:
    endpoint: "http://127.0.0.1:9090/api/v1/write"
    tls:
      insecure: true
  
  # 2. Debug output (Print everything to console)
  debug:
    verbosity: detailed

service:
  telemetry:
    logs:
      level: "${LOG}"
  pipelines:
    metrics:
      receivers: [bigip]
      # 暫時移除 Filter，看看是不是 Filter 寫錯導致擋光光
      # processors: [filter] 
      processors: [] 
      exporters: [prometheusremotewrite, debug]
EOF

echo "Starting F5 OTel Collector (Debug Mode)..."
exec /usr/local/bin/otelcol-custom --config /app/otel-config.yaml
