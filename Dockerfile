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
    TZ=Asia/Shanghai \
    EXTENSIONS_GALLERY={"serviceUrl":"https://marketplace.visualstudio.com/_apis/public/gallery","itemUrl":"https://marketplace.visualstudio.com/items","resourceUrlTemplate":"https://{publisher}.vscode-unpkg.net/{publisher}/{name}/{version}/{path}"} \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    PATH=/opt/npm-global/bin:$PATH \
    NODE_PATH=/opt/npm-global/lib/node_modules \
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
        nodemon && \
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
    chown -R abc:abc /config

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

COPY docker/app/server.js /opt/default-node-app.js
COPY docker/app/package.json /opt/default-express-package.json
COPY docker/pm2/ecosystem.config.js /opt/default-ecosystem.config.js
COPY docker/www/index.html /opt/default-index.html

COPY docker/cont-init.d/10-runtime-directories /custom-cont-init.d/10-runtime-directories
RUN chmod +x /custom-cont-init.d/10-runtime-directories

COPY docker/services.d/nginx/run /etc/services.d/nginx/run
RUN chmod +x /etc/services.d/nginx/run

COPY docker/services.d/svc-code-server/run /etc/services.d/svc-code-server/run
RUN chmod +x /etc/services.d/svc-code-server/run

COPY docker/services.d/mongodb/run /etc/services.d/mongodb/run
RUN chmod +x /etc/services.d/mongodb/run

COPY docker/services.d/pm2/run /etc/services.d/pm2/run
RUN chmod +x /etc/services.d/pm2/run

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
