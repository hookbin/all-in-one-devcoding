const assert = require("assert");
const {
  createSessionToken,
  decodeBase32,
  encodeBase32,
  generateSecret,
  generateTotp,
  verifySessionToken,
  verifyTotp
} = require("../docker/app/totp");

const rfcSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
const rfcVectors = [
  [59, "94287082"],
  [1111111109, "07081804"],
  [1111111111, "14050471"],
  [1234567890, "89005924"],
  [2000000000, "69279037"],
  [20000000000, "65353130"]
];

for (const [seconds, expected] of rfcVectors) {
  const timestamp = seconds * 1000;
  assert.strictEqual(
    generateTotp(rfcSecret, { timestamp, digits: 8 }),
    expected
  );
  assert.strictEqual(
    verifyTotp(expected, rfcSecret, { timestamp, digits: 8, window: 0 }),
    true
  );
}

const generatedSecret = generateSecret();
assert.strictEqual(decodeBase32(generatedSecret).length, 20);
assert.strictEqual(
  encodeBase32(decodeBase32(rfcSecret)),
  rfcSecret
);

const currentTimestamp = Date.now();
const currentToken = generateTotp(generatedSecret, { timestamp: currentTimestamp });
assert.strictEqual(
  verifyTotp(currentToken, generatedSecret, { timestamp: currentTimestamp }),
  true
);
const toleranceEdgeToken = generateTotp(generatedSecret, {
  timestamp: currentTimestamp + 10 * 60 * 1000
});
assert.strictEqual(
  verifyTotp(toleranceEdgeToken, generatedSecret, {
    timestamp: currentTimestamp,
    window: 20
  }),
  true
);
const outsideToleranceToken = generateTotp(generatedSecret, {
  timestamp: currentTimestamp + 10.5 * 60 * 1000
});
assert.strictEqual(
  verifyTotp(outsideToleranceToken, generatedSecret, {
    timestamp: currentTimestamp,
    window: 20
  }),
  false
);
assert.strictEqual(
  verifyTotp("00000000", generatedSecret, { timestamp: currentTimestamp }),
  false
);

const sessionToken = createSessionToken(generatedSecret, {
  timestamp: currentTimestamp,
  ttlSeconds: 86400
});
assert.strictEqual(
  verifySessionToken(sessionToken, generatedSecret, {
    timestamp: currentTimestamp + 86400 * 1000 - 1
  }),
  true
);
assert.strictEqual(
  verifySessionToken(sessionToken, generatedSecret, {
    timestamp: currentTimestamp + 86400 * 1000
  }),
  false
);
assert.strictEqual(
  verifySessionToken(`${sessionToken}x`, generatedSecret, {
    timestamp: currentTimestamp
  }),
  false
);

console.log("TOTP RFC 6238 and signed-session validation passed.");
