# Stage 1: Source specific version
FROM ghcr.io/f5devcentral/application-study-tool/otel_custom_collector:v0.9.6 AS source

# Stage 2: Runtime environment
FROM ubuntu:22.04

# Setup environment
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    jq \
    bash \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy binary
COPY --from=source /otelcol-custom /usr/local/bin/otelcol-custom

# Copy and permission script
COPY run.sh /run.sh
RUN chmod +x /run.sh

WORKDIR /app
CMD [ "/run.sh" ]
