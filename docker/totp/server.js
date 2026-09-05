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

        console.log(`Generated TOTP secret at ${SECRET_FILE}`);
        console.log(`TOTP secret: ${secret}`);
        console.log('Add this secret to your authenticator application.');
    }

    return fs.readFileSync(SECRET_FILE, 'utf8').trim();
}

const SECRET = ensureSecret();
const sessions = new Map();

function parseCookies(header = '') {
    const result = {};

    for (const part of header.split(';')) {
        const index = part.indexOf('=');

        if (index > 0) {
            const key = part.slice(0, index).trim();
            const value = part.slice(index + 1).trim();

            try {
                result[key] = decodeURIComponent(value);
            } catch {
                result[key] = value;
            }
        }
    }

    return result;
}

function createSession() {
    const token = crypto.randomBytes(32).toString('base64url');

    sessions.set(token, Date.now() + SESSION_TTL);

    return token;
}

function hasValidSession(req) {
    const token = parseCookies(req.headers.cookie).totp_session;

    if (!token) {
        return false;
    }

    const expires = sessions.get(token);

    if (!expires) {
        return false;
    }

    if (expires <= Date.now()) {
        sessions.delete(token);
        return false;
    }

    return true;
}

function escapeHtml(value = '') {
    return String(value).replace(/[&<>"']/g, char => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    }[char]));
}

function sendHtml(res, status, body, headers = {}) {
    res.writeHead(status, {
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Security-Policy':
            "default-src 'self'; style-src 'unsafe-inline'; form-action 'self'",
        'X-Content-Type-Options': 'nosniff',
        ...headers
    });

    res.end(body);
}

function renderLogin(returnTo, error = '') {
    return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TOTP Login</title>
<style>
body {
    font-family: system-ui, sans-serif;
    max-width: 420px;
    margin: 15vh auto;
    padding: 24px;
}
input {
    width: 100%;
    box-sizing: border-box;
    padding: 12px;
    font-size: 24px;
    letter-spacing: 6px;
    text-align: center;
}
button {
    width: 100%;
    margin-top: 12px;
    padding: 12px;
    font-size: 18px;
}
.error {
    color: #b00020;
    margin-bottom: 12px;
}
</style>
</head>
<body>
<h1>TOTP Login</h1>
${error ? `<div class="error">${escapeHtml(error)}</div>` : ''}
<form method="post" action="/totp/verify-code">
    <input
        name="code"
        inputmode="numeric"
        autocomplete="one-time-code"
        maxlength="6"
        pattern="[0-9]{6}"
        autofocus
        required
    >
    <input
        type="hidden"
        name="return"
        value="${escapeHtml(returnTo)}"
    >
    <button type="submit">Verify</button>
</form>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
    try {
        if (req.method === 'GET' && req.url === '/verify') {
            return res.writeHead(hasValidSession(req) ? 204 : 401).end();
        }

        if (req.method === 'GET' && req.url === '/login') {
            const returnTo = req.headers['x-original-uri'] || '/vscode/';

            if (hasValidSession(req)) {
                return res.writeHead(302, { Location: returnTo }).end();
            }

            return sendHtml(res, 200, renderLogin(returnTo));
        }

        if (req.method === 'POST' && req.url === '/verify-code') {
            let body = '';

            req.on('data', chunk => {
                body += chunk;

                if (body.length > 4096) {
                    req.destroy();
                }
            });

            req.on('end', () => {
                const params = new URLSearchParams(body);

                const code = (params.get('code') || '')
                    .replace(/\D/g, '');

                let returnTo = params.get('return') || '/vscode/';

                if (!returnTo.startsWith('/')) {
                    returnTo = '/vscode/';
                }

                const valid =
                    code.length === 6 &&
                    authenticator.check(code, SECRET);

                if (!valid) {
                    return sendHtml(
                        res,
                        401,
                        renderLogin(returnTo, 'Invalid code.')
                    );
                }

                const token = createSession();

                return sendHtml(res, 302, '', {
                    'Set-Cookie':
                        `totp_session=${encodeURIComponent(token)}; ` +
                        `Max-Age=${Math.floor(SESSION_TTL / 1000)}; ` +
                        `Path=/; HttpOnly; Secure; SameSite=Strict`,
                    Location: returnTo
                });
            });

            return;
        }

        if (req.method === 'POST' && req.url === '/logout') {
            const token = parseCookies(req.headers.cookie).totp_session;

            if (token) {
                sessions.delete(token);
            }

            return sendHtml(res, 302, '', {
                'Set-Cookie':
                    'totp_session=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Strict',
                Location: '/'
            });
        }

        res.writeHead(404).end();
    } catch (error) {
        console.error(error);
        res.writeHead(500).end();
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`TOTP service listening on 127.0.0.1:${PORT}`);
});
