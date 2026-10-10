(function(root,factory){
  const create=factory();
  if(typeof module==='object'&&module.exports)module.exports=create;
  else {
    let storage;try{storage=root.sessionStorage}catch{}
    root.RRFinancialRequests=create({storage,randomUUID:()=>root.crypto.randomUUID()});
  }
})(typeof window==='object'?window:globalThis,function(){
  'use strict';
  const operations=new Set([
    'rr_accounts_post_payment_v805','rr_accounts_post_receipt_v805',
    'rr_material_post_purchase_v805_1','rr_material_post_purchase_txn_v661',
    'rr_worker_salary_payment_post_v781','rr_committee_payment_post_v824',
    'rr_salary_payment_post_v785','rr_salary_payment_post_v786','rr_advance_payment_post_v785'
  ]);
  const canonical=value=>{
    if(Array.isArray(value))return value.map(canonical);
    if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])]));
    return value;
  };
  return function({storage,randomUUID}){
    const pending=new Map(),inflight=new Map();
    async function rpc(client,operation,payload={}){
      if(!operations.has(operation))return client.rpc(operation,payload);
      const mode=String(payload.p_data_mode||'TEST').toUpperCase();
      const key='rr.financial.request.test71:'+operation+':'+mode;
      const fingerprint=JSON.stringify(canonical(payload));
      let requests=pending.get(key);
      if(!requests){
        try{requests=JSON.parse(storage.getItem(key)||'[]')}catch{throw Error('Payment request storage is unavailable. Enable storage before posting.')}
        if(!Array.isArray(requests))requests=[];
      }
      let request=requests.find(item=>item.fingerprint===fingerprint);
      if(!request){request={fingerprint,id:randomUUID()};requests.push(request)}
      try{storage.setItem(key,JSON.stringify(requests))}catch{throw Error('Payment request could not be saved on this device. Posting was stopped.')}
      pending.set(key,requests);
      const flightKey=key+':'+request.id;
      if(inflight.has(flightKey))return inflight.get(flightKey);
      const promise=client.rpc('rr_financial_request_post_test71',{
        p_operation:operation,p_data_mode:mode,p_request_id:request.id,p_payload:payload
      });
      inflight.set(flightKey,promise);
      try{return await promise}finally{inflight.delete(flightKey)}
    }
    return {rpc};
  };
});
