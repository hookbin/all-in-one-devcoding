FROM lscr.io/linuxserver/code-server:latest

USER root

ARG MONGO_VERSION=7.0.5
ARG MONGO_OS=ubuntu2204
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    PATH=/opt/npm-global/bin:$PATH \
    ME_CONFIG_MONGODB_URL=mongodb://127.0.0.1:27017/ \
    ME_CONFIG_SITE_BASEURL=/express/ \
    NODE_ENV=development \
    APP_DIR=/config/app \
    NGINX_DIR=/config/nginx \
    TOTP_DIR=/config/totp \
    TOTP_PORT=4180 \
    PM2_HOME=/config/logs/pm2

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git vim nano wget nginx procps netcat-openbsd && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g pnpm yarn pm2 nodemon mongo-express otplib && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# MongoDB 7.0.5 bundled binary; current image supports linux/amd64.
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) MONGO_ARCH="x86_64" ;; \
      *) echo "Unsupported TARGETARCH=$TARGETARCH. Build for linux/amd64."; exit 1 ;; \
    esac; \
    curl -fL "https://fastdl.mongodb.org/linux/mongodb-linux-${MONGO_ARCH}-${MONGO_OS}-${MONGO_VERSION}.tgz" \
      -o /tmp/mongodb.tgz; \
    tar -xzf /tmp/mongodb.tgz -C /tmp; \
    cp /tmp/mongodb-linux-${MONGO_ARCH}-${MONGO_OS}-${MONGO_VERSION}/bin/* /usr/local/bin/; \
    rm -rf /tmp/mongodb.tgz /tmp/mongodb-linux-${MONGO_ARCH}-${MONGO_OS}-${MONGO_VERSION}

RUN mkdir -p \
        /opt/npm-global \
        /config/app \
        /config/www \
        /config/totp \
        /config/logs \
        /config/logs/nginx \
        /config/logs/mongodb \
        /config/logs/mongo-express \
        /config/logs/node-app \
        /config/logs/totp \
        /config/logs/code-server \
        /config/logs/pm2 \
        /config/mongo_data \
        /config/nginx \
        /etc/services.d && \
    chown -R abc:abc \
        /opt/npm-global \
        /config

# Keep the image default outside /config because /config/nginx is a bind mount.
COPY docker/nginx/nginx.conf /opt/default-nginx.conf
COPY docker/totp/server.js /opt/totp-server.js
COPY docker/services/ /etc/services.d/
COPY docker/www/ /opt/default-www/

RUN chmod +x /etc/services.d/*/run && \
    chown -R abc:abc \
        /opt/npm-global \
        /opt/default-www \
        /config && \
    nginx -t -c /opt/default-nginx.conf && \
    apt-get clean

EXPOSE 8000

# Persistent data/config directories.
VOLUME ["/config/app", "/config/www", "/config/totp", "/config/logs", "/config/mongo_data", "/config/nginx"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health >/dev/null || exit 1
