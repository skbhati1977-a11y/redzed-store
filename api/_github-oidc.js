const crypto = require("node:crypto");

const ISSUER = "https://token.actions.githubusercontent.com";
const AUDIENCE = "redzed-test71-e2e";
const REPOSITORY = "skbhati1977-a11y/redzed-store";
const REF = "refs/heads/test71-real-chat-e2e-finalization";
const WORKFLOW_REF_PREFIX = `${REPOSITORY}/.github/workflows/test71-checkpoint0-e2e.yml@${REF}`;

let cachedKeys = null;
let cachedUntil = 0;

function decodePart(part) {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

async function getKeys(fetchImpl) {
  if (cachedKeys && Date.now() < cachedUntil) return cachedKeys;
  const result = await fetchImpl(`${ISSUER}/.well-known/jwks`, {
    headers: { Accept: "application/json" }
  });
  if (!result.ok) throw new Error("OIDC keys unavailable");
  const body = await result.json();
  if (!Array.isArray(body?.keys) || !body.keys.length) throw new Error("OIDC keys unavailable");
  cachedKeys = body.keys;
  cachedUntil = Date.now() + 5 * 60 * 1000;
  return cachedKeys;
}

async function verifyGithubOidc(token, fetchImpl = fetch) {
  const parts = String(token || "").split(".");
  if (parts.length !== 3) throw new Error("Invalid runner identity");
  const header = decodePart(parts[0]);
  const payload = decodePart(parts[1]);
  if (header.alg !== "RS256" || !header.kid) throw new Error("Invalid runner identity");
  const keys = await getKeys(fetchImpl);
  const jwk = keys.find((key) => key.kid === header.kid && key.kty === "RSA");
  if (!jwk) throw new Error("Invalid runner identity");
  const verified = crypto.verify(
    "RSA-SHA256",
    Buffer.from(`${parts[0]}.${parts[1]}`),
    crypto.createPublicKey({ key: jwk, format: "jwk" }),
    Buffer.from(parts[2], "base64url")
  );
  if (!verified) throw new Error("Invalid runner identity");

  const now = Math.floor(Date.now() / 1000);
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (
    payload.iss !== ISSUER ||
    !audiences.includes(AUDIENCE) ||
    payload.repository !== REPOSITORY ||
    payload.ref !== REF ||
    !String(payload.workflow_ref || "").startsWith(WORKFLOW_REF_PREFIX) ||
    !Number.isFinite(payload.exp) || payload.exp <= now ||
    !Number.isFinite(payload.iat) || payload.iat > now + 60 ||
    (Number.isFinite(payload.nbf) && payload.nbf > now + 60)
  ) throw new Error("Invalid runner identity");
  return payload;
}

function resetKeyCache() {
  cachedKeys = null;
  cachedUntil = 0;
}

module.exports = { AUDIENCE, verifyGithubOidc, resetKeyCache };
