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
    msg.textContent = error.message;
    return;
  }

  location.href = "real-dashboard.html";
});
