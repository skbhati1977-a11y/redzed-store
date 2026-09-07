const form = document.getElementById("loginForm");
const msg = document.getElementById("loginMessage");

form.addEventListener("submit", async (e) => {
  e.preventDefault();

  msg.textContent = "Signing in...";

  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;

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
  await new Promise((resolve) => setTimeout(resolve, 250));

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
        "https://skbhati1977-a11y.github.io/redzed-store/reset-password.html"
    }
  );

  if (error) {
    msg.textContent = error.message;
    return;
  }

  msg.textContent =
    "Password reset email sent. Gmail, Spam और Promotions check करें।";
}
