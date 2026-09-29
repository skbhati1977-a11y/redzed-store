const assert = require('node:assert/strict');
const fs = require('node:fs');
const { test } = require('node:test');
const { installFunctions } = require('./helpers/source-functions');
const loginSource = fs.readFileSync('real-login.js', 'utf8');
for (const origin of ['https://test71-8000.app.github.dev', 'https://test71-preview.vercel.app']) {
  test('password recovery stays on its current authorized origin: ' + origin, async () => {
    const calls = [];
    const scope = { location: {origin}, msg: {}, document: {getElementById: () => ({value:' unit@example.invalid '})},
      supabaseClient: {auth: {resetPasswordForEmail: async (...args) => {calls.push(args); return {error:null};}}} };
    installFunctions(loginSource, scope, ['sendRecovery']);
    await scope.sendRecovery();
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0], 'unit@example.invalid');
    assert.equal(calls[0][1].redirectTo, origin + '/reset-password.html');
  });
}
test('password recovery does not pin Vercel or GitHub Pages callbacks', () => {
  assert.doesNotMatch(loginSource, /redirectTo:\s*["']https:\/\//);
});
