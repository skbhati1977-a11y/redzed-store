(() => {
  'use strict';
  if(window.__RR_CUSTOMER_LOGIN_APPROVALS71__)return;
  window.__RR_CUSTOMER_LOGIN_APPROVALS71__=true;
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let rows=[],button=null,sheet=null,busy=false;
  const rpc=async(name,args={})=>{if(window.RF853?.rpc)return RF853.rpc(name,args);const {data,error}=await window.supabaseClient.rpc(name,args);if(error)throw error;return data;};
  function render(){
    if(!sheet)return;
    const content=sheet.querySelector('[data-requests]');
    content.innerHTML=rows.length?rows.slice().sort((a,b)=>(b.status==='PENDING')-(a.status==='PENDING')).map(row=>`
      <article style="padding:14px;margin:10px 0;border:1px solid #40536b;border-radius:12px;background:#121c29">
        <b>${esc(row.customer_name)}</b><p style="margin:7px 0">Registered number: <a style="color:#9ed5ff" href="tel:+91${esc(row.registered_mobile)}">${esc(row.registered_mobile)}</a></p>
        <p style="margin:7px 0">Request name: ${esc(row.requested_name)}<br>Request number: ${esc(row.requested_mobile)}<br>Device: ${esc(row.device_label)} · ${esc(new Date(row.requested_at).toLocaleString())}</p>
        <b>${esc(row.status)}</b>
        <div style="display:flex;flex-wrap:wrap;gap:7px;margin-top:12px">
          ${row.status==='PENDING'?`<button data-decision="APPROVED" data-request="${esc(row.request_id)}">VERIFY NUMBER & APPROVE</button><button data-decision="REJECTED" data-request="${esc(row.request_id)}">REJECT</button>`:''}
          ${row.status==='APPROVED'?`<button data-decision="REVOKED" data-request="${esc(row.request_id)}">REVOKE DEVICE ACCESS</button>`:''}
        </div>
      </article>`).join(''):'No login requests.';
    sheet.querySelectorAll('button').forEach(el=>{el.style.cssText='padding:10px;border:1px solid #52647d;border-radius:9px;background:#fff;color:#111;font-weight:800;cursor:pointer';});
  }
  function close(){sheet?.remove();sheet=null;}
  function open(){
    close();sheet=document.createElement('div');sheet.id='rrCustomerLoginApprovalSheet71';
    sheet.setAttribute('role','dialog');sheet.setAttribute('aria-modal','true');sheet.setAttribute('aria-label','Customer login approvals');
    sheet.style.cssText='position:fixed;inset:0;z-index:2147483600;background:#000b;display:grid;place-items:center;padding:12px;color:#fff;font-family:system-ui';
    sheet.innerHTML='<section style="box-sizing:border-box;width:min(680px,100%);max-height:90vh;overflow:auto;padding:18px;border:1px solid #40536b;border-radius:16px;background:#0c1118"><div style="display:flex;justify-content:space-between;gap:12px"><b style="font-size:20px">CUSTOMER LOGIN REQUESTS</b><button data-close>CLOSE ×</button></div><p>New customer/device login के लिए original registered number पर customer की पहचान verify करें। उसके बाद Approve करें। App अपने-आप SIM number verify नहीं करता।</p><div data-status role="status" aria-live="polite"></div><div data-requests></div></section>';
    sheet.onclick=async event=>{
      if(event.target===sheet||event.target.closest('[data-close]'))return close();
      const action=event.target.closest('[data-decision]');if(!action||busy)return;
      const row=rows.find(x=>x.request_id===action.dataset.request);if(!row)return;
      const approve=action.dataset.decision==='APPROVED';
      if(approve&&!confirm(`${row.customer_name} की पहचान original registered number ${row.registered_mobile} पर call/message करके verify कर ली है? इस नए device को access मिलेगा।`))return;
      if(!approve&&!confirm(`${action.dataset.decision==='REJECTED'?'Reject login request':'Revoke this device access'}?`))return;
      busy=true;action.disabled=true;
      try{await rpc('rr_customer_login_approval_decide_test71',{p_request_id:row.request_id,p_decision:action.dataset.decision,p_mobile_verified:approve});await refresh();}
      catch(error){sheet?.querySelector('[data-status]')&&(sheet.querySelector('[data-status]').textContent=error.message);}
      finally{busy=false;if(action.isConnected)action.disabled=false;}
    };
    document.body.appendChild(sheet);render();sheet.querySelector('[data-close]').focus();refresh().catch(error=>{if(sheet)sheet.querySelector('[data-status]').textContent=error.message;});
  }
  async function refresh(){
    const result=await rpc('rr_customer_login_approval_list_test71');rows=Array.isArray(result)?result:[];
    const count=rows.filter(row=>row.status==='PENDING').length;
    if(button){button.textContent=`LOGIN REQUESTS (${count})`;button.style.background=count?'#ffe095':'#182231';button.style.color=count?'#111':'#fff';}
    render();
  }
  async function boot(){
    if(!window.RF853?.rpc&&!window.supabaseClient?.rpc){setTimeout(boot,500);return;}
    // Server authorization decides whether this account can even list requests.
    try{await refresh();}catch(_){return;}
    button=document.createElement('button');button.type='button';button.id='rrCustomerLoginApprovals71';button.onclick=open;
    button.style.cssText='margin:6px;padding:9px;border:1px solid #52647d;border-radius:9px;font-size:11px;font-weight:900;cursor:pointer';
    const host=document.querySelector('.inbox .head')||document.querySelector('header')||document.body;host.appendChild(button);
    await refresh();
    setInterval(()=>{if(!document.hidden)refresh().catch(()=>{if(sheet)sheet.querySelector('[data-status]').textContent='Login requests अभी load नहीं हुईं।';});},15000);
  }
  document.addEventListener('keydown',event=>{if(event.key==='Escape')close();});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
