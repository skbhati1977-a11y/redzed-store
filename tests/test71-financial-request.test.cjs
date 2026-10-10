const test=require('node:test');
const assert=require('node:assert/strict');
const create=require('../real-financial-request.js');
const operation='rr_accounts_post_payment_v805';
const payload={p_data_mode:'TEST',p_amount:1,p_ref_no:'PAY-1'};
function fixture(storage){
  let count=0;
  storage=storage||{items:new Map(),getItem(k){return this.items.get(k)},setItem(k,v){this.items.set(k,v)}};
  return {storage,api:create({storage,randomUUID:()=>`request-${++count}`})};
}
test('two clicks share one in-flight call and retry keeps its request ID',async()=>{
  const {api}=fixture();const calls=[];let resolve;
  const client={rpc(n,p){calls.push([n,p]);return new Promise(r=>{resolve=r})}};
  const a=api.rpc(client,operation,payload),b=api.rpc(client,operation,payload);
  assert.equal(calls.length,1);
  resolve({data:{transaction_id:'T1'},error:null});
  assert.deepEqual(await a,await b);
  client.rpc=async(n,p)=>{calls.push([n,p]);return {data:{transaction_id:'T1'},error:null}};
  await api.rpc(client,operation,payload);
  assert.equal(calls[0][1].p_request_id,calls[1][1].p_request_id);
});
test('uncertain network failure does not allocate a new payment on retry',async()=>{
  const {api}=fixture();const ids=[];let failed=true;
  const client={async rpc(n,p){ids.push(p.p_request_id);if(failed){failed=false;throw Error('connection lost after posting')}return {data:{ok:true},error:null}}};
  await assert.rejects(api.rpc(client,operation,payload));
  await api.rpc(client,operation,payload);assert.equal(ids[0],ids[1]);
});
test('page reload restores request ID without reading credentials',async()=>{
  const {api,storage}=fixture();const ids=[];
  const client={async rpc(n,p){ids.push(p.p_request_id);return {data:{ok:true},error:null}}};
  await api.rpc(client,operation,payload);
  await fixture(storage).api.rpc(client,operation,payload);
  assert.equal(ids[0],ids[1]);
});
test('changed financial payload allocates a new request',async()=>{
  const {api}=fixture();const ids=[];
  const client={async rpc(n,p){ids.push(p.p_request_id);return {data:{ok:true},error:null}}};
  await api.rpc(client,operation,payload);await api.rpc(client,operation,{...payload,p_amount:2});
  assert.notEqual(ids[0],ids[1]);
});
test('object key order preserves operation identity',async()=>{
  const {api}=fixture();const ids=[];
  const client={async rpc(n,p){ids.push(p.p_request_id);return {data:{ok:true},error:null}}};
  await api.rpc(client,operation,payload);await api.rpc(client,operation,{p_ref_no:'PAY-1',p_amount:1,p_data_mode:'TEST'});
  assert.equal(ids[0],ids[1]);
});
test('denied storage blocks a financial write before sending it',async()=>{
  const {api}=fixture({getItem(){throw Error('denied')},setItem(){throw Error('denied')}});const ids=[];
  const client={async rpc(n,p){ids.push(p.p_request_id);return {data:{ok:true},error:null}}};
  await assert.rejects(api.rpc(client,operation,payload),/storage is unavailable/);
  assert.equal(ids.length,0);
});
test('returning to an earlier payload does not discard its request identity',async()=>{
  const {api}=fixture();const ids=[];
  const client={async rpc(n,p){ids.push(p.p_request_id);return {data:{ok:true},error:null}}};
  await api.rpc(client,operation,payload);await api.rpc(client,operation,{...payload,p_amount:2});
  await api.rpc(client,operation,payload);assert.equal(ids[0],ids[2]);assert.notEqual(ids[0],ids[1]);
});
test('read-only RPCs retain their normal route',async()=>{
  const {api}=fixture();const calls=[];
  const client={async rpc(n,p){calls.push([n,p]);return {data:[],error:null}}};
  await api.rpc(client,'rr_trial_balance_v806',{p_data_mode:'TEST'});
  assert.deepEqual(calls,[['rr_trial_balance_v806',{p_data_mode:'TEST'}]]);
});
