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

async function authorizedInvoke(fetchStub) {
  const values = {
    VERCEL_ENV: 'preview', VERCEL_GIT_COMMIT_REF: 'test71-real-chat-e2e-finalization',
    E2E_TEST_BOOTSTRAP_SECRET: 'fixture-bootstrap-secret-at-least-32-characters',
    E2E_TEST_SUPER_ADMIN_EMAIL: 'fixture@example.invalid', E2E_TEST_SUPER_ADMIN_PASSWORD: 'fixture-only'
  };
  const previous = Object.fromEntries(Object.keys(values).map(key => [key, process.env[key]]));
  const oldFetch = global.fetch;
  const oldTimeout = AbortSignal.timeout;
  const deadlines = [];
  Object.assign(process.env, values);
  global.fetch = fetchStub;
  AbortSignal.timeout = ms => { deadlines.push(ms); return oldTimeout(1); };
  try {
    const result = response();
    await handler({ method: 'POST', headers: { 'x-e2e-bootstrap-secret': values.E2E_TEST_BOOTSTRAP_SECRET } }, result);
    return { result, deadlines };
  } finally {
    global.fetch = oldFetch;
    AbortSignal.timeout = oldTimeout;
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
}

function waitForAbort(options) {
  assert.ok(options.signal, 'upstream request must have an abort deadline');
  return new Promise((_, reject) => {
    // Keep the event loop alive while Node's unref'ed AbortSignal timer fires.
    const fallback = setTimeout(() => reject(new Error('abort deadline did not fire')), 100);
    options.signal.addEventListener('abort', () => {
      clearTimeout(fallback);
      reject(options.signal.reason);
    }, { once: true });
  });
}

const fixtureSession = { access_token: 'fixture-access', refresh_token: 'fixture-refresh', user: { id: 'fixture-user' } };

test('stalled upstream password login returns generic 503 within its abort deadline', async () => {
  const { result, deadlines } = await authorizedInvoke((_, options) => waitForAbort(options));
  assert.equal(result.code, 503);
  assert.deepEqual(result.body, { error: 'Not found' });
  assert.deepEqual(deadlines, [15000]);
});

test('stalled profile verification with stalled logout never returns session tokens', async () => {
  const calls = [];
  const { result, deadlines } = await authorizedInvoke(async (url, options) => {
    calls.push(url);
    if (calls.length === 1) return { ok: true, json: async () => fixtureSession };
    return waitForAbort(options);
  });
  assert.equal(result.code, 503);
  assert.deepEqual(result.body, { error: 'Not found' });
  assert.match(calls[2], /auth\/v1\/logout$/);
  assert.deepEqual(deadlines, [15000, 15000, 5000]);
});

test('authorized active Super Admin still receives a verified session', async () => {
  let calls = 0;
  const { result, deadlines } = await authorizedInvoke(async () => {
    calls += 1;
    return { ok: true, json: async () => calls === 1 ? fixtureSession : [{ role_code: 'SUPER_ADMIN', is_active: true, access_status: 'ACTIVE' }] };
  });
  assert.equal(result.code, 200);
  assert.equal(result.body.access_token, fixtureSession.access_token);
  assert.equal(result.body.refresh_token, fixtureSession.refresh_token);
  assert.deepEqual(deadlines, [15000, 15000]);
});

test('inactive profile remains denied even when logout times out', async () => {
  let calls = 0;
  const { result } = await authorizedInvoke(async (_, options) => {
    calls += 1;
    if (calls === 3) return waitForAbort(options);
    return { ok: true, json: async () => calls === 1 ? fixtureSession : [{ role_code: 'SUPER_ADMIN', is_active: false }] };
  });
  assert.equal(result.code, 403);
  assert.deepEqual(result.body, { error: 'Not found' });
});
