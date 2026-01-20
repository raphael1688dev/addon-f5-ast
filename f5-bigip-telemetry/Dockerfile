# Stage 1: F5 OTel Binary
FROM ghcr.io/f5devcentral/application-study-tool/otel_custom_collector:v0.9.6 AS source

# Stage 2: Runtime Environment (Ubuntu)
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 安裝 jq, bash 以及 prometheus
RUN apt-get update && apt-get install -y \
    jq \
    bash \
    ca-certificates \
    prometheus \
    && rm -rf /var/lib/apt/lists/*

# Copy OTel binary
COPY --from=source /otelcol-custom /usr/local/bin/otelcol-custom

# Copy script
COPY run.sh /run.sh
RUN chmod +x /run.sh

WORKDIR /app
CMD [ "/run.sh" ]
