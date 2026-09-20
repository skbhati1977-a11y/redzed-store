const names = [
  "E2E_TEST_SUPER_ADMIN_EMAIL",
  "E2E_TEST_SUPER_ADMIN_PASSWORD",
  "E2E_TEST_BOOTSTRAP_SECRET"
];

for (const name of names) console.log(`${name}: ${process.env[name] ? "CONFIGURED" : "MISSING"}`);
if (names.some((name) => !process.env[name])) process.exitCode = 1;
