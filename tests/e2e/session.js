const path = require("path");

const authFile = path.join("playwright", ".auth", "super-admin.json");

async function bootstrap(page) {
  const secret = process.env.E2E_TEST_BOOTSTRAP_SECRET;
  if (!secret) throw new Error("Missing E2E_TEST_BOOTSTRAP_SECRET");
  const response = await page.request.post("/api/e2e-session", { headers: { "x-e2e-bootstrap-secret": secret } });
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

module.exports = { authFile, bootstrap, ensureSession };
