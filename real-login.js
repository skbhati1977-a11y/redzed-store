const form = document.getElementById("loginForm");
const msg = document.getElementById("loginMessage");

form.addEventListener("submit", async (e) => {
  e.preventDefault();

  msg.textContent = "Signing in...";

  const identifier = document.getElementById("identifier").value.trim();
  const password = document.getElementById("password").value;
  const isEmail = identifier.includes("@");
  let data, error;
  if (isEmail) ({ data, error } = await supabaseClient.auth.signInWithPassword({ email: identifier, password }));
  else {
    try {
      const response = await fetch(`${SUPABASE_URL}/functions/v1/rr-staff-login-v9750`, {
        method: "POST", headers: { "Content-Type": "application/json", apikey: SUPABASE_ANON_KEY },
        body: JSON.stringify({ action: "login", identifier, password })
      });
      const result = await response.json();
      if (!response.ok || !result.session) throw new Error(result.error || "Invalid login credentials.");
      ({ data, error } = await supabaseClient.auth.setSession({ access_token: result.session.access_token, refresh_token: result.session.refresh_token }));
    } catch (requestError) { error = requestError; }
  }

  if (error) {
    msg.innerHTML = `
      ${error.message}<br><br>
      <button
        type="button"
        onclick="sendRecovery()"
        class="rr-btn rr-btn-secondary"
      >
        Reset Password
      </button>
    `;
    return;
  }

  if (!data?.session?.access_token) {
    msg.textContent = "Login session could not be saved. Please try again.";
    return;
  }
  const verified = await supabaseClient.auth.getUser(data.session.access_token);
  if (verified.error || !verified.data?.user) {
    msg.textContent = verified.error?.message || "Login verification failed.";
    return;
  }
  await new Promise((resolve) => setTimeout(resolve, 250));

  const requested = new URLSearchParams(location.search).get("next") || "";
  const safeNext = /^(?:real-[a-z0-9._-]+\.html)(?:\?[a-z0-9_=&.%+-]*)?$/i.test(requested)
    ? requested
    : "real-dashboard.html";
  location.href = safeNext;
});

async function sendRecovery() {
  const identifier = document.getElementById("identifier").value.trim();

  if (!identifier) { msg.textContent = "Enter your email, mobile or username first."; return; }

  msg.textContent = "Sending password reset email...";

  let error = null;
  if (identifier.includes("@")) ({ error } = await supabaseClient.auth.resetPasswordForEmail(identifier, { redirectTo: "https://skbhati1977-a11y.github.io/redzed-store/reset-password.html" }));
  else {
    try {
      const response = await fetch(`${SUPABASE_URL}/functions/v1/rr-staff-login-v9750`, { method:"POST", headers:{"Content-Type":"application/json",apikey:SUPABASE_ANON_KEY}, body:JSON.stringify({action:"reset",identifier}) });
      if (!response.ok) throw new Error("Reset request could not be processed.");
    } catch (requestError) { error = requestError; }
  }

  if (error) {
    msg.textContent = error.message;
    return;
  }

  msg.textContent =
    "If the account has a registered email, a reset link has been sent. Gmail, Spam और Promotions check करें।";
}

document.getElementById("forgotBtn").addEventListener("click", sendRecovery);
document.getElementById("togglePassword").addEventListener("click", (event) => {
  const password = document.getElementById("password"), showing = password.type === "text";
  password.type = showing ? "password" : "text";
  event.currentTarget.setAttribute("aria-pressed", String(!showing));
  event.currentTarget.setAttribute("aria-label", showing ? "Show password" : "Hide password");
});
