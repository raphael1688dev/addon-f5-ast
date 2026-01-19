#!/bin/bash
set -e

echo "Starting F5 BIG-IP Telemetry Add-on..."

CONFIG_PATH="/data/options.json"

# 1. 讀取連線資訊
HOST=$(jq --raw-output '.f5_host' $CONFIG_PATH)
USER=$(jq --raw-output '.f5_username' $CONFIG_PATH)
PASS=$(jq --raw-output '.f5_password' $CONFIG_PATH)
INTERVAL=$(jq --raw-output '.collection_interval' $CONFIG_PATH)
VERIFY=$(jq --raw-output '.insecure_skip_verify' $CONFIG_PATH)

# [關鍵修改] 讀取 log_level (處理 Array 格式，取第一個值)
LOG=$(jq --raw-output '.log_level[0] // "info"' $CONFIG_PATH)

# 2. 讀取模組狀態
ENABLE_SYSTEM=$(jq --raw-output '.enable_system' $CONFIG_PATH)
ENABLE_LTM=$(jq --raw-output '.enable_ltm' $CONFIG_PATH)
ENABLE_NET=$(jq --raw-output '.enable_net' $CONFIG_PATH)
ENABLE_ASM=$(jq --raw-output '.enable_asm' $CONFIG_PATH)
ENABLE_GTM=$(jq --raw-output '.enable_gtm' $CONFIG_PATH)
ENABLE_APM=$(jq --raw-output '.enable_apm' $CONFIG_PATH)
ENABLE_AFM=$(jq --raw-output '.enable_afm' $CONFIG_PATH)
ENABLE_PEM=$(jq --raw-output '.enable_pem' $CONFIG_PATH)
ENABLE_AVR=$(jq --raw-output '.enable_avr' $CONFIG_PATH)
ENABLE_VCMP=$(jq --raw-output '.enable_vcmp' $CONFIG_PATH)

echo "Target Host: $HOST"
echo "Log Level: $LOG"
echo "Modules Active: System=$ENABLE_SYSTEM, LTM=$ENABLE_LTM"

# 3. 生成 OTel 設定檔
cat <<EOF > /app/otel-config.yaml
receivers:
  bigip:
    endpoint: "https://${HOST}"
    username: "${USER}"
    password: "${PASS}"
    collection_interval: "${INTERVAL}"
    tls:
      insecure_skip_verify: ${VERIFY}
    modules:
      system: ${ENABLE_SYSTEM}
      ltm: ${ENABLE_LTM}
      net: ${ENABLE_NET}
      asm: ${ENABLE_ASM}
      gtm: ${ENABLE_GTM}
      apm: ${ENABLE_APM}
      afm: ${ENABLE_AFM}
      pem: ${ENABLE_PEM}
      avr: ${ENABLE_AVR}
      vcmp: ${ENABLE_VCMP}

exporters:
  prometheus:
    endpoint: "0.0.0.0:8888"
    namespace: "f5_telemetry"

service:
  telemetry:
    logs:
      level: "${LOG}"
  pipelines:
    metrics:
      receivers: [bigip]
      exporters: [prometheus]
EOF

# 4. 啟動
echo "Starting Collector binary..."
exec /usr/local/bin/otelcol-custom --config /app/otel-config.yaml
