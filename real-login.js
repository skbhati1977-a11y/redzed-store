const form = document.getElementById("loginForm");
const msg = document.getElementById("loginMessage");

form.addEventListener("submit", async (e) => {
  e.preventDefault();

  msg.textContent = "Signing in...";

  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;

  const { error } = await supabaseClient.auth.signInWithPassword({
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

  location.href = "real-dashboard.html";
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
