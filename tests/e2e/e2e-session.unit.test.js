const assert = require("node:assert/strict");
const { test } = require("node:test");
const handler = require("../../api/e2e-session");

function response() {
  return {
    code: null,
    body: null,
    headers: {},
    setHeader(key, value) { this.headers[key] = value; },
    status(code) { this.code = code; return this; },
    json(body) { this.body = body; return this; }
  };
}

async function invoke(environment, branch) {
  const previous = {
    environment: process.env.VERCEL_ENV,
    branch: process.env.VERCEL_GIT_COMMIT_REF,
    secret: process.env.E2E_TEST_BOOTSTRAP_SECRET
  };
  process.env.VERCEL_ENV = environment;
  process.env.VERCEL_GIT_COMMIT_REF = branch;
  delete process.env.E2E_TEST_BOOTSTRAP_SECRET;
  const result = response();
  await handler({ method: "POST", headers: {} }, result);
  if (previous.environment === undefined) delete process.env.VERCEL_ENV; else process.env.VERCEL_ENV = previous.environment;
  if (previous.branch === undefined) delete process.env.VERCEL_GIT_COMMIT_REF; else process.env.VERCEL_GIT_COMMIT_REF = previous.branch;
  if (previous.secret === undefined) delete process.env.E2E_TEST_BOOTSTRAP_SECRET; else process.env.E2E_TEST_BOOTSTRAP_SECRET = previous.secret;
  return result;
}

test("production always returns a generic 404", async () => {
  const result = await invoke("production", "main");
  assert.equal(result.code, 404);
  assert.deepEqual(result.body, { error: "Not found" });
  assert.match(result.headers["Cache-Control"], /no-store/);
});

test("other preview branches always return a generic 404", async () => {
  const result = await invoke("preview", "another-branch");
  assert.equal(result.code, 404);
});

test("TEST71 without an authorized runner identity fails closed", async () => {
  const result = await invoke("preview", "test71-real-chat-e2e-finalization");
  assert.equal(result.code, 404);
});
