(()=>{
'use strict';

const $=id=>document.getElementById(id);

const state={
  client:null,
  current:null
};

const safe=value=>String(value??'').replace(
  /[&<>"']/g,
  char=>({
    '&':'&amp;',
    '<':'&lt;',
    '>':'&gt;',
    '"':'&quot;',
    "'":'&#039;'
  })[char]
);

const err=error=>[
  error?.message,
  error?.details,
  error?.hint,
  error?.code
].filter(Boolean).join(' — ')||'Unknown error';

function say(text,type=''){
  $('message').textContent=text||'';
  $('message').className=`message ${type}`.trim();
}

async function rpc(name,payload={}){
  const result=await state.client.rpc(name,payload);
  if(result.error)throw result.error;
  return result.data;
}

function render(){
  const item=state.current||{};

  $('phaseValue').textContent=item.lifecycle_phase||'—';
  $('defaultValue').textContent=item.default_mode||'—';
  $('protectedValue').textContent=item.protected_mode||'—';
  $('feedValue').textContent=
    item.main_data_feed_started?'YES':'NO';

  $('phaseCard').className=
    `card ${
      item.lifecycle_phase==='REAL_LIVE'
        ?'live'
        :'testing'
    }`;

  if(item.lifecycle_phase==='REAL_LIVE'){
    $('ruleText').innerHTML=
      '<b>REAL_LIVE:</b> All modules open in REAL by default. TEST is protected and opens only after permission plus explicit confirmation.';

    $('confirmationHelp').innerHTML=
      'To return to TEST default, type exactly:<br><b>RETURN TO TESTING</b>';
  }else{
    $('ruleText').innerHTML=
      '<b>TESTING:</b> All modules open in TEST by default. REAL is protected and never auto-opens.';

    $('confirmationHelp').innerHTML=
      'When MAIN / REAL data feeding actually starts, type exactly:<br><b>START REAL DATA</b>';
  }

  $('startReal').disabled=
    item.lifecycle_phase==='REAL_LIVE';

  $('returnTesting').disabled=
    item.lifecycle_phase==='TESTING';
}

async function loadAudit(){
  const result=await state.client
    .from('rr_app_data_mode_audit_v786')
    .select('*')
    .order('changed_at',{ascending:false})
    .limit(100);

  if(result.error)throw result.error;

  const rows=result.data||[];

  $('auditBody').innerHTML=rows.length
    ?rows.map(row=>`
      <tr>
        <td>${safe(
          new Date(row.changed_at).toLocaleString(
            'en-IN',
            {timeZone:'Asia/Kolkata'}
          )
        )}</td>
        <td>${safe(row.old_phase||'—')}</td>
        <td>${safe(row.new_phase||'—')}</td>
        <td>${safe(row.old_default_mode||'—')}</td>
        <td>${safe(row.new_default_mode||'—')}</td>
        <td>${safe(row.changed_by_name||'—')}</td>
        <td>${safe(row.change_reason||'—')}</td>
      </tr>
    `).join('')
    :'<tr><td colspan="7">No phase changes yet.</td></tr>';
}

async function loadState(){
  try{
    say('Loading global Data Mode state…','info');

    state.current=await rpc(
      'rr_app_data_mode_state_v786'
    );

    render();
    await loadAudit();

    say(
      `${state.current.lifecycle_phase} · Default ${state.current.default_mode} · Protected ${state.current.protected_mode}`,
      'success'
    );
  }catch(error){
    say(err(error),'error');
  }
}

async function setPhase(phase){
  try{
    const confirmation=$('confirmationText').value.trim();
    const reason=$('changeReason').value.trim();

    const targetLabel=phase==='REAL_LIVE'
      ?'START MAIN / REAL DATA FEED'
      :'RETURN TO TESTING DEFAULT';

    if(!window.confirm(
      `${targetLabel}\n\n`+
      'This changes the default Data Mode for all connected modules.\n'+
      'Continue?'
    ))return;

    say('Updating global phase…','info');

    const result=await rpc(
      'rr_app_data_mode_set_phase_v786',
      {
        p_new_phase:phase,
        p_confirmation_text:confirmation,
        p_change_reason:reason
      }
    );

    state.current=result.state;

    $('confirmationText').value='';
    $('changeReason').value='';

    if(window.RRDataMode){
      await RRDataMode.refresh();
    }

    render();
    await loadAudit();

    say(
      `Global phase updated. New default: ${state.current.default_mode}. Reload open modules.`,
      'success'
    );
  }catch(error){
    say(err(error),'error');
  }
}

function bind(){
  $('startReal').onclick=()=>setPhase('REAL_LIVE');
  $('returnTesting').onclick=()=>setPhase('TESTING');
  $('refreshState').onclick=loadState;
}

async function boot(){
  try{
    state.client=
      window.supabaseClient||
      window.supabaseDb||
      window.redzedSupabase||
      window.sb;

    if(!state.client){
      throw new Error('Supabase client unavailable.');
    }

    if(window.RR?.requireOwner){
      await RR.requireOwner();
    }else{
      throw new Error('Owner/Admin access helper unavailable.');
    }

    bind();
    await loadState();

    $('accessBadge').textContent='OWNER ACCESS OK';
  }catch(error){
    $('accessBadge').textContent='ACCESS ERROR';
    say(err(error),'error');
  }
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',boot);
}else{
  boot();
}
})();
