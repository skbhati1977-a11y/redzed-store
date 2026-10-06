(()=>{
 'use strict';
 const $=id=>document.getElementById(id),urls=[];let files=null,busy=false;
 const hash=async blob=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await blob.arrayBuffer())),b=>b.toString(16).padStart(2,'0')).join('');
 function validate(data){
  if(!Array.isArray(data.files)||!data.files.length||data.files.length>30)throw Error('Receipt link सही नहीं है. Sender से receipt दोबारा लें.');
  for(const f of data.files){const u=new URL(f.url);if(u.origin!=='https://hruartsemierwhtzonei.supabase.co'||!/^\/storage\/v1\/object\/public\/redzed-media\/readymade\/test71\/receipts\/[a-f0-9-]+\/[a-f0-9-]+\.jpg$/.test(u.pathname)||!/^[-a-z0-9_]+\.jpg$/i.test(f.name)||!/^[a-f0-9]{64}$/i.test(f.sha256))throw Error('Receipt link सही नहीं है. Sender से receipt दोबारा लें.')}
  return data;
 }
 let data;try{data=validate(JSON.parse(decodeURIComponent(location.hash.slice(1))));$('title').textContent=String(data.title||'REDZED Purchase Receipt').slice(0,160)}catch(e){$('message').textContent=e.message;return}
 const shareLink={title:String(data.title||'REDZED Purchase Receipt'),text:'REDZED Purchase Receipt',url:location.href};
 $('whatsapp').href='https://wa.me/?text='+encodeURIComponent(shareLink.title+'\n'+location.href);$('whatsapp').hidden=false;
 async function prepare(){
  if(busy)return;busy=true;files=null;$('share').disabled=true;$('retry').hidden=true;$('message').textContent='Saved receipt JPG खुल रही है…';urls.splice(0).forEach(u=>URL.revokeObjectURL(u));$('images').replaceChildren();
  try{const result=[];for(const f of data.files){const r=await fetch(f.url,{signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Receipt JPG नहीं खुली. Retry दबाएँ.');const blob=await r.blob();if(await hash(blob)!==f.sha256)throw Error('Receipt verification failed. Sender से receipt दोबारा लें.');const file=new File([blob],f.name,{type:'image/jpeg'});result.push(file);const url=URL.createObjectURL(file);urls.push(url);const section=document.createElement('section'),img=document.createElement('img'),a=document.createElement('a');img.src=url;img.alt=f.name;a.href=url;a.download=f.name;a.textContent='Save JPG · '+f.name;section.append(img,a);$('images').append(section)}files=result;$('share').disabled=false;$('message').textContent='Share JPG दबाएँ और app picker में WhatsApp / दूसरी app चुनें. File share बंद हो तो WhatsApp Receipt link चुनें या JPG save करें.'}
  catch(e){$('message').textContent=e.message||'Receipt नहीं खुली. Retry दबाएँ.';$('retry').hidden=false}finally{busy=false}
 }
 $('retry').onclick=prepare;
 $('share').onclick=()=>{
  if(!files||busy)return;const policy=document.permissionsPolicy||document.featurePolicy;let supported=typeof navigator.share==='function'&&!(policy?.allowsFeature&&!policy.allowsFeature('web-share')),fileSupported=supported;
  try{if(navigator.canShare)fileSupported=fileSupported&&navigator.canShare({files})}catch{fileSupported=false}
  const payload=fileSupported?{files,title:shareLink.title}:shareLink;try{if(navigator.canShare)supported=supported&&navigator.canShare(payload)}catch{supported=false}
  if(!supported){$('whatsapp').click();$('message').textContent='WhatsApp contact चुनें—receipt link जाएगा. JPG attachment के लिए Save JPG से file लें.';return}
  busy=true;$('share').disabled=true;let promise;try{promise=navigator.share(payload)}catch{busy=false;$('share').disabled=false;$('message').textContent='Share बंद है. WhatsApp Receipt link चुनें या Save JPG से file लें.';return}
  Promise.resolve(promise).then(()=>{$('message').textContent=(fileSupported?'JPG':'Receipt link')+' share app को दी गई. WhatsApp में contact चुनकर Send करें.'},e=>{$('message').textContent=e?.name==='AbortError'?'Share cancel हुई. फिर से Share दबा सकते हैं.':'Share नहीं खुला. WhatsApp Receipt link चुनें या Save JPG से file लें.'}).finally(()=>{busy=false;$('share').disabled=false});
 };
 window.addEventListener('pagehide',()=>urls.forEach(u=>URL.revokeObjectURL(u)),{once:true});prepare();
})();
