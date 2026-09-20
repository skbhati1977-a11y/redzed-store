const roles = [
  ["super-admin", "E2E_SUPER_ADMIN", ["owner", "super_admin"]],
  ["admin", "E2E_ADMIN", ["admin"]],
  ["manager", "E2E_MANAGER", ["manager"]],
  ["lineman", "E2E_LINEMAN", ["line_manager", "lineman"]],
  ["printing-worker", "E2E_PRINTING_WORKER", ["printing_operator", "worker"]],
  ["sticker-worker", "E2E_STICKER_WORKER", ["sticker_operator", "worker"]],
  ["stitching-worker", "E2E_STITCHING_WORKER", ["worker"]],
  ["overlock-worker", "E2E_OVERLOCK_WORKER", ["worker"]],
  ["folding-worker", "E2E_FOLDING_WORKER", ["worker"]],
  ["kaaj-btn-worker", "E2E_KAAJ_BTN_WORKER", ["worker"]],
  ["metal-id-worker", "E2E_METAL_ID_WORKER", ["worker"]],
  ["teak-tanki-worker", "E2E_TEAK_TANKI_WORKER", ["worker"]],
  ["thread-cut-worker", "E2E_THREAD_CUT_WORKER", ["worker"]],
  ["qc-worker", "E2E_QC_WORKER", ["worker"]],
  ["press-worker", "E2E_PRESS_WORKER", ["worker"]],
  ["packing-worker", "E2E_PACKING_WORKER", ["packing_operator", "worker"]],
  ["salesman", "E2E_SALESMAN", ["sales", "salesman"]],
  ["accounts-store", "E2E_ACCOUNTS_STORE", ["accounts", "store_receiver"]]
].map(([slug, envPrefix, allowedRoles]) => ({ slug, envPrefix, allowedRoles }));

function credentials(role) {
  const email = process.env[`${role.envPrefix}_EMAIL`];
  const password = process.env[`${role.envPrefix}_PASSWORD`];
  if (!email || !password) {
    throw new Error(`Missing ${role.envPrefix}_EMAIL/PASSWORD`);
  }
  return { email, password };
}

module.exports = { roles, credentials };

