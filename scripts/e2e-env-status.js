const { roles } = require("../tests/e2e/roles");

const rows = roles.map(({ slug, envPrefix }) => ({
  role: slug,
  email: process.env[`${envPrefix}_EMAIL`] ? "CONFIGURED" : "MISSING",
  password: process.env[`${envPrefix}_PASSWORD`] ? "CONFIGURED" : "MISSING"
}));

console.table(rows);
if (rows.some((row) => row.email === "MISSING" || row.password === "MISSING")) {
  process.exitCode = 1;
}
