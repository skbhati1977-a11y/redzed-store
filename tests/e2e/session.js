const path = require("path");

const authFile = path.join("playwright", ".auth", "super-admin.json");
const OIDC_AUDIENCE = "redzed-test71-e2e";

async function runnerHeaders() {
  const secret = process.env.E2E_TEST_BOOTSTRAP_SECRET;
  if (secret) return { "x-e2e-bootstrap-secret": secret };
  if (process.env.E2E_RUNNER_OIDC_TOKEN) return { Authorization: `Bearer ${process.env.E2E_RUNNER_OIDC_TOKEN}` };
  const requestUrl = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  const requestToken = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
  if (!requestUrl || !requestToken) throw new Error("Missing short-lived E2E runner identity");
  const separator = requestUrl.includes("?") ? "&" : "?";
  const result = await fetch(`${requestUrl}${separator}audience=${encodeURIComponent(OIDC_AUDIENCE)}`, {
    headers: { Authorization: `bearer ${requestToken}` }
  });
  if (!result.ok) throw new Error(`GitHub OIDC request failed (${result.status})`);
  const body = await result.json();
  if (!body?.value) throw new Error("GitHub OIDC token missing");
  return { Authorization: `Bearer ${body.value}` };
}

async function bootstrap(page) {
  const headers = await runnerHeaders();
  let response;
  for (let attempt = 0; attempt < 24; attempt += 1) {
    response = await page.request.post("/api/e2e-session", { headers });
    if (response.ok()) break;
    if (![404, 503].includes(response.status()) || attempt === 23) break;
    await new Promise((resolve) => setTimeout(resolve, 10_000));
  }
  if (!response.ok()) throw new Error(`TEST71 bootstrap failed (${response.status()})`);
  const session = await response.json();
  await page.goto("/real-login.html");
  const result = await page.evaluate(async (tokens) => {
    const set = await window.supabaseClient.auth.setSession(tokens);
    if (set.error) throw new Error(set.error.message);
    return Boolean(set.data?.session?.user);
  }, { access_token: session.access_token, refresh_token: session.refresh_token });
  if (!result) throw new Error("Supabase session was not established");
  return session;
}

async function ensureSession(page) {
  await page.goto("/real-dashboard-v9182.html?mode=TEST");
  const active = await page.evaluate(async () => Boolean((await window.supabaseClient.auth.getSession()).data?.session));
  if (!active) {
    await bootstrap(page);
    await page.goto("/real-dashboard-v9182.html?mode=TEST");
  }
}

module.exports = { authFile, bootstrap, ensureSession, runnerHeaders };
