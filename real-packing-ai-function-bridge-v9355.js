(()=>{
  'use strict';
  if(window.__RR_PACKING_AI_FUNCTION_BRIDGE_V9355__)return;
  window.__RR_PACKING_AI_FUNCTION_BRIDGE_V9355__=true;
  const FN='rr-ai-garment-images-v9330';
  const getClient=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const connectMsg='AI service connect nahi ho pa raha. Internet/Supabase Function status check karke retry karein.';
  function patch(){
    const c=getClient();
    if(!c?.functions?.invoke||c.__rrAiFunctionBridge9355)return false;
    const original=c.functions.invoke.bind(c.functions);
    c.functions.invoke=async function(name,options){
      if(name!==FN)return original(name,options);
      try{return await invokeDirect(c,options&&options.body)}
      catch(error){
        console.warn('Packing AI direct bridge failed',error);
        try{return await original(name,options)}catch(e){return {data:null,error:e||error}}
      }
    };
    c.__rrAiFunctionBridge9355=true;
    return true;
  }
  async function invokeDirect(c,body){
    const auth=await c.auth.getSession();
    const token=auth?.data?.session?.access_token;
    if(!token)throw Error('Login session required');
    const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
    const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
    if(!base||!key)throw Error('Supabase config missing');
    const ctl=new AbortController(),timer=setTimeout(()=>ctl.abort(),120000);
    try{
      const res=await fetch(base.replace(/\/$/,'')+'/functions/v1/'+FN,{method:'POST',headers:{'Content-Type':'application/json','apikey':key,'Authorization':'Bearer '+token},body:JSON.stringify(body||{}),signal:ctl.signal,cache:'no-store'});
      const raw=await res.text();let data=null;
      try{data=raw?JSON.parse(raw):null}catch(_){data={ok:false,error:raw}}
      if(!res.ok)return {data,error:new Error(data?.error||data?.message||connectMsg)};
      return {data,error:null};
    }catch(e){
      if(String(e?.name||'')==='AbortError')return {data:null,error:new Error('AI service timeout. Retry karein.')};
      return {data:null,error:new Error(e?.message||connectMsg)};
    }finally{clearTimeout(timer)}
  }
  [0,200,800,1600,3000].forEach(ms=>setTimeout(patch,ms));
  document.addEventListener('click',()=>setTimeout(patch,50),true);
})();

