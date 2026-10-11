(()=>{
 'use strict';
 const $=id=>document.getElementById(id),uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 let source=null,revision=0,busy=false;
 const report=data=>{$('report').hidden=false;$('report').textContent=JSON.stringify(data,null,2);};
 function lock(value){busy=value;for(const id of ['datasetName','datasetId','sourceRef','sourceFile','createDataset'])$(id).disabled=value;$('stageSource').disabled=value||!source;}
 async function client(){const c=window.supabaseClient;if(!c)throw Error('Real Chat में login करके यह पेज खोलें।');const u=await c.auth.getUser();if(u.error||!u.data?.user)throw Error('Owner/Admin/Super Admin login चाहिए।');return {c,uid:u.data.user.id};}
 function requestId(key){let id=sessionStorage.getItem(key);if(!id){id=crypto.randomUUID();sessionStorage.setItem(key,id);}return id;}
 $('createDataset').onclick=async()=>{
  if(busy)return;const name=$('datasetName').value.trim();if(!name){$('state').textContent='समीक्षा का नाम भरें।';return;}lock(true);
  try{const {c,uid}=await client();const r=await c.rpc('rr_source_dataset_create_test71',{p_request_id:requestId('rr_dataset_create71:'+uid+':'+name),p_name:name});if(r.error)throw r.error;
   if(!uuid.test(r.data?.dataset_id||'')||r.data.data_mode!=='TEST'||r.data.operational_posting_enabled!==false)throw Error('अलग समीक्षा की पुष्टि नहीं मिली।');$('datasetId').value=r.data.dataset_id;report(r.data);$('state').textContent='अलग समीक्षा तैयार है। अब source file चुनें।';
  }catch(e){$('state').textContent=e.message||'समीक्षा नहीं बन पाई।';}finally{lock(false);}
 };
 $('sourceFile').onchange=async()=>{
  if(busy)return;const current=++revision;source=null;$('stageSource').disabled=true;$('report').hidden=true;const f=$('sourceFile').files[0];if(!f)return;
  try{if(f.size>10*1024*1024)throw Error('Source file अधिकतम 10 MB रखें।');const bytes=await f.arrayBuffer(),text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
   const rows=f.name.toLowerCase().endsWith('.csv')?window.RRSourceIntake71.csv(text):JSON.parse(text);const check=window.RRSourceIntake71.inspect(rows);
   const digest=await crypto.subtle.digest('SHA-256',bytes),sha=Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');if(current!==revision)return;
   source={rows:check.rows,sha};if(!$('sourceRef').value.trim())$('sourceRef').value=f.name;report(check);$('state').textContent=check.findings.length?'Source में findings हैं। अलग समीक्षा में save कर सकते हैं।':'Source पढ़ लिया। Save करने पर server जाँच होगी।';lock(false);
  }catch(e){if(current===revision)$('state').textContent=e.message||'Source पढ़ा नहीं गया।';}
 };
 $('stageSource').onclick=async()=>{
  if(busy||!source)return;const dataset=$('datasetId').value.trim(),ref=$('sourceRef').value.trim();if(!uuid.test(dataset)||!ref){$('state').textContent='सही समीक्षा ID और source reference भरें।';return;}const prepared=source;lock(true);
  try{const {c,uid}=await client();const r=await c.rpc('rr_dataset_import_stage_test71',{p_dataset_id:dataset,p_request_id:requestId('rr_dataset_stage71:'+uid+':'+dataset+':'+ref+':'+prepared.sha),p_source_ref:ref,p_source_sha256:prepared.sha,p_rows:prepared.rows});if(r.error)throw r.error;
   const data=r.data;if(data?.dataset_id!==dataset||!uuid.test(data?.batch_id||'')||data.cleared_for_import!==false||data.business_records_posted!==0)throw Error('Source isolation की पुष्टि नहीं मिली।');report(data);$('state').textContent='Source अलग समीक्षा में save हुआ। Business posting 0 है; approval और activation बाकी हैं।';
  }catch(e){$('state').textContent=e.message||'Save असफल। Retry में वही request रहेगा।';}finally{lock(false);}
 };
})();
