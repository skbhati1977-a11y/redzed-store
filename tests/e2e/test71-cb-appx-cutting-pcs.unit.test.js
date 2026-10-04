const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const cb=fs.readFileSync(path.join(root,'real-cb-new-v9130-fix2.html'),'utf8');
const migration=fs.readFileSync(
  path.join(root,'supabase/migrations/20261004054500_test71_cb_appx_cutting_snapshot_v1.sql'),
  'utf8'
);

test('CB Appx Sheet shows Appx PCS followed by Cutting PCS',()=>{
  const appx=cb.indexOf('<th>Appx PCS</th>');
  const cutting=cb.indexOf('<th>Cutting PCS</th>');
  assert.ok(appx>0);
  assert.ok(cutting>appx);
  assert.ok(cb.includes('g.appx_pcs'));
  assert.ok(cb.includes('g.cutting_pcs'));
});

test('CB UI explicitly preserves Appx when Cutting arrives',()=>{
  assert.ok(cb.includes('Cutting आने पर Appx overwrite नहीं होगा.'));
  assert.ok(cb.includes("Number(g.cutting_pcs||0)>0"));
});

test('derived requirement schema stores Appx and Cutting independently',()=>{
  assert.ok(migration.includes('add column if not exists appx_pcs numeric'));
  assert.ok(migration.includes('add column if not exists cutting_pcs numeric'));
  assert.ok(migration.includes('appx_pcs=v_appx_store'));
  assert.ok(migration.includes('cutting_pcs=nullif(v_cutting_pcs,0)'));
});

test('actual requirement basis uses actual Cutting PCS, never planned PCS',()=>{
  const start=migration.indexOf('create or replace function public.rr_cb_refresh_derived_requirements_core_v1');
  const end=migration.indexOf('create or replace function public.rr_cb_requirement_context_v1');
  const core=migration.slice(start,end);
  assert.ok(core.includes('basis_pcs:=coalesce(public.rr_cb_actual_cutting_pcs_v1(u.id),0)'));
  assert.ok(!core.includes('planned_pcs'));
});

test('root Set physical weight follows its assigned Regular Cloth roll',()=>{
  assert.ok(migration.includes('coalesce(du.parent_unit_id,du.id) root_id'));
  assert.ok(migration.includes('group by coalesce(du.parent_unit_id,du.id)'));
  assert.ok(migration.includes("lower(mc.category_code)='regular-cloth'"));
});
