const form = document.getElementById("loginForm");
const msg = document.getElementById("loginMessage");
const emailInput = document.getElementById("email");
const passwordInput = document.getElementById("password");

form.addEventListener("submit", async (e) => {
  e.preventDefault();

  msg.textContent = "Signing in...";

  const email = emailInput.value.trim();
  const password = passwordInput.value;

  const { data, error } = await supabaseClient.auth.signInWithPassword({
    email,
    password
  });

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
  // Keep the credential fields intact briefly after successful authentication so
  // Android/Chrome password managers can observe a successful username/password form.
  form.dataset.loginSuccess = "true";
  msg.textContent = "Login successful…";
  await new Promise((resolve) => setTimeout(resolve, 900));

  const requested = new URLSearchParams(location.search).get("next") || "";
  const safeNext = /^(?:real-[a-z0-9._-]+\.html)(?:\?[a-z0-9_=&.%+-]*)?$/i.test(requested)
    ? requested
    : "real-dashboard.html";
  location.href = safeNext;
});

async function sendRecovery() {
  const email = document.getElementById("email").value.trim();

  msg.textContent = "Sending password reset email...";

  const { error } = await supabaseClient.auth.resetPasswordForEmail(
    email,
    {
      redirectTo:
        location.origin + "/reset-password.html"
    }
  );

  if (error) {
    msg.textContent = error.message;
    return;
  }

  msg.textContent =
    "Password reset email sent. Gmail, Spam और Promotions check करें।";
}
