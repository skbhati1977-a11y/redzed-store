(() => {
 'use strict';
 if(window.__RR_CHAT_PDF_RENDER_9574__)return;window.__RR_CHAT_PDF_RENDER_9574__=true;
 // Render from the existing message response. Never poll the inbox or fetch
 // the full chat again in response to a DOM mutation.
 const data=new Map(),pending=new Map();
 const base=RF853.rpc.bind(RF853);
 RF853.rpc=async(name,args={})=>{const result=await base(name,args);if(/rr_chat_staff_messages_v/.test(name)&&Array.isArray(result)){result.forEach(m=>{if(m.payload?.mime_type==='application/pdf')data.set(String(m.id),m);});setTimeout(paint,0);}return result;};
 async function attachment(id){if(!pending.has(id))pending.set(id,RF853.rpc('rr_chat_staff_attachment_v9434',{p_attachment_id:id}).catch(e=>{pending.delete(id);throw e}));return pending.get(id)}
 function bytes(b64){return Uint8Array.from(atob(b64),c=>c.charCodeAt(0))}
 async function open(id){try{const d=await attachment(id);const url=URL.createObjectURL(new Blob([bytes(d.base64)],{type:'application/pdf'}));window.open(url,'_blank','noopener,noreferrer');setTimeout(()=>URL.revokeObjectURL(url),60000)}catch(e){const f=document.getElementById('flash');if(f){f.textContent=e.message;f.style.display='block'}}}
 async function preview(id,canvas){try{if(!window.pdfjsLib)return;const d=await attachment(id);pdfjsLib.GlobalWorkerOptions.workerSrc='https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';const pdf=await pdfjsLib.getDocument({data:bytes(d.base64)}).promise,page=await pdf.getPage(1),base=page.getViewport({scale:1}),view=page.getViewport({scale:360/base.width});canvas.width=view.width;canvas.height=view.height;await page.render({canvasContext:canvas.getContext('2d'),viewport:view}).promise;canvas.hidden=false}catch(_){canvas.hidden=true}}
 function paint(){document.querySelectorAll('#msgs .msg[data-msg-id]').forEach(row=>{const m=data.get(row.dataset.msgId),button=row.querySelector('[data-att]');if(!m||!button||button.dataset.pdf71)return;button.dataset.pdf71='1';button.onclick=()=>open(m.payload.attachment_id);const canvas=document.createElement('canvas');canvas.hidden=true;canvas.style.cssText='display:block;max-width:100%;height:auto;background:#fff';button.prepend(canvas);preview(m.payload.attachment_id,canvas)});}
 const root=document.getElementById('msgs');if(root)new MutationObserver(paint).observe(root,{childList:true,subtree:true});
})();
