const crypto = require("node:crypto");

const TEST_BRANCH = "test71-real-chat-e2e-finalization";
const SUPABASE_URL = "https://hruartsemierwhtzonei.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_uo3dcrFuRvGsvRzPcdTV0A_5ZVwgzga";

function deny(response, status = 404) {
  response.setHeader("Cache-Control", "private, no-store, max-age=0");
  return response.status(status).json({ error: "Not found" });
}

function safeEqual(left, right) {
  const a = Buffer.from(String(left || ""));
  const b = Buffer.from(String(right || ""));
  return a.length > 31 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

module.exports = async function handler(request, response) {
  response.setHeader("Cache-Control", "private, no-store, max-age=0");
  response.setHeader("Pragma", "no-cache");
  if (process.env.VERCEL_ENV !== "preview" || process.env.VERCEL_GIT_COMMIT_REF !== TEST_BRANCH) return deny(response);
  if (request.method !== "POST") return deny(response);
  const bootstrapSecret = process.env.E2E_TEST_BOOTSTRAP_SECRET;
  if (!bootstrapSecret || !safeEqual(request.headers["x-e2e-bootstrap-secret"], bootstrapSecret)) return deny(response);
  const email = process.env.E2E_TEST_SUPER_ADMIN_EMAIL;
  const password = process.env.E2E_TEST_SUPER_ADMIN_PASSWORD;
  if (!email || !password) return deny(response, 503);

  const authResponse = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password })
  });
  if (!authResponse.ok) return deny(response, 503);
  const session = await authResponse.json();
  const userId = session?.user?.id;
  if (!session?.access_token || !session?.refresh_token || !userId) return deny(response, 503);
  const profileResponse = await fetch(
    `${SUPABASE_URL}/rest/v1/rr_user_profiles?auth_user_id=eq.${encodeURIComponent(userId)}&select=role_code,is_active,access_status&limit=1`,
    { headers: { apikey: SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${session.access_token}`, Accept: "application/json" } }
  );
  const profiles = profileResponse.ok ? await profileResponse.json() : [];
  const profile = profiles[0] || {};
  const role = String(profile.role_code || "").toUpperCase();
  if (!profileResponse.ok || !profile.is_active || String(profile.access_status || "ACTIVE").toUpperCase() !== "ACTIVE" || !["OWNER", "SUPER_ADMIN"].includes(role)) {
    await fetch(`${SUPABASE_URL}/auth/v1/logout`, { method: "POST", headers: { apikey: SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${session.access_token}` } }).catch(() => null);
    return deny(response, 403);
  }
  return response.status(200).json({ access_token: session.access_token, refresh_token: session.refresh_token, expires_at: session.expires_at, token_type: "bearer" });
};
