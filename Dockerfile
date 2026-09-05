FROM lscr.io/linuxserver/code-server:latest

USER root

ARG MONGO_VERSION=7.0.5
ARG MONGO_OS=ubuntu2204
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    PATH=/opt/npm-global/bin:$PATH \
    PM2_HOME=/config/.pm2

# --------------------------------------------------
# Basic system tools + Nginx
# --------------------------------------------------

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

# --------------------------------------------------
# Node.js 20
# --------------------------------------------------

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# --------------------------------------------------
# Node.js development tools
# --------------------------------------------------

RUN npm install -g \
        pnpm \
        yarn \
        pm2 \
        nodemon \
        mongo-express && \
    npm cache clean --force

# --------------------------------------------------
# MongoDB
#
# Current target: linux/amd64
# MongoDB is an internal service.
# --------------------------------------------------

RUN set -eux; \
    if [ "$TARGETARCH" != "amd64" ]; then \
        echo "MongoDB currently supports linux/amd64 only"; \
        exit 1; \
    fi; \
    curl -fL \
        "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-${MONGO_OS}-${MONGO_VERSION}.tgz" \
        -o /tmp/mongodb.tgz; \
    tar -xzf /tmp/mongodb.tgz -C /tmp; \
    cp /tmp/mongodb-linux-x86_64-${MONGO_OS}-${MONGO_VERSION}/bin/* /usr/local/bin/; \
    rm -rf /tmp/mongodb*

# --------------------------------------------------
# Basic directories
# --------------------------------------------------

RUN mkdir -p \
        /config/app \
        /config/www \
        /config/mongo_data \
        /config/logs \
        /config/nginx && \
    chown -R abc:abc /config

# --------------------------------------------------
# Nginx default configuration
# --------------------------------------------------

COPY docker/nginx/nginx.conf /opt/default-nginx.conf

RUN nginx -t -c /opt/default-nginx.conf

# --------------------------------------------------
# Exposed service
#
# Only Nginx is exposed externally.
# Other services communicate through localhost.
# --------------------------------------------------

EXPOSE 8000

# --------------------------------------------------
# Persistent data
# --------------------------------------------------

VOLUME [
    "/config"
]

# --------------------------------------------------
# Health check
# --------------------------------------------------

HEALTHCHECK \
    --interval=30s \
    --timeout=5s \
    --start-period=30s \
    --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health || exit 1