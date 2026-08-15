(() => {
  'use strict';
  const frame=document.getElementById('upmFrame');
  if(!frame) return;
  let active='ALL', payload=null, packCards=[], readyBoxes=[], observer=null, timer=null;
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const up=v=>String(v||'').trim().toUpperCase();

  function ctx(){
    try{
      const d=frame.contentDocument,w=frame.contentWindow;if(!d||!w)return null;
      const u=new URL(w.location.href); if(!/real-finished-goods-v787\.html/i.test(u.pathname)) return null;
      const view=(u.searchParams.get('view')||'packing').toLowerCase();
      if(!['packing','despatch'].includes(view)) return null;
      const sb=w.supabaseClient||w.redzedSupabase||w.sb||window.supabaseClient||window.redzedSupabase||window.sb;
      return {d,w,sb,view,dept:view==='packing'?'PACKING':'DESPATCH'};
    }catch{return null;}
  }

  function style(d){if(d.getElementById('rr-upm-fg-v9093-style'))return;const s=d.createElement('style');s.id='rr-upm-fg-v9093-style';s.textContent=`
    .rr9093bar{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0;padding:9px;border:1px solid #303641;border-radius:12px;background:#10151d}
    .rr9093btn{border:1px solid #485364;background:#1b222d;color:#fff;border-radius:999px;padding:8px 11px;font-weight:900;cursor:pointer}.rr9093btn.on{background:#6b1f2b;border-color:#d64559}.rr9093btn.a{border-color:#c8992d}.rr9093btn.s{border-color:#318b65}.rr9093btn.x{border-color:#9b7a16}
    .rr9093alter{display:grid;gap:4px;margin:7px 0;padding:7px;border:1px solid #9b7a16;border-radius:9px;background:#332a08;font-size:10px}.rr9093line{display:flex;gap:6px;flex-wrap:wrap}.rr9093owner{font-weight:950}.rr9093hide{display:none!important}`;d.head.appendChild(s);}

  function totals(c){const alt=Number(payload?.totals?.active_alter_count||0);if(c.dept==='PACKING')return{a:packCards.filter(x=>!x.assignment_id).length,s:packCards.filter(x=>x.assignment_id&&['ASSIGNED','ACCEPTED'].includes(up(x.assignment_status))).length,x:alt};const lots=new Set(readyBoxes.map(x=>up(x.lot_no)).filter(Boolean));return{a:lots.size,s:0,x:alt};}
  function amap(){return new Map((payload?.lots||[]).map(x=>[up(x.lot_no),x.alter_journeys||[]]));}
  function alter(j){return !j?.length?'':`<div class="rr9093alter">${j.map(v=>`<div class="rr9093line"><b>${esc(v.journey_code||'ALTER')}</b><span>${esc(v.colour_code||'')} ${esc(v.size_code||'')} · ${Number(v.qty||0)} PCS</span><span class="rr9093owner">OWNER: ${esc(v.owner_name||'PENDING')} [${esc(String(v.owner_role||'').replaceAll('_',' '))}] · ${esc(v.owner_department_code||'')}</span><span>${esc(v.stage||'')}</span></div>`).join('')}</div>`;}

  function bar(c){const {d}=c;style(d);const view=d.querySelector(`.fg-view[data-view="${c.view}"]`);if(!view)return;let b=view.querySelector('.rr9093bar');if(!b){b=d.createElement('div');b.className='rr9093bar';view.prepend(b);}const t=totals(c);b.innerHTML=`<button class="rr9093btn ${active==='ALL'?'on':''}" data-rf="ALL">ALL</button><button class="rr9093btn a ${active==='ASSIGN'?'on':''}" data-rf="ASSIGN">ASSIGN DUE · ${t.a}</button><button class="rr9093btn s ${active==='SUBMIT'?'on':''}" data-rf="SUBMIT">SUBMIT DUE · ${t.s}</button><button class="rr9093btn x ${active==='ALTER'?'on':''}" data-rf="ALTER">ALTER ACTIVE · ${t.x}</button><span style="margin-left:auto;align-self:center;font-size:11px;color:#98a2b3;font-weight:800">${c.dept}</span>`;b.querySelectorAll('[data-rf]').forEach(x=>x.onclick=e=>{e.preventDefault();active=x.dataset.rf;bar(c);apply(c);});}

  function packing(c){const {d}=c,map=amap();[...d.querySelectorAll('#packLotCards > *')].forEach(card=>{card.querySelector?.('.rr9093alter')?.remove();const txt=up(card.textContent);const row=packCards.find(x=>txt.includes(up(x.lot_no)));if(!row)return;const js=map.get(up(row.lot_no))||[];if(js.length)card.insertAdjacentHTML('beforeend',alter(js));let show=true;if(active==='ASSIGN')show=!row.assignment_id;if(active==='SUBMIT')show=!!row.assignment_id&&['ASSIGNED','ACCEPTED'].includes(up(row.assignment_status));if(active==='ALTER')show=js.length>0;card.classList.toggle('rr9093hide',!show);});}
  function despatch(c){const {d}=c,map=amap(),body=d.getElementById('dispatchBoxRows');if(body)[...body.children].forEach(tr=>{const txt=up(tr.textContent),box=readyBoxes.find(x=>txt.includes(up(x.lot_no))||txt.includes(up(x.box_code))),js=box?(map.get(up(box.lot_no))||[]):[];let show=true;if(active==='ASSIGN')show=!!box;if(active==='SUBMIT')show=false;if(active==='ALTER')show=js.length>0;tr.classList.toggle('rr9093hide',!show);});let h=d.querySelector('.fg-view[data-view="despatch"] .rr9093holder');if(!h){h=d.createElement('div');h.className='rr9093holder';d.querySelector('.fg-view[data-view="despatch"] .fg-panel')?.prepend(h);}h.innerHTML=(payload?.lots||[]).filter(x=>(x.alter_journeys||[]).length).map(x=>`<div><b>${esc(x.lot_no)}</b>${alter(x.alter_journeys)}</div>`).join('');}
  function apply(c){c.dept==='PACKING'?packing(c):despatch(c);}

  async function load(){const c=ctx();if(!c?.sb)return;try{const [du,pa,bo]=await Promise.all([c.sb.rpc('rr_upm_lot_card_due_alter_header_v9092',{p_department_code:c.dept}),c.dept==='PACKING'?c.sb.rpc('rr_fg_ready_packing_cards_v788',{p_data_mode:'TEST'}):Promise.resolve({data:[]}),c.dept==='DESPATCH'?c.sb.from('rr_fg_ready_box_v787').select('box_id,box_code,lot_no,box_type,qty,data_mode').eq('data_mode','TEST'):Promise.resolve({data:[]})]);if(du.error)throw du.error;payload=du.data||{};packCards=Array.isArray(pa.data)?pa.data:[];readyBoxes=Array.isArray(bo.data)?bo.data:[];bar(c);apply(c);observer?.disconnect?.();observer=new MutationObserver(()=>apply(ctx()||c));observer.observe(c.d.body,{childList:true,subtree:true});}catch(e){console.warn('UPM FG V9093 due filter load failed',e);}}
  function start(){active='ALL';payload=null;packCards=[];readyBoxes=[];setTimeout(load,350);setTimeout(load,1200);clearInterval(timer);timer=setInterval(load,15000);}
  frame.addEventListener('load',start); if(frame.contentDocument?.readyState==='complete')start();
})();
