const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const loginSource = fs.readFileSync(
  path.join(__dirname, "..", "..", "real-login.js"),
  "utf8"
);

test("TEST71 password recovery requests the exact preview reset page", () => {
  assert.match(
    loginSource,
    /redirectTo:\s*\n?\s*["']https:\/\/redzed-test65-msk9oi43o-skbhati1977-4414\.vercel\.app\/reset-password\.html["']/
  );
});

test("password recovery no longer requests the GitHub Pages callback", () => {
  assert.doesNotMatch(
    loginSource,
    /redirectTo:\s*\n?\s*["']https:\/\/skbhati1977-a11y\.github\.io\/redzed-store\/reset-password\.html["']/
  );
});
