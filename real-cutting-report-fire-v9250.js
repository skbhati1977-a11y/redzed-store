(()=>{
'use strict';
if(window.__RR_CUTTING_REPORT_FIRE_9251__)return;
window.__RR_CUTTING_REPORT_FIRE_9251__=true;

let lastFireAt=0;
let lastType='';

function directReportButton(target){
  return target?.closest?.('[data-cba-report]')||null;
}

function pointReportButton(x,y){
  if(!Number.isFinite(x)||!Number.isFinite(y))return null;
  const stack=document.elementsFromPoint?.(x,y)||[];
  for(const node of stack){
    const button=node?.closest?.('[data-cba-report]');
    if(button)return button;
  }
  for(const button of document.querySelectorAll('[data-cba-report]')){
    const r=button.getBoundingClientRect();
    if(x>=r.left&&x<=r.right&&y>=r.top&&y<=r.bottom)return button;
  }
  return null;
}

function buttonForEvent(event){
  const direct=directReportButton(event?.target);
  if(direct)return direct;
  const touch=event?.changedTouches?.[0]||event?.touches?.[0];
  const x=touch?.clientX??event?.clientX;
  const y=touch?.clientY??event?.clientY;
  return pointReportButton(Number(x),Number(y));
}

function fire(button,event){
  if(!button)return false;
  const type=String(button.dataset.cbaReport||'');
  const now=Date.now();
  if(type&&type===lastType&&now-lastFireAt<900){
    event?.preventDefault?.();
    event?.stopImmediatePropagation?.();
    return true;
  }

  const handler=button.onclick;
  if(typeof handler!=='function')return false;

  event?.preventDefault?.();
  event?.stopImmediatePropagation?.();
  lastType=type;
  lastFireAt=now;
  handler.call(button,event);
  return true;
}

function capture(event){
  fire(buttonForEvent(event),event);
}

function escapeSelector(value){
  if(window.CSS&&typeof CSS.escape==='function')return CSS.escape(String(value||''));
  return String(value||'').replace(/["\\]/g,'\\$&');
}

function installLotDamageGrPlacement(){
  const styleId='rrDgrLotPlacement9252';
  if(!document.getElementById(styleId)){
    const style=document.createElement('style');
    style.id=styleId;
    style.textContent=`
      .cm-card>.rr-dgr-actions{display:none!important}
      #lotForm>.rr-dgr-lot-wrap{display:block!important;margin:2px 0 0;padding:13px 14px;border:1px solid #4b3439;border-radius:15px;background:#171114}
      .rr-dgr-lot-wrap>small{display:block;margin-bottom:8px;color:#ff9da6;font-size:11px;font-weight:900;letter-spacing:.05em}
      .rr-dgr-lot-wrap .rr-dgr-actions{display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px;margin:0;padding:0;border-top:0}
      .rr-dgr-lot-wrap .rr-dgr-actions button{min-height:44px}
      @media(max-width:650px){.rr-dgr-lot-wrap .rr-dgr-actions{grid-template-columns:repeat(3,minmax(0,1fr))}}
    `;
    document.head.appendChild(style);
  }

  const form=document.getElementById('lotForm');
  const notes=form?.querySelector('.cm-notes');
  const unitId=String(document.getElementById('lotUnitId')?.value||'').trim();
  if(!form||!notes||!unitId)return;

  document.querySelectorAll('.cm-card>.rr-dgr-actions').forEach(row=>{row.style.display='none';});

  let wrap=form.querySelector('.rr-dgr-lot-wrap');
  if(!wrap){
    wrap=document.createElement('section');
    wrap.className='rr-dgr-lot-wrap';
    wrap.innerHTML='<small>Damage / GR Decision</small><div class="rr-dgr-actions rr-dgr-popup-actions"></div>';
    notes.insertAdjacentElement('beforebegin',wrap);
  }

  if(wrap.dataset.divisionId===unitId&&wrap.querySelector('[data-dgr-type]'))return;
  wrap.dataset.divisionId=unitId;

  const sourceCard=document.querySelector(`.cm-card[data-division-id="${escapeSelector(unitId)}"]`);
  const sourceRow=sourceCard?.querySelector('.rr-dgr-actions');
  const target=wrap.querySelector('.rr-dgr-popup-actions');
  if(!target)return;

  const types=[
    ['DAMAGE','Report Damage'],
    ['PARTIAL_GR','Report Partial GR'],
    ['FULL_GR','Report Full GR']
  ];
  target.innerHTML=types.map(([type,label])=>`<button type="button" data-dgr-type="${type}">${label}</button>`).join('');
  target.querySelectorAll('[data-dgr-type]').forEach(button=>{
    const type=button.dataset.dgrType;
    button.addEventListener('click',event=>{
      event.preventDefault();
      event.stopPropagation();
      const freshCard=document.querySelector(`.cm-card[data-division-id="${escapeSelector(unitId)}"]`);
      const source=freshCard?.querySelector(`.rr-dgr-actions [data-dgr-type="${type}"]`)||sourceRow?.querySelector(`[data-dgr-type="${type}"]`);
      source?.click();
    });
  });
}

window.addEventListener('pointerdown',capture,true);
window.addEventListener('touchstart',capture,{capture:true,passive:false});
window.addEventListener('click',capture,true);

installLotDamageGrPlacement();
setInterval(installLotDamageGrPlacement,500);
})();
