(()=>{
 'use strict';const $=id=>document.getElementById(id);let prepared=null,run=0,busy=false;
 function show(data){$('report').hidden=false;$('report').textContent=JSON.stringify(data,null,2);}
 $('sourceFile').onchange=async()=>{
  const revision=++run;prepared=null;$('stageSource').disabled=true;$('report').hidden=true;
  const file=$('sourceFile').files[0];if(!file)return;
  try{
   if(file.size>10*1024*1024)throw Error('Maximum source file size is 10 MB.');
   const bytes=await file.arrayBuffer(),text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
   const rows=file.name.toLowerCase().endsWith('.csv')?window.RRSourceIntake71.csv(text):JSON.parse(text);
   const result=window.RRSourceIntake71.inspect(rows);
   const digest=await crypto.subtle.digest('SHA-256',bytes),sha=Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
   if(revision!==run)return;prepared={rows:result.rows,sha};show(result);
   $('state').textContent=result.findings.length?'Mapping findings हैं। Review के लिए source save कर सकते हैं।':'Source format valid है। Server reconciliation अभी बाकी है।';
   if(!$('sourceRef').value.trim())$('sourceRef').value=file.name;$('stageSource').disabled=false;
  }catch(error){if(revision===run)$('state').textContent=error.message;}
 };
 $('stageSource').onclick=async()=>{
  if(busy||!prepared)return;const ref=$('sourceRef').value.trim();if(!ref){$('state').textContent='Original source reference required.';return;}
  const source=prepared;busy=true;$('stageSource').disabled=true;$('sourceFile').disabled=true;$('sourceRef').disabled=true;
  try{
   const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!client)throw Error('Login client unavailable. Open Real Chat and sign in.');
   const user=await client.auth.getUser();if(user.error||!user.data?.user)throw Error('Owner/Admin/Super Admin login required.');
   const key='rr_import_request71:'+user.data.user.id+':'+ref+':'+source.sha;
   let id=sessionStorage.getItem(key);if(!id){id=crypto.randomUUID();sessionStorage.setItem(key,id);}
   const response=await client.rpc('rr_import_stage_source_test71',{p_request_id:id,p_source_ref:ref,p_source_sha256:source.sha,p_rows:source.rows});
   if(response.error)throw response.error;if(!response.data?.batch_id||response.data.data_mode!=='TEST'||response.data.cleared_for_import!==false||response.data.business_records_posted!==0)throw Error('Source staging confirmation missing. No import clearance established.');show(response.data);
   $('state').textContent='Source review में save हुआ। Business posting: '+Number(response.data?.business_records_posted||0)+'. Import clearance अभी बाकी है।';
  }catch(error){$('state').textContent=error.message||'Source save failed. Retry preserves the same request.';}
  finally{busy=false;$('stageSource').disabled=false;$('sourceFile').disabled=false;$('sourceRef').disabled=false;}
 };
})();
