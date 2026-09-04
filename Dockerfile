FROM lscr.io/linuxserver/code-server:latest

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    PATH=/opt/npm-global/bin:$PATH \
    ME_CONFIG_MONGODB_URL=mongodb://127.0.0.1:27017/ \
    ME_CONFIG_SITE_BASEURL=/express/ \
    NODE_ENV=development \
    APP_DIR=/config/app \
    TOTP_DIR=/config/totp \
    TOTP_PORT=4180

# Base packages + Node.js 20
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        vim \
        nano \
        wget \
        nginx \
        openssl \
        procps \
        netcat-openbsd && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g \
        pnpm \
        yarn \
        pm2 \
        nodemon \
        mongo-express \
        otplib && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# MongoDB 7.0.5.
# linux/amd64: works with the official MongoDB tarball.
# linux/arm64: use a MongoDB-compatible ARM64 image/package instead; this
# image intentionally fails the build rather than silently installing x86_64.
ARG TARGETARCH
RUN set -eux; \
    if [ "$TARGETARCH" = "amd64" ]; then \
        curl -fL "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-7.0.5.tgz" -o /tmp/mongo.tgz; \
    else \
        echo "Unsupported TARGETARCH=$TARGETARCH for bundled MongoDB 7.0.5 binary." >&2; \
        echo "Build this image for linux/amd64, or replace MongoDB with an ARM64-compatible package/image." >&2; \
        exit 1; \
    fi; \
    tar -xzf /tmp/mongo.tgz -C /tmp; \
    cp /tmp/mongodb-linux-x86_64-ubuntu2204-7.0.5/bin/* /usr/local/bin/; \
    rm -rf /tmp/mongo*

# Global npm packages are writable by abc without modifying system binaries.
RUN mkdir -p /opt/npm-global /config/app /config/www /config/totp /config/logs /config/mongo_data /config/nginx && \
    chown -R abc:abc /opt/npm-global /config

# Nginx configuration.
RUN cat > /config/nginx/nginx.conf <<'EOF'
events {}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    access_log /config/logs/nginx-access.log;
    error_log  /config/logs/nginx-error.log warn;

    sendfile on;
    keepalive_timeout 65;

    # Allow WebSocket/upgrade traffic used by code-server and development apps.
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen 8000;
        server_name _;

        # Container health endpoint. No authentication.
        location = /health {
            access_log off;
            default_type text/plain;
            return 200 "ok\n";
        }

        # Public static site. Put index.html and other static files in /config/www.
        location / {
            root /config/www;
            index index.html;
            try_files $uri $uri/ /index.html;
        }

        # Development application. No TOTP.
        # /app/foo -> http://127.0.0.1:3000/foo
        location /app/ {
            proxy_pass http://127.0.0.1:3000/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_buffering off;
        }

        # code-server. TOTP protected.
        location /vscode/ {
            auth_request /_totp_verify;
            error_page 401 = @totp_login;

            proxy_pass http://127.0.0.1:8080/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_buffering off;
        }

        # mongo-express. TOTP protected.
        location /express/ {
            auth_request /_totp_verify;
            error_page 401 = @totp_login;

            proxy_pass http://127.0.0.1:8081/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        }

        # TOTP login UI/API. Intentionally public because it is the login gate.
        location /totp/ {
            proxy_pass http://127.0.0.1:4180/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        }

        # Internal authentication subrequest.
        location = /_totp_verify {
            internal;
            proxy_pass http://127.0.0.1:4180/verify;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Original-URI $request_uri;
            proxy_set_header X-Original-Method $request_method;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header Cookie $http_cookie;
        }

        # Unauthenticated protected request -> TOTP login page.
        location @totp_login {
            proxy_pass http://127.0.0.1:4180/login;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Original-URI $request_uri;
            proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        }
    }
}
EOF

# Minimal TOTP authentication service.
RUN cat > /opt/totp-server.js <<'EOF'
'use strict';

const http = require('http');
const fs = require('fs');
const crypto = require('crypto');
const { authenticator } = require('otplib');

const PORT = Number(process.env.TOTP_PORT || 4180);
const SECRET_FILE = process.env.TOTP_SECRET_FILE || '/config/totp/secret';
const SESSION_TTL = Number(process.env.TOTP_SESSION_TTL || 8 * 60 * 60 * 1000);

function ensureSecret() {
    fs.mkdirSync('/config/totp', { recursive: true });
    if (!fs.existsSync(SECRET_FILE)) {
        const secret = authenticator.generateSecret();
        fs.writeFileSync(SECRET_FILE, secret + '\n', { mode: 0o600 });
        console.log('Generated TOTP secret at ' + SECRET_FILE);
        console.log('TOTP secret: ' + secret);
        console.log('Create an authenticator entry with this secret.');
        console.log('Delete/recreate the secret file only if you intentionally want to reset TOTP.');
    }
    return fs.readFileSync(SECRET_FILE, 'utf8').trim();
}

const SECRET = ensureSecret();
const sessions = new Map();

function parseCookies(header) {
    const out = {};
    for (const part of (header || '').split(';')) {
        const i = part.indexOf('=');
        if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
    }
    return out;
}

function newSession() {
    const token = crypto.randomBytes(32).toString('base64url');
    sessions.set(token, Date.now() + SESSION_TTL);
    return token;
}

function validSession(req) {
    const token = parseCookies(req.headers.cookie).totp_session;
    if (!token) return false;
    const expires = sessions.get(token);
    if (!expires) return false;
    if (expires < Date.now()) {
        sessions.delete(token);
        return false;
    }
    return true;
}

function htmlEscape(s) {
    return String(s || '').replace(/[&<>"']/g, c => ({
        '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
    }[c]));
}

function send(res, status, body, headers = {}) {
    res.writeHead(status, {
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Security-Policy': "default-src 'self'; style-src 'unsafe-inline'; form-action 'self'",
        'X-Content-Type-Options': 'nosniff',
        ...headers
    });
    res.end(body);
}

function loginPage(returnTo, error = '') {
    return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TOTP Login</title>
<style>
body{font-family:system-ui,sans-serif;max-width:420px;margin:15vh auto;padding:24px}
input{width:100%;box-sizing:border-box;padding:12px;font-size:24px;letter-spacing:6px;text-align:center}
button{width:100%;margin-top:12px;padding:12px;font-size:18px}
.error{color:#b00020;margin-bottom:12px}
</style></head>
<body>
<h1>TOTP Login</h1>
${error ? `<div class="error">${htmlEscape(error)}</div>` : ''}
<form method="post" action="/totp/verify-code">
<input name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" pattern="[0-9]{6}" autofocus required>
<input type="hidden" name="return" value="${htmlEscape(returnTo)}">
<button type="submit">Verify</button>
</form>
</body></html>`;
}

const server = http.createServer((req, res) => {
    try {
        if (req.method === 'GET' && req.url === '/verify') {
            return res.writeHead(validSession(req) ? 204 : 401).end();
        }

        if (req.method === 'GET' && req.url.startsWith('/login')) {
            const returnTo = req.headers['x-original-uri'] || '/vscode/';
            if (validSession(req)) {
                return res.writeHead(302, { Location: returnTo }).end();
            }
            return send(res, 200, loginPage(returnTo));
        }

        if (req.method === 'GET' && req.url === '/') {
            return res.writeHead(404).end();
        }

        if (req.method === 'POST' && req.url === '/verify-code') {
            let data = '';
            req.on('data', chunk => {
                data += chunk;
                if (data.length > 4096) req.destroy();
            });
            req.on('end', () => {
                const params = new URLSearchParams(data);
                const code = (params.get('code') || '').replace(/\D/g, '');
                let returnTo = params.get('return') || '/vscode/';
                if (!returnTo.startsWith('/')) returnTo = '/vscode/';

                const ok = code.length === 6 && authenticator.check(code, SECRET);
                if (!ok) return send(res, 401, loginPage(returnTo, 'Invalid code.'));

                const token = newSession();
                return send(res, 302, '', {
                    'Set-Cookie': `totp_session=${encodeURIComponent(token)}; Max-Age=${Math.floor(SESSION_TTL/1000)}; Path=/; HttpOnly; Secure; SameSite=Strict`,
                    'Location': returnTo
                });
            });
            return;
        }

        if (req.method === 'POST' && req.url === '/logout') {
            const token = parseCookies(req.headers.cookie).totp_session;
            if (token) sessions.delete(token);
            return send(res, 302, '', {
                'Set-Cookie': 'totp_session=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Strict',
                'Location': '/'
            });
        }

        res.writeHead(404).end();
    } catch (err) {
        console.error(err);
        res.writeHead(500).end();
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`TOTP service listening on 127.0.0.1:${PORT}`);
});
EOF

# s6 services
RUN mkdir -p /etc/services.d/mongodb /etc/services.d/mongo-express /etc/services.d/node-app /etc/services.d/totp /etc/services.d/nginx && \
cat > /etc/services.d/mongodb/run <<'EOF'
#!/command/with-contenv bash
exec 2>&1
mkdir -p /config/mongo_data /config/logs
chown -R abc:abc /config/mongo_data /config/logs

if pgrep -u abc -x mongod >/dev/null 2>&1; then
    echo "MongoDB already running."
    exec tail -f /dev/null
fi

exec s6-setuidgid abc mongod \
    --bind_ip 127.0.0.1 \
    --port 27017 \
    --dbpath /config/mongo_data \
    --logpath /config/logs/mongo.log \
    --logappend
EOF

cat > /etc/services.d/mongo-express/run <<'EOF'
#!/command/with-contenv bash
exec 2>&1

echo "Waiting for MongoDB..."
until mongosh --quiet --host 127.0.0.1:27017 --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q '^1$'; do
    sleep 2
done

echo "MongoDB is ready. Starting mongo-express..."
export ME_CONFIG_MONGODB_URL="${ME_CONFIG_MONGODB_URL:-mongodb://127.0.0.1:27017/}"
export ME_CONFIG_SITE_BASEURL="${ME_CONFIG_SITE_BASEURL:-/express/}"
unset ME_CONFIG_BASICAUTH_USERNAME ME_CONFIG_BASICAUTH_PASSWORD

exec s6-setuidgid abc mongo-express
EOF

cat > /etc/services.d/node-app/run <<'EOF'
#!/command/with-contenv bash
exec 2>&1

APP_DIR="${APP_DIR:-/config/app}"

if [ ! -f "$APP_DIR/package.json" ]; then
    echo "No $APP_DIR/package.json; Node app service is idle."
    exec tail -f /dev/null
fi

echo "Waiting for MongoDB..."
until mongosh --quiet --host 127.0.0.1:27017 --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q '^1$'; do
    sleep 2
done

cd "$APP_DIR"

if [ ! -d node_modules ]; then
    echo "Installing npm dependencies..."
    pnpm install
fi

if node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.start ? 0 : 1)"; then
    echo "Starting Node app with PM2..."
    exec s6-setuidgid abc pm2-runtime start npm --name dev-app -- start
fi

echo "No package.json start script found; Node app service is idle."
exec tail -f /dev/null
EOF

cat > /etc/services.d/totp/run <<'EOF'
#!/command/with-contenv bash
exec 2>&1
mkdir -p /config/totp
chown -R abc:abc /config/totp
exec s6-setuidgid abc node /opt/totp-server.js
EOF

cat > /etc/services.d/nginx/run <<'EOF'
#!/command/with-contenv bash
exec 2>&1
mkdir -p /config/nginx /config/logs /config/www
exec nginx -c /config/nginx/nginx.conf -g 'daemon off;'
EOF

RUN chmod +x /etc/services.d/*/run /opt/totp-server.js && \
    cat > /etc/cont-init.d/10-webdev-init <<'EOF'
#!/command/with-contenv bash
set -e

mkdir -p /config/app /config/www /config/totp /config/logs /config/mongo_data /config/nginx
chown -R abc:abc /config/app /config/www /config/totp /config/logs /config/mongo_data /config/nginx

if [ ! -f /config/www/index.html ]; then
cat > /config/www/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Web Dev</title></head>
<body>
<h1>Web Development Environment</h1>
<ul>
  <li><a href="/app/">App</a></li>
  <li><a href="/vscode/">VS Code</a></li>
  <li><a href="/express/">Mongo Express</a></li>
</ul>
</body>
</html>
HTML
chown abc:abc /config/www/index.html
fi
EOF

RUN chmod +x /etc/cont-init.d/10-webdev-init && \
    nginx -t -c /config/nginx/nginx.conf && \
    apt-get clean

EXPOSE 8000

VOLUME ["/config"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health >/dev/null || exit 1

USER abc