(()=>{
  'use strict';
  if(window.__RR_PACKING_ALGO_RECOVER_V9355__)return;
  window.__RR_PACKING_ALGO_RECOVER_V9355__=true;
  if(!/real-finished-goods-v787\.html$/i.test(location.pathname))return;
  const qs=new URLSearchParams(location.search);
  if((qs.get('view')||'').toLowerCase()!=='packing')return;
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const n=v=>Number(v||0), SIZE_ORDER=['L','XL','XXL'];
  let busy=false,lastRecoveredPlan='';
  function sb(){return window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;}
  function setMsg(text,type='ok'){const m=$('message');if(m){m.textContent=text||'';m.className='fg-msg '+type;}}
  function selectedLot(){const text=String($('selectedPackLot')?.textContent||'').trim(),m=text.match(/Lot\s+(.+)/i);return (m?m[1]:text).trim().toUpperCase();}
  function normalizeMessage(){const m=$('message');if(!m)return;const t=String(m.textContent||'');if(/Re-run allowed before submit|Existing algorithm table loaded/i.test(t))setMsg('Algorithm table retained. Next stage complete karein; re-run sirf confirmation ke baad hoga.','ok');}
  function packMatrix(cells){
    const rows={};(cells||[]).forEach(x=>{const c=String(x.colour_code||'').trim(),s=String(x.size_code||'').trim(),q=n(x.qty);if(!c||!s||!q)return;rows[c] ||= {};rows[c][s]=(rows[c][s]||0)+q;});
    const colours=Object.keys(rows).sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
    const found=(cells||[]).map(x=>String(x.size_code||'').trim()).filter(Boolean);
    const sizes=[...new Set([...SIZE_ORDER,...found])].sort((a,b)=>(SIZE_ORDER.indexOf(a)<0?99:SIZE_ORDER.indexOf(a))-(SIZE_ORDER.indexOf(b)<0?99:SIZE_ORDER.indexOf(b))||a.localeCompare(b,undefined,{numeric:true}));
    return {rows,colours,sizes};
  }
  function compositionTable(cells){const m=packMatrix(cells);if(!m.colours.length||!m.sizes.length)return '';return '<div class="fg-pack-matrix-wrap"><table class="fg-pack-matrix"><thead><tr><th>Colour</th>'+m.sizes.map(s=>'<th>'+esc(s)+'</th>').join('')+'</tr></thead><tbody>'+m.colours.map(c=>'<tr><th>'+esc(c)+'</th>'+m.sizes.map(s=>'<td>'+n(m.rows[c][s])+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>';}
  function boxNo(code){const m=String(code||'').match(/-BOX-(\d+)$/);return m?Number(m[1]):null;}
  function cellsKey(cells){return (cells||[]).map(x=>`${x.colour_code}|${x.size_code}|${n(x.qty)}|${String(x.pack_mark||'')}`).sort((a,b)=>a.localeCompare(b,undefined,{numeric:true})).join('~');}
  function boxType(box){const type=String(box.box_type||'').toUpperCase(),cells=box.cells||[];if(cells.some(x=>String(x.pack_mark||'').toUpperCase()==='MIX')||n(box.qty)>18)return 'MIX';if(cells.some(x=>String(x.pack_mark||'').toUpperCase()==='ASST'))return 'ASST';return type==='REGULAR'?'FRESH':(type||'ASST');}
  function groups(boxes){const out=[],map=new Map();(boxes||[]).forEach(box=>{const type=boxType(box),key=`${type}|${n(box.qty)}|${cellsKey(box.cells)}`;let g=map.get(key);if(!g){g={type,boxes:[],nos:[],total:0,sample:box};map.set(key,g);out.push(g);}g.boxes.push(box);g.total+=n(box.qty);const no=boxNo(box.box_code);if(no)g.nos.push(no);});return out;}
  function ranges(nums){const a=[...new Set(nums)].sort((x,y)=>x-y),r=[];for(let i=0;i<a.length;i++){let s=a[i],e=s;while(i+1<a.length&&a[i+1]===e+1)e=a[++i];r.push(s===e?String(s):`${s}-${e}`);}return r.join(', ');}
  function render(detail,status,planId){
    const boxes=detail?.boxes||[],packRows=$('packRows'),summary=$('packSummary'),submit=$('submitPack'),block=$('packAlgoBlock');if(!packRows||!summary||!submit)return false;
    packRows.innerHTML=groups(boxes).map(g=>'<tr><td data-label="Box">'+esc(g.nos.length?'BOX '+ranges(g.nos):String(g.sample.box_code||''))+'</td><td data-label="Type">'+esc(g.type)+'</td><td data-label="PCS">'+esc(g.boxes.length>1?`${n(g.sample.qty)} x ${g.boxes.length} = ${g.total}`:String(n(g.sample.qty)))+'</td><td data-label="Composition">'+compositionTable(g.sample.cells)+'</td></tr>').join('');
    summary.innerHTML='<span class="fg-chip">Boxes <b>'+boxes.length+'</b></span><span class="fg-chip">PCS <b>'+esc(detail?.total_qty||boxes.reduce((s,b)=>s+n(b.qty),0))+'</b></span><span class="fg-chip">Retained <b>'+esc(status||'READY')+'</b></span>';
    if(block)block.hidden=false;
    submit.disabled=String(status||'').toUpperCase()==='SUBMITTED';
    window.__RR_LAST_PACK_PLAN_ID__=planId||window.__RR_LAST_PACK_PLAN_ID__||'';
    lastRecoveredPlan=planId||lastRecoveredPlan;
    return true;
  }
  async function loadAssignment(lot){
    const c=sb();if(!c||!lot)return null;
    let r=await c.from('rr_fg_packing_assignments_v788').select('id,lot_no,status,pack_plan_id,updated_at').eq('data_mode','TEST').ilike('lot_no',lot).not('pack_plan_id','is',null).order('updated_at',{ascending:false}).limit(1);
    if(r.error)throw r.error;
    return (r.data||[])[0]||null;
  }
  async function recover(reason=''){
    if(busy)return;const lot=selectedLot();if(!lot)return;busy=true;
    try{
      const a=await loadAssignment(lot);if(!a?.pack_plan_id)return;
      const hasRows=!!String($('packRows')?.innerHTML||'').trim();
      if(hasRows&&lastRecoveredPlan===a.pack_plan_id&&!/Equal packing algorithm chal raha/i.test(String($('message')?.textContent||'')))return;
      const d=await sb().rpc('rr_fg_pack_plan_detail_v787',{p_plan_id:a.pack_plan_id});if(d.error)throw d.error;
      if(render(d.data,a.status,a.pack_plan_id)){const stuck=/Equal packing algorithm chal raha|Re-run allowed before submit|Existing algorithm table loaded/i.test(String($('message')?.textContent||''));if(stuck||reason)setMsg('Algorithm table retained. Next stage complete karein; re-run sirf confirmation ke baad hoga.','ok');}
    }
    catch(e){setMsg(e.message||String(e),'error')}finally{busy=false;}
  }
  function needsRecover(){const text=String($('message')?.textContent||''),rows=String($('packRows')?.innerHTML||'').trim(),lot=selectedLot();return !!lot&&(/Equal packing algorithm chal raha/i.test(text)||!rows||/Re-run allowed before submit|Existing algorithm table loaded/i.test(text));}
  document.addEventListener('click',e=>{if(e.target?.closest?.('[data-pack-lot]'))setTimeout(()=>recover('open-lot'),450);if(e.target?.closest?.('#runPackAlgo'))setTimeout(()=>{if(needsRecover())recover('run-timeout');},8000);},true);
  const start=()=>{if(!document.body)return;new MutationObserver(()=>{normalizeMessage();if(needsRecover())setTimeout(()=>recover('observer'),450);}).observe(document.body,{childList:true,subtree:true,characterData:true});setInterval(()=>{normalizeMessage();if(needsRecover())recover('interval');},1800);};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})();