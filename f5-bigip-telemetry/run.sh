#!/bin/bash
set -e

echo "Starting F5 BIG-IP Telemetry Add-on..."

CONFIG_PATH="/data/options.json"

# 1. Read Inputs
HOST=$(jq --raw-output '.f5_host' $CONFIG_PATH)
USER=$(jq --raw-output '.f5_username' $CONFIG_PATH)
PASS=$(jq --raw-output '.f5_password' $CONFIG_PATH)
INTERVAL=$(jq --raw-output '.collection_interval' $CONFIG_PATH)
VERIFY=$(jq --raw-output '.insecure_skip_verify' $CONFIG_PATH)

# --- SECURITY FIX: Handle Special Characters in Password ---
# Export password to environment variable.
# This prevents YAML syntax errors if password contains " or \ or $
export F5_PASSWORD="$PASS"
# -----------------------------------------------------------

# --- LOGIC: Smart Log Level ---
RAW_LOG=$(jq --raw-output '.log_level' $CONFIG_PATH)

# If null or empty, default to "info"
if [[ "$RAW_LOG" == "null" ]] || [[ -z "$RAW_LOG" ]]; then
    LOG="info"
    echo "Notice: log_level is empty. Defaulting to 'info'."
else
    # Convert to lowercase (DEBUG -> debug)
    LOG=$(echo "$RAW_LOG" | tr '[:upper:]' '[:lower:]')
fi

# Validate (Fallback to info if invalid)
if [[ ! "$LOG" =~ ^(debug|info|warn|error)$ ]]; then
    echo "Warning: Invalid log_level '$LOG'. Falling back to 'info'."
    LOG="info"
fi
# ------------------------------

# 2. Read Module Flags
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

# 3. Generate OTel Config
# NOTE: We use "\${env:F5_PASSWORD}" to let OTel read from env var directly.
cat <<EOF > /app/otel-config.yaml
receivers:
  bigip:
    endpoint: "https://${HOST}"
    username: "${USER}"
    password: "\${env:F5_PASSWORD}"
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

# 4. Start Collector
echo "Starting Collector binary..."
exec /usr/local/bin/otelcol-custom --config /app/otel-config.yaml
