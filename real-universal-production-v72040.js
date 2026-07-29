(()=>{
'use strict';
const $=id=>document.getElementById(id);
const state={client:null,auth:null,depts:[],lots:[],alters:[]};
const safe=v=>window.RR?.safeText?RR.safeText(v):String(v??'').replace(/[&<>"']/g,'');
function msg(t,type='info'){$('message').innerHTML=t?`<div class="msg ${safe(type)}">${safe(t)}</div>`:''}
function open(id){$(id)?.classList.remove('hidden')}
function close(id){$(id)?.classList.add('hidden')}
async function rpc(name,args){const{data,error}=await state.client.rpc(name,args);if(error)throw error;return data}
function colours(l){return Array.isArray(l?.colours)?l.colours:[]}
function currentLot(id){return state.lots.find(x=>x.canonical_lot_id===id)}
function lotAlterQty(lotNo){return state.alters.filter(a=>a.lot_no===lotNo).reduce((n,a)=>n+Number(a.pending_qty||0),0)}
function roleOf(auth){return String(auth?.role||auth?.user_role||auth?.profile?.role||auth?.profile?.user_role||'WORKER').toUpperCase()}
function authValue(...keys){for(const key of keys){const parts=key.split('.');let v=state.auth;for(const p of parts)v=v?.[p];if(v!==undefined&&v!==null&&v!=='')return v}return null}
function prepareAlterUser(lot){
  const firstColour=colours(lot)[0]||{};
  window.supabaseClient=state.client;
  window.REDZED_USER={
    id:authValue('user.id','id','profile.id','profile.user_id')||state.auth?.user?.id,
    name:authValue('name','full_name','user_name','profile.name','profile.full_name','user.email')||'Worker',
    role:roleOf(state.auth),
    department_id:authValue('department_id','profile.department_id'),
    department_name:authValue('department_name','profile.department_name')||firstColour.current_department_code||'Production',
    line_man_id:authValue('line_man_id','profile.line_man_id'),
    line_man_name:authValue('line_man_name','profile.line_man_name'),
    cutting_master_id:authValue('cutting_master_id','profile.cutting_master_id'),
    cutting_master_name:authValue('cutting_master_name','profile.cutting_master_name')
  };
}
async function load(){
  try{
    msg('Loading…');
    const [d,l,a,e]=await Promise.all([
      state.client.from('rr_upm_departments').select('*').eq('is_active',true).order('sequence_no'),
      state.client.from('rr_upm_lot_board_v1').select('*').order('board_updated_at',{ascending:false}),
      state.client.from('rr_up_alter_card_v1').select('*').not('status','in','(CLOSED,CANCELLED)').order('created_at',{ascending:false}),
      state.client.from('rr_upm_entries').select('id,created_at').gte('created_at',new Date(new Date().setHours(0,0,0,0)).toISOString())
    ]);
    for(const r of[d,l,a,e])if(r.error)throw r.error;
    state.depts=d.data||[];state.lots=l.data||[];state.alters=a.data||[];
    fillSelects();render();
    $('sLots').textContent=state.lots.filter(x=>!['CLOSED','CANCELLED'].includes(String(x.status).toUpperCase())).length;
    $('sColours').textContent=state.lots.reduce((n,x)=>n+colours(x).length,0);
    $('sAlters').textContent=state.alters.length;
    $('sToday').textContent=(e.data||[]).length;
    msg('');
  }catch(e){console.error(e);msg(e.message,'error')}
}
function fillSelects(){
  const opts=state.depts.map(d=>`<option value="${safe(d.department_code)}">${safe(d.department_name)}</option>`).join('');
  $('eDept').innerHTML=opts;
  $('deptFilter').innerHTML='<option value="">All departments</option>'+opts;
}
function render(){
  const q=$('search').value.trim().toLowerCase(),df=$('deptFilter').value;
  const rows=state.lots.filter(l=>{
    const text=[l.lot_no,l.art_no,l.item_name].join(' ').toLowerCase();
    return(!q||text.includes(q))&&(!df||colours(l).some(c=>c.current_department_code===df));
  });
  $('board').innerHTML=rows.length?rows.map(l=>{
    const pending=lotAlterQty(l.lot_no);
    return `<article class="card">
      <div class="muted">${safe(l.art_no||'')} · ${safe(l.item_name||'')}</div>
      <h3>${safe(l.lot_no)}</h3>
      <div class="muted">Qty ${Number(l.total_qty||0)} · ${safe(l.status)}</div>
      ${pending>0?`<div class="alter-alert">ALTER : ${pending} PCS</div>`:''}
      <div>${colours(l).map(c=>`<span class="chip ${c.status==='COMPLETED'?'done':c.status==='PARTIAL'?'partial':''}">${safe(c.colour_name||c.colour_code)} → ${safe(c.current_department_code)} · ${safe(c.status)}</span>`).join('')||'<span class="muted">No colour state</span>'}</div>
      <div class="actions"><button data-entry="${safe(l.canonical_lot_id)}">Add entry</button><button class="primary" data-alter="${safe(l.canonical_lot_id)}">Alter / Remake / Damage</button></div>
    </article>`;
  }).join(''):'<div class="empty">No production lots found.</div>';
  document.querySelectorAll('[data-entry]').forEach(b=>b.onclick=()=>openEntry(b.dataset.entry));
  document.querySelectorAll('[data-alter]').forEach(b=>b.onclick=()=>openAlterModule(b.dataset.alter));
}
function setColourSelect(id,l){$(id).innerHTML=colours(l).map(c=>`<option value="${safe(c.colour_code)}">${safe(c.colour_name||c.colour_code)}</option>`).join('')||'<option value="GENERAL">General</option>'}
function openEntry(id){const l=currentLot(id);$('eLot').value=id;setColourSelect('eColour',l);const c=colours(l)[0];if(c?.current_department_code)$('eDept').value=c.current_department_code;open('entryModal')}
function openAlterModule(id){
  const l=currentLot(id);if(!l)return;
  prepareAlterUser(l);
  $('alterModuleTitle').textContent=`Alter / Remake / Damage — ${l.lot_no}`;
  open('alterModuleModal');
  try{window.RedzedAlter.mount('#alterRoot',{lotNo:l.lot_no,departmentName:window.REDZED_USER.department_name})}
  catch(e){console.error(e);alert(e.message)}
}
async function saveEntry(ev){ev.preventDefault();try{await rpc('rr_upm_post_entry_v1',{p_canonical_lot_id:$('eLot').value,p_department_code:$('eDept').value,p_colour_code:$('eColour').value,p_size_code:$('eSize').value,p_entry_type:$('eType').value,p_qty:Number($('eQty').value),p_rate:Number($('eRate').value||0),p_remarks:$('eRemarks').value||null});close('entryModal');ev.target.reset();await load()}catch(e){alert(e.message)}}
async function register(ev){ev.preventDefault();try{let cs=[];if($('rColours').value.trim())cs=JSON.parse($('rColours').value);await rpc('rr_upm_register_lot_v1',{p_canonical_lot_id:$('rId').value.trim(),p_lot_no:$('rLotNo').value.trim(),p_source_table:'MANUAL',p_source_id:null,p_art_no:$('rArt').value||null,p_item_name:$('rItem').value||null,p_total_qty:Number($('rQty').value||0),p_colours:cs,p_metadata:{registered_from:'UPM_UI'}});close('registerModal');ev.target.reset();await load()}catch(e){alert(e.message)}}
async function boot(){
  try{
    state.client=window.supabaseClient||window.sb;if(!state.client)throw new Error('Supabase client unavailable');
    state.auth=await RR.requireRoles(['owner','admin','production','manager','line_manager','worker','department_head','cutting_master']);
    $('refresh').onclick=load;$('registerBtn').onclick=()=>open('registerModal');$('search').oninput=render;$('deptFilter').onchange=render;
    $('entryForm').onsubmit=saveEntry;$('registerForm').onsubmit=register;
    document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>close(b.dataset.close));
    await load();
  }catch(e){console.error(e);msg(e.message,'error')}
}
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot):boot();
})();
