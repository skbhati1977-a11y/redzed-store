(()=>{'use strict';
const states=new Map(),contexts=new Map();let timer=null;
function style(){if(document.getElementById('rrTickStyle71'))return;const s=document.createElement('style');s.id='rrTickStyle71';s.textContent='.rrTicks71{display:inline-block;margin-left:8px;color:#b7c2cf;font-size:15px;font-weight:900;letter-spacing:-3px}.rrTicks71.read{color:#53bdff}.rrReceiptStatus71.read{color:#53bdff!important}';document.head.appendChild(s);}
function state(r){return r.read?'read':r.delivered?'delivered':'sent';}
function paint(selector){style();document.querySelectorAll(selector+' [data-msg-id]').forEach(node=>{const r=states.get(node.dataset.msgId);if(!r?.own)return;const time=node.querySelector('time');if(!time)return;let el=time.querySelector('.rrTicks71');if(!el){el=document.createElement('span');el.className='rrTicks71';time.appendChild(el);}const v=state(r);el.classList.toggle('read',v==='read');el.textContent=v==='sent'?'✓':'✓✓';el.title=v[0].toUpperCase()+v.slice(1);el.setAttribute('aria-label',el.title);});}
function visible(node,host){if(document.visibilityState==='hidden')return false;if(host.closest('#rrFSChat')&&!host.closest('#rrFSChat.on'))return false;if(host.id==='msgs'&&document.querySelector('.sheetback.on,.rrReqBack9508.on'))return false;if(host.id==='fsMsgs'&&document.querySelector('#fcPanel.on,#rrMorePanel9630.on'))return false;const r=node.getBoundingClientRect(),h=host.getBoundingClientRect();const top=Math.max(r.top,h.top,0),bottom=Math.min(r.bottom,h.bottom,innerHeight);if(bottom-top<Math.min(40,r.height*0.3)||r.width<=0)return false;return true;}
async function sync(ctx){contexts.set(ctx.selector,ctx);const host=document.querySelector(ctx.selector);if(!host||ctx.busy)return;ctx.busy=true;
try{const ids=ctx.rows.map(x=>x.id).filter(Boolean).slice(-200);if(!ids.length)return;const readIds=ids.filter(id=>{const n=host.querySelector('[data-msg-id="'+CSS.escape(id)+'"]');return n&&visible(n,host);});const args={p_message_ids:ids,p_read_ids:readIds};if(ctx.mode==='CUSTOMER'){args.p_session_token=ctx.sessionToken;args.p_device_id=ctx.deviceId;}else args.p_chat_id=ctx.chatId;
const result=await RF853.rpc(ctx.mode==='CUSTOMER'?'rr_chat_customer_receipts_test71':'rr_chat_staff_receipts_test71',args);if(contexts.get(ctx.selector)!==ctx)return;for(const row of result||[])states.set(row.message_id,row);paint(ctx.selector);
}catch(_){/* Network failure keeps the last confirmed state; never invent delivery. */}finally{ctx.busy=false;}}
function refresh(){clearTimeout(timer);timer=setTimeout(()=>{for(const ctx of contexts.values())sync(ctx);},150);}
document.addEventListener('scroll',refresh,true);document.addEventListener('visibilitychange',refresh);
window.RRChatTicks71={sync,state};
})();
