const oidcAvailable = Boolean(
  process.env.E2E_RUNNER_OIDC_TOKEN ||
  (process.env.ACTIONS_ID_TOKEN_REQUEST_URL && process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN)
);

console.log("PERMANENT_E2E_CREDENTIALS: VERCEL_PREVIEW_RUNTIME_ONLY");
console.log(`RUNNER_AUTHORIZATION: ${oidcAvailable ? "SHORT_LIVED_OIDC_CONFIGURED" : "SHORT_LIVED_OIDC_UNAVAILABLE"}`);
console.log(`LOCAL_PERMANENT_SECRETS_REQUIRED: NO`);
if (process.env.CI && !oidcAvailable) process.exitCode = 1;
