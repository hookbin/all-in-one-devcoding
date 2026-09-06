# syntax=docker/dockerfile:1

FROM lscr.io/linuxserver/code-server:latest

USER root

# ============================================================
# Build Arguments
# ============================================================

ARG MONGO_VERSION=7.0.5
ARG MONGO_OS=ubuntu2204
ARG TARGETARCH

# ============================================================
# Environment
# ============================================================

ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    PATH=/opt/npm-global/bin:$PATH \
    PM2_HOME=/config/.pm2

# ============================================================
# System Packages
# ============================================================

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        wget \
        nginx \
        procps \
        netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

# ============================================================
# Node.js 20
# ============================================================

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ============================================================
# Node.js Development Tools
# ============================================================

RUN npm install -g \
        pnpm \
        yarn \
        pm2 \
        nodemon \
        mongo-express && \
    npm cache clean --force

# ============================================================
# MongoDB
#
# Current supported architecture:
#   linux/amd64
#
# MongoDB listens on localhost only at runtime.
# It must NOT be exposed through Docker port mapping.
# ============================================================

RUN set -eux; \
    if [ "$TARGETARCH" != "amd64" ]; then \
        echo "MongoDB currently supports linux/amd64 only"; \
        exit 1; \
    fi; \
    curl -fL \
        "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${MONGO_OS}-${MONGO_VERSION}.tgz" \
        -o /tmp/mongodb.tgz; \
    tar -xzf /tmp/mongodb.tgz -C /tmp; \
    cp \
        "/tmp/mongodb-linux-x86_64-${MONGO_OS}-${MONGO_VERSION}/bin/"* \
        /usr/local/bin/; \
    rm -rf \
        /tmp/mongodb.tgz \
        "/tmp/mongodb-linux-x86_64-${MONGO_OS}-${MONGO_VERSION}"

# ============================================================
# Runtime Directories
# ============================================================

RUN mkdir -p \
        /config/app \
        /config/www \
        /config/mongo_data \
        /config/logs \
        /config/logs/nginx \
        /config/nginx \
        /config/.pm2 && \
    chown -R 1000:1000 /config

# ============================================================
# Default Nginx Configuration
#
# The actual Nginx configuration will be provided by:
#
#   docker/nginx/nginx.conf
#
# It is copied outside /config so that a bind-mounted
# /config/nginx does not remove the image default.
# ============================================================

COPY docker/nginx/nginx.conf /opt/default-nginx.conf

RUN nginx -t -c /opt/default-nginx.conf

# ============================================================
# External HTTP Entry Point
#
# Nginx:
#   0.0.0.0:8000
#
# Internal services:
#   code-server    127.0.0.1:8080
#   Node.js        127.0.0.1:3000
#   mongo-express  127.0.0.1:8081
#   MongoDB        127.0.0.1:27017
# ============================================================

EXPOSE 8000

# ============================================================
# Health Check
# ============================================================

HEALTHCHECK \
    --interval=30s \
    --timeout=5s \
    --start-period=30s \
    --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health || exit 1
