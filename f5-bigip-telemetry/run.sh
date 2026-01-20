#!/bin/bash
set -e

echo "Starting F5 Telemetry All-in-One (v2.0.6 Metrics Fix)..."

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

echo "Starting Built-in Prometheus (Official v2.50.1)..."
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

# --- 2. Prepare F5 OTel Collector ---
HOST=$(jq --raw-output '.f5_host' $CONFIG_PATH)
USER=$(jq --raw-output '.f5_username' $CONFIG_PATH)
PASS=$(jq --raw-output '.f5_password' $CONFIG_PATH)
INTERVAL=$(jq --raw-output '.collection_interval' $CONFIG_PATH)
VERIFY=$(jq --raw-output '.insecure_skip_verify' $CONFIG_PATH)

# Log Level
RAW_LOG=$(jq --raw-output '.log_level' $CONFIG_PATH)
if [[ -z "$RAW_LOG" ]] || [[ "$RAW_LOG" == "null" ]]; then LOG="info"; else LOG=$(echo "$RAW_LOG" | tr '[:upper:]' '[:lower:]'); fi
if [[ ! "$LOG" =~ ^(debug|info|warn|error)$ ]]; then LOG="info"; fi

# Filter Regex
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
[ "$ENABLE_AP
