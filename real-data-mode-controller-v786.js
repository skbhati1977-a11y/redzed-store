(()=>{
'use strict';

if(window.__REAL_FACTORY_DATA_MODE_CONTROLLER_V786_1_1__)return;
window.__REAL_FACTORY_DATA_MODE_CONTROLLER_V786_1_1__=true;

const MODE_IDS=new Set([
  'dataMode',
  'payrollMode',
  'detailMode',
  'attendanceMode',
  'adjustmentMode',
  'ledgerMode',
  'historyMode',
  'sourceMode',
  'targetMode',
  'reportMode'
]);

let cachedState=null;
let statePromise=null;

const upper=value=>String(value||'').trim().toUpperCase();

function client(){
  return window.supabaseClient||
    window.supabaseDb||
    window.redzedSupabase||
    window.sb||
    null;
}

function isModeSelect(element){
  return element instanceof HTMLSelectElement
    &&(
      element.dataset.rrDataMode==='true'
      ||MODE_IDS.has(element.id)
      ||upper(element.name)==='DATA_MODE'
    );
}

async function rpc(name,payload={}){
  const db=client();
  if(!db)throw new Error(
    'Supabase client unavailable for Global Data Mode.'
  );

  const result=await db.rpc(name,payload);
  if(result.error)throw result.error;
  return result.data;
}

async function refreshState(force=false){
  if(force){
    cachedState=null;
    statePromise=null;
  }

  if(cachedState)return cachedState;

  if(!statePromise){
    statePromise=rpc(
      'rr_app_data_mode_state_v786'
    )
    .then(state=>{
      cachedState=state;
      document.documentElement.dataset.rrLifecyclePhase=
        state.lifecycle_phase||'TESTING';
      document.documentElement.dataset.rrDefaultDataMode=
        state.default_mode||'TEST';
      installPhaseBadge(state);
      scanUninitializedSelects(state);
      return state;
    })
    .catch(error=>{
      statePromise=null;
      throw error;
    });
  }

  return statePromise;
}

async function permission(mode){
  return rpc(
    'rr_app_data_mode_can_open_v786',
    {p_requested_mode:upper(mode)}
  );
}

async function authorize(mode,{confirmProtected=true}={}){
  const requested=upper(mode);
  const state=await refreshState();

  if(!['TEST','REAL'].includes(requested)){
    return {
      allowed:false,
      mode:state.default_mode,
      reason:'Invalid Data Mode.'
    };
  }

  if(requested===state.default_mode){
    return {
      allowed:true,
      mode:requested,
      protected:false
    };
  }

  const result=await permission(requested);

  if(!result?.allowed){
    window.alert(
      result?.message||
      `${requested} Data Mode permission required.`
    );

    return {
      allowed:false,
      mode:state.default_mode,
      protected:true,
      result
    };
  }

  if(result.requires_confirmation&&confirmProtected){
    const label=requested==='REAL'
      ?'OPEN PROTECTED REAL DATA'
      :'OPEN PROTECTED TEST DATA';

    const confirmed=window.confirm(
      `${result.message}\n\n`+
      `Selected Mode: ${requested}\n`+
      `Current Default: ${result.default_mode}\n\n`+
      `${label}?`
    );

    if(!confirmed){
      return {
        allowed:false,
        mode:state.default_mode,
        protected:true,
        result
      };
    }
  }

  return {
    allowed:true,
    mode:requested,
    protected:true,
    result
  };
}

function markApproved(select,mode){
  if(!select)return;

  const approved=upper(mode);
  select.value=approved;
  select.dataset.rrApprovedMode=approved;
  select.dataset.rrDataMode='true';
  select.dataset.rrModeInitialized='1';
}

async function resolveInitialMode(requestedMode=''){
  const state=await refreshState();
  const requested=upper(requestedMode);

  if(!requested){
    return state.default_mode;
  }

  const result=await authorize(requested);
  return result.allowed
    ?result.mode
    :state.default_mode;
}

async function applyInitialMode(selectOrId,requestedMode=''){
  const select=typeof selectOrId==='string'
    ?document.getElementById(selectOrId)
    :selectOrId;

  const mode=await resolveInitialMode(requestedMode);

  if(select)markApproved(select,mode);

  return mode;
}

async function applyInitialModes(ids=[],requestedMode=''){
  const mode=await resolveInitialMode(requestedMode);

  for(const item of ids){
    const select=typeof item==='string'
      ?document.getElementById(item)
      :item;

    if(select)markApproved(select,mode);
  }

  return mode;
}

function scanUninitializedSelects(state=cachedState){
  if(!state)return;

  document.querySelectorAll('select').forEach(select=>{
    if(!isModeSelect(select))return;
    if(select.dataset.rrModeInitialized==='1')return;

    markApproved(select,state.default_mode);
  });
}

function installPhaseBadge(state){
  // V799.2 UI cleanup: keep TEST/REAL protection active, hide only floating badge.
  document.getElementById('rr-global-data-mode-badge-v786-1-1')?.remove();
}


document.addEventListener(
  'change',
  event=>{
    const select=event.target;

    if(!isModeSelect(select))return;

    if(select.dataset.rrModeBypass==='1'){
      delete select.dataset.rrModeBypass;
      select.dataset.rrApprovedMode=upper(select.value);
      return;
    }

    const requested=upper(select.value);
    const previous=upper(
      select.dataset.rrApprovedMode||
      cachedState?.default_mode||
      'TEST'
    );

    if(requested===previous){
      select.dataset.rrApprovedMode=requested;
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();

    select.value=previous;

    void authorize(requested).then(result=>{
      if(!result.allowed){
        select.value=previous;
        return;
      }

      select.value=result.mode;
      select.dataset.rrApprovedMode=result.mode;
      select.dataset.rrModeBypass='1';

      select.dispatchEvent(
        new Event('change',{
          bubbles:true
        })
      );
    }).catch(error=>{
      console.error(error);
      window.alert(
        error?.message||
        'Data Mode permission check failed.'
      );
      select.value=previous;
    });
  },
  true
);

const ready=refreshState();
window.RRDataModeReadyPromise=ready;

if(document.readyState==='loading'){
  document.addEventListener(
    'DOMContentLoaded',
    ()=>void ready.then(scanUninitializedSelects)
  );
}else{
  void ready.then(scanUninitializedSelects);
}

window.RRDataMode={
  ready:()=>refreshState(),
  refresh:()=>refreshState(true),
  state:()=>cachedState,
  authorize,
  resolveInitialMode,
  applyInitialMode,
  applyInitialModes,
  markApproved,
  scan:scanUninitializedSelects
};
})();
