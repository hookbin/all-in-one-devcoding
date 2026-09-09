const crypto = require("crypto");

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function encodeBase32(input) {
  let accumulator = 0;
  let bits = 0;
  let encoded = "";

  for (const byte of input) {
    accumulator = (accumulator << 8) | byte;
    bits += 8;

    while (bits >= 5) {
      bits -= 5;
      encoded += BASE32_ALPHABET[(accumulator >>> bits) & 31];
    }

    accumulator &= (1 << bits) - 1;
  }

  if (bits > 0) {
    encoded += BASE32_ALPHABET[(accumulator << (5 - bits)) & 31];
  }

  return encoded;
}

function decodeBase32(secret) {
  const normalized = String(secret)
    .trim()
    .toUpperCase()
    .replace(/=+$/, "")
    .replace(/[\s-]/g, "");

  if (!normalized || !/^[A-Z2-7]+$/.test(normalized)) {
    throw new Error("TOTP secret must be a non-empty Base32 string");
  }

  let accumulator = 0;
  let bits = 0;
  const decoded = [];

  for (const character of normalized) {
    accumulator = (accumulator << 5) | BASE32_ALPHABET.indexOf(character);
    bits += 5;

    while (bits >= 8) {
      bits -= 8;
      decoded.push((accumulator >>> bits) & 255);
    }

    accumulator &= (1 << bits) - 1;
  }

  return Buffer.from(decoded);
}

function generateSecret(byteLength = 20) {
  if (!Number.isInteger(byteLength) || byteLength < 16) {
    throw new Error("TOTP secret must contain at least 16 random bytes");
  }

  return encodeBase32(crypto.randomBytes(byteLength));
}

function generateTotp(
  secret,
  { timestamp = Date.now(), period = 30, digits = 6, offset = 0 } = {}
) {
  if (!Number.isInteger(period) || period <= 0) {
    throw new Error("TOTP period must be a positive integer");
  }
  if (!Number.isInteger(digits) || digits < 6 || digits > 8) {
    throw new Error("TOTP digits must be between 6 and 8");
  }

  const counterValue = Math.floor(timestamp / 1000 / period) + offset;
  if (!Number.isSafeInteger(counterValue) || counterValue < 0) {
    throw new Error("Invalid TOTP timestamp");
  }

  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(counterValue));

  const digest = crypto
    .createHmac("sha1", decodeBase32(secret))
    .update(counter)
    .digest();
  const digestOffset = digest[digest.length - 1] & 15;
  const binaryCode =
    ((digest[digestOffset] & 127) << 24) |
    ((digest[digestOffset + 1] & 255) << 16) |
    ((digest[digestOffset + 2] & 255) << 8) |
    (digest[digestOffset + 3] & 255);

  return String(binaryCode % 10 ** digits).padStart(digits, "0");
}

function verifyTotp(
  token,
  secret,
  { timestamp = Date.now(), period = 30, digits = 6, window = 1 } = {}
) {
  const normalizedToken = String(token).trim();
  if (!new RegExp(`^\\d{${digits}}$`).test(normalizedToken)) {
    return false;
  }
  if (!Number.isInteger(window) || window < 0 || window > 120) {
    throw new Error("TOTP window must be an integer between 0 and 120");
  }

  const received = Buffer.from(normalizedToken);
  for (let offset = -window; offset <= window; offset += 1) {
    const expected = Buffer.from(
      generateTotp(secret, { timestamp, period, digits, offset })
    );
    if (crypto.timingSafeEqual(received, expected)) {
      return true;
    }
  }

  return false;
}

function createSessionToken(
  secret,
  { timestamp = Date.now(), ttlSeconds = 86400 } = {}
) {
  if (!Number.isInteger(ttlSeconds) || ttlSeconds <= 0) {
    throw new Error("Session TTL must be a positive integer");
  }

  const payload = Buffer.from(
    JSON.stringify({
      version: 1,
      issuedAt: timestamp,
      expiresAt: timestamp + ttlSeconds * 1000,
      nonce: crypto.randomBytes(16).toString("base64url")
    })
  ).toString("base64url");
  const signature = crypto
    .createHmac("sha256", decodeBase32(secret))
    .update("nginx-admin-session-v1\0")
    .update(payload)
    .digest("base64url");

  return `${payload}.${signature}`;
}

function verifySessionToken(token, secret, { timestamp = Date.now() } = {}) {
  try {
    const [payload, signature, extra] = String(token).split(".");
    if (!payload || !signature || extra !== undefined) {
      return false;
    }

    const expectedSignature = crypto
      .createHmac("sha256", decodeBase32(secret))
      .update("nginx-admin-session-v1\0")
      .update(payload)
      .digest("base64url");
    const received = Buffer.from(signature);
    const expected = Buffer.from(expectedSignature);
    if (
      received.length !== expected.length ||
      !crypto.timingSafeEqual(received, expected)
    ) {
      return false;
    }

    const session = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    return (
      session.version === 1 &&
      Number.isSafeInteger(session.issuedAt) &&
      Number.isSafeInteger(session.expiresAt) &&
      session.issuedAt <= timestamp &&
      session.expiresAt > timestamp &&
      typeof session.nonce === "string" &&
      session.nonce.length > 0
    );
  } catch (error) {
    return false;
  }
}

function createProvisioningUri(
  secret,
  { issuer = "All-in-One DevCoding", account = "nginx-admin" } = {}
) {
  const label = `${encodeURIComponent(issuer)}:${encodeURIComponent(account)}`;
  const query = new URLSearchParams({
    secret,
    issuer,
    algorithm: "SHA1",
    digits: "6",
    period: "30"
  });
  return `otpauth://totp/${label}?${query}`;
}

module.exports = {
  createProvisioningUri,
  decodeBase32,
  encodeBase32,
  generateSecret,
  generateTotp,
  createSessionToken,
  verifySessionToken,
  verifyTotp
};
