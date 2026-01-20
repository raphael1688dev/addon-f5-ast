#!/bin/bash
set -e

echo "Starting F5 Telemetry All-in-One (v2.1.9 Doc Verified)..."

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

# --- 3. Doc-Verified Regex Construction ---

# [Group A] Core Essentials (Always On)
# 這些是 F5 運作的基礎，不論有無購買特殊模組都該有的數據。
# - scraper/collector/endpoint: 採集器自身狀態
# - system/plane: CPU, Memory, Disk, Blade status
# - license/module/nethsm: 授權與硬體狀態
# - network: Interface, VLAN (文件中 f5.network.*)
# - node: LTM 後端節點狀態
CORE_METRICS="scraper|collector|endpoint|system|plane|license|module|nethsm|network|node"

# [Group B] LTM Traffic & Profiles (Always On)
# - virtual_server/pool: 流量核心
# - rule: iRules 執行統計
# - profile.*: 各種協定 (tcp, udp, http, client_ssl) 的詳細統計
# - ssl_certificate: 憑證過期監控
LTM_METRICS="virtual_server|pool|rule|profile.*|ssl_certificate"

# [Group C] Policy Defaults (Always On)
# 根據文件，policy 下有一些通用的，如 eviction (資源回收) 和 bandwidth_control
POLICY_DEFAULTS="policy[._](eviction|bandwidth_control)"

# 組合基礎 Regex
FILTER_REGEX="(f5|bigip)[._]($CORE_METRICS|$LTM_METRICS|$POLICY_DEFAULTS).*"

# [Group D] Optional Modules (Config Controlled)
# 根據文件將 f5.policy.* 拆解到對應模組

# ASM / WAF (包含 f5.asm.* 和 f5.policy.asm.*)
ENABLE_ASM=$(jq --raw-output '.enable_asm' $CONFIG_PATH)
[ "$ENABLE_ASM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|(f5|bigip)[._](asm|policy[._]asm).*"

# GTM / DNS (包含 f5.gtm.* 和 f5.dns.*)
ENABLE_GTM=$(jq --raw-output '.enable_gtm' $CONFIG_PATH)
[ "$ENABLE_GTM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|(f5|bigip)[._](gtm|wideip|dns).*"

# APM / Access (包含 f5.apm.* 和 f5.policy.api_protection.*)
ENABLE_APM=$(jq --raw-output '.enable_apm' $CONFIG_PATH)
[ "$ENABLE_APM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|(f5|bigip)[._](apm|access|policy[._]api_protection).*"

# AFM / Firewall (包含 f5.firewall.*, f5.dos.*, f5.policy.firewall.*, f5.policy.ip_intelligence.*)
ENABLE_AFM=$(jq --raw-output '.enable_afm' $CONFIG_PATH)
[ "$ENABLE_AFM" == "true" ] && FILTER_REGEX="$FILTER_REGEX|(f5|bigip)[._](afm|firewall|dos|policy[._](firewall|ip_intelligence)).*"

# Network Extras (CGNAT/NAT) - (包含 f5.cgnat.* 和 f5.policy.nat.*)
ENABLE_NET=$(jq --raw-output '.enable_net' $CONFIG_PATH)
[ "$ENABLE_NET" == "true" ] && FILTER_REGEX="$FILTER_REGEX|(f5|bigip)[._](cgnat|policy[._]nat).*"

echo "Target F5: $HOST"
echo "Log Level: $LOG"
echo "Active Filter Regex: $FILTER_REGEX"

# --- 4. Generate OTel Config ---
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
