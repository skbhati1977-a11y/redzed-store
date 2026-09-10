const fs = require('node:fs');
const assert = require('node:assert/strict');

const sql = fs.readFileSync('supabase/migrations/20260910193000_test69_creditor_accounts_frontend_v9763.sql', 'utf8');
const html = fs.readFileSync('real-accounts-v805.html', 'utf8');
const js = fs.readFileSync('real-accounts-v805.js', 'utf8');

for (const token of [
  'rr_supplier_accounts_map_v9763', 'rr_accounts_creditor_search_v9763',
  'rr_accounts_post_journal_v9763', 'rr_accounts_reverse_voucher_v9763',
  "transaction_type not in(' Tarr')"
].slice(0, 4)) assert.ok(sql.includes(token), `missing ${token}`);
assert.ok(sql.includes("transaction_type not in('RECEIPT','PAYMENT','JOURNAL')"));
assert.ok(sql.includes('revoke all on table public.rr_supplier_accounts_map_v9763'));
for (const id of ['creditors', 'creditorSearch', 'postJournal', 'reverseVoucherBtn']) assert.ok(html.includes(`id="${id}"`), `missing #${id}`);
for (const fn of ['loadCreditors', 'postJournal', 'reverseVoucher']) assert.ok(js.includes(`function ${fn}`), `missing ${fn}`);
for (const id of ['openAccountsMenu', 'accountsDrawer', 'entryPopup', 'sharePopupEntry', 'exportPopupEntry']) assert.ok(html.includes(`id="${id}"`), `missing #${id}`);
for (const token of ['data-share-entry', 'data-export-entry', 'data-share-set', 'pointerdown', 'navigator.share']) assert.ok(js.includes(token), `missing ${token}`);

console.log('V9763 creditor mapping/UI contract: PASS');
