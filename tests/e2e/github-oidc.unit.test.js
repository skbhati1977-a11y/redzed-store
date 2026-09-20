const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { test } = require("node:test");
const { AUDIENCE, verifyGithubOidc, resetKeyCache } = require("../../api/_github-oidc");

const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
const kid = "test-key";
const publicJwk = publicKey.export({ format: "jwk" });

function token(overrides = {}) {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: "RS256", kid, typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({
    iss: "https://token.actions.githubusercontent.com",
    aud: AUDIENCE,
    repository: "skbhati1977-a11y/redzed-store",
    ref: "refs/heads/test71-real-chat-e2e-finalization",
    workflow_ref: "skbhati1977-a11y/redzed-store/.github/workflows/test71-checkpoint0-e2e.yml@refs/heads/test71-real-chat-e2e-finalization",
    iat: now,
    nbf: now - 5,
    exp: now + 300,
    ...overrides
  })).toString("base64url");
  const signature = crypto.sign("RSA-SHA256", Buffer.from(`${header}.${payload}`), privateKey).toString("base64url");
  return `${header}.${payload}.${signature}`;
}

async function keys() {
  return { ok: true, json: async () => ({ keys: [{ ...publicJwk, kid, use: "sig", alg: "RS256" }] }) };
}

test("accepts a signed TEST71 workflow identity", async () => {
  resetKeyCache();
  const identity = await verifyGithubOidc(token(), keys);
  assert.equal(identity.repository, "skbhati1977-a11y/redzed-store");
});

test("rejects a signed identity from another branch", async () => {
  resetKeyCache();
  await assert.rejects(
    verifyGithubOidc(token({ ref: "refs/heads/main" }), keys),
    /Invalid runner identity/
  );
});

test("rejects an expired workflow identity", async () => {
  resetKeyCache();
  await assert.rejects(
    verifyGithubOidc(token({ exp: Math.floor(Date.now() / 1000) - 1 }), keys),
    /Invalid runner identity/
  );
});
