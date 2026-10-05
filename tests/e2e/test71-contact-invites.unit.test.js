const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const source=fs.readFileSync(path.resolve(__dirname,'../../real-chat-add-customer-test67.js'),'utf8');
function fixture(){
  const nodes=new Map();
  function node(){return {textContent:'',disabled:false,children:[],style:{},append(...items){this.children.push(...items)},appendChild(item){this.children.push(item)},replaceChildren(...items){this.children=items},scrollIntoView(){},focus(){},setAttribute(){}}}
  const document={querySelector:()=>null,getElementById:id=>{if(!nodes.has(id))nodes.set(id,node());return nodes.get(id)},createElement:node};
  const calls=[],opened=[];
  const window={open:()=>({opener:null,location:{replace:url=>opened.push(url)},close(){}})};
  const supabaseClient={auth:{getSession:async()=>({data:{session:{user:{id:'auth'}}}})},from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{id:'owner',role_code:'SUPER_ADMIN',is_active:true}})})})})};
  const RF853={rpc:async(name,args)=>{calls.push({name,args});return {token:'token-'+args.p_default_mobile}}};
  const context={window,document,supabaseClient,RF853,URL,location:{href:'https://fixture.test/chat.html?chat_id=secret&t=old#private'},setTimeout:()=>0,clearTimeout:()=>{}};
  const instrumented=source.replace("document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot,{once:true}):boot()",'window.testApi={save,setPhones:list=>{phones=list},contactPhone,uniqueDirectory,parseVcards,saveDirectory,setOwner:id=>{ownerId=id},setDb:f=>{contactDb=f},inviteRecipients,queueInvites,sendQueuedInvite,setRows:r=>{directoryRows=r},select:ids=>{selectedContacts=new Set(ids)},queue:()=>inviteQueue}');
  vm.runInNewContext(instrumented,context);
  return {...context,api:window.testApi,nodes,calls,opened,node};
}
const rows=Array.from({length:205},(_,i)=>({id:'id'+i,name:'Person '+i,numbers:[String(9000000000+i)]}));
test('normalizes Indian WhatsApp numbers, deduplicates and rejects invalid entries',()=>{
  const f=fixture();const result=f.api.inviteRecipients([...rows,{name:'Duplicate',numbers:['+919000000000']},{name:'Bad',numbers:['abc']}]);
  assert.equal(result.length,205);assert.equal(result[0].whatsapp,'919000000000');
});
test('selected queue respects IDs and does not create invites before share',()=>{
  const f=fixture();f.api.setRows(f.api.inviteRecipients(rows));f.api.select(['id0','id204']);f.api.queueInvites(false);
  assert.equal(f.api.queue().length,2);assert.equal(f.api.queue()[1].name,'Person 204');assert.equal(f.calls.length,0);
});
test('all includes contacts beyond displayed/search results',()=>{
  const f=fixture();f.api.setRows(f.api.inviteRecipients(rows));f.api.select(['id0']);f.api.queueInvites(true);
  assert.equal(f.api.queue().length,205);assert.equal(f.nodes.get('rr67InviteQueue').children.length,205);
});
test('separate recipient link, clean query, and reuse without claiming delivery',async()=>{
  const f=fixture();f.api.setRows(f.api.inviteRecipients(rows.slice(0,2)));f.api.queueInvites(true);const [first,second]=f.api.queue();
  const wa=f.node(),sms=f.node();await f.api.sendQueuedInvite(first,'whatsapp',wa,sms);await f.api.sendQueuedInvite(first,'whatsapp',wa,sms);await f.api.sendQueuedInvite(second,'whatsapp',wa,sms);
  assert.equal(f.calls.length,2);const url=new URL(f.opened[0]);assert.equal(url.pathname,'/919000000000');const message=url.searchParams.get('text');assert(message.includes('token-%2B919000000000'));assert(!message.includes('chat_id=secret'));assert(!message.includes('t=old'));assert(!message.includes('#private'));
  assert(new URL(f.opened[2]).searchParams.get('text').includes('token-%2B919000000001'));assert(first.statusNode.textContent.includes('delivery की पुष्टि नहीं'));assert.equal(wa.disabled,false);
});
test('blocked popup exposes a clickable link, RPC failure restores actions',async()=>{
  const f=fixture();f.window.open=()=>null;f.api.setRows(f.api.inviteRecipients(rows.slice(0,2)));f.api.queueInvites(true);const [first,second]=f.api.queue();const wa=f.node(),sms=f.node();
  await f.api.sendQueuedInvite(first,'whatsapp',wa,sms);assert.equal(first.statusNode.children[0].target,'_blank');assert(first.statusNode.children[0].href.startsWith('https://wa.me/'));
  f.RF853.rpc=async()=>{throw Error('sensitive backend error')};await f.api.sendQueuedInvite(second,'whatsapp',wa,sms);assert.equal(second.statusNode.textContent,'लिंक तैयार नहीं हुआ। दोबारा कोशिश करें।');assert.equal(wa.disabled,false);assert.equal(f.nodes.get('rr67SendAll').disabled,false);
});
test('invite controls are wired into staff chat and hidden directory stays hidden',()=>{
  const html=fs.readFileSync(path.resolve(__dirname,'../../real-sales-live-chat-v9434.html'),'utf8');assert(html.includes('real-chat-add-customer-test67.js?v=TEST71-INVITE-LOADER-20261005'));assert(source.includes('#rr67Directory[hidden]{display:none}'));
});

 test('4700 contacts stay 4700 after repeated imports and 80000 duplicate entries',()=>{
  const f=fixture(),contacts=Array.from({length:4700},(_,i)=>({name:'Person '+i,numbers:[String(9000000000+i)]}));
  let saved=f.api.uniqueDirectory(contacts);
  for(let i=0;i<4;i++)saved=f.api.uniqueDirectory([...contacts,...saved]);
  assert.equal(saved.length,4700);
  const repeated=Array.from({length:80000},(_,i)=>({...contacts[i%4700],numbers:[i%2?'+91 '+contacts[i%4700].numbers[0]:'0'+contacts[i%4700].numbers[0]]}));
  assert.equal(f.api.uniqueDirectory(repeated).length,4700);
 });
 test('overlapping multi-number cards merge; same names with different numbers remain',()=>{
  const f=fixture();const result=f.api.uniqueDirectory([{name:'Same',numbers:['9000000000']},{name:'Same',numbers:['9000000001']},{name:'Bridge',numbers:['+919000000000','00919000000001']}]);
  assert.equal(result.length,1);assert.equal(result[0].numbers.length,2);
  assert.equal(f.api.uniqueDirectory([{name:'Same',numbers:['9000000000']},{name:'Same',numbers:['9000000001']}]).length,2);
  const vcf='BEGIN:VCARD\r\nFN:Person\r\nTEL;TYPE=CELL:tel:+91 9000000000;ext=4\r\nEND:VCARD';
  assert.equal(f.api.parseVcards(vcf)[0].numbers[0],'+919000000000');
 });
 test('atomic directory update uses stable IDs, keeps other owners, and repeats without growth',async()=>{
  const f=fixture();f.api.setOwner('owner');const data=new Map([['other',{id:'other',ownerId:'other',name:'Other',numbers:['8000000000']}] ]);
  f.api.setDb(async()=>({close(){},transaction(){const tx={};const table={getAll(){const r={};queueMicrotask(()=>{r.result=[...data.values()];r.onsuccess();queueMicrotask(()=>tx.oncomplete())});return r},delete:id=>data.delete(id),put:row=>data.set(row.id,row)};tx.objectStore=()=>table;tx.abort=()=>tx.onabort();return tx}}));
  const contacts=[{name:'A',numbers:['9000000000']},{name:'Duplicate',numbers:['+919000000000']}];
  const first=await f.api.saveDirectory(contacts);assert.equal(first.total,1);assert.equal(first.duplicates,1);assert(data.has('owner|+919000000000'));
  const again=await f.api.saveDirectory(contacts);assert.equal(again.total,1);assert.equal(again.added,0);assert.equal(data.size,2);assert(data.has('other'));
 });

 test('create invite shows missing-name and invalid-number validation inside form',async()=>{
  const f=fixture();f.document.getElementById('rr67Name').value='';f.document.getElementById('rr67Mobile').value='';f.document.getElementById('rr67Kind').value='CUSTOMER';f.api.setPhones(['9873887784']);await f.api.save();assert(f.nodes.get('rr67SaveStatus').textContent.includes('नाम'));assert.equal(f.calls.length,0);
  f.nodes.get('rr67Name').value='Customer';f.api.setPhones(['bad']);await f.api.save();assert(f.nodes.get('rr67SaveStatus').textContent.includes('mobile'));assert.equal(f.calls.length,0);
 });
 test('create invite produces visible share links and restores button after error',async()=>{
  const f=fixture();for(const [id,value] of Object.entries({rr67Name:'Customer',rr67Mobile:'',rr67Kind:'CUSTOMER',rr67Prefix:''}))f.document.getElementById(id).value=value;f.api.setPhones(['9873887784']);await f.api.save();assert.equal(f.nodes.get('rr67Result').hidden,false);assert(f.nodes.get('rr67Wa').href.startsWith('https://wa.me/919873887784'));assert.equal(f.nodes.get('rr67Save').disabled,false);assert(f.nodes.get('rr67SaveStatus').textContent.includes('लिंक तैयार'));
  f.RF853.rpc=async()=>{throw Error('function does not exist')};await f.api.save();assert(f.nodes.get('rr67SaveStatus').textContent.includes('setup'));assert.equal(f.nodes.get('rr67Result').hidden,true);assert.equal(f.nodes.get('rr67Save').disabled,false);
 });
 test('double tap while invite request is pending creates only one request',async()=>{
  const f=fixture();for(const [id,value] of Object.entries({rr67Name:'Customer',rr67Mobile:'',rr67Kind:'CUSTOMER',rr67Prefix:''}))f.document.getElementById(id).value=value;f.api.setPhones(['9873887784']);let finish,count=0;f.RF853.rpc=()=>{count++;return new Promise(resolve=>finish=resolve)};const pending=f.api.save();await new Promise(resolve=>setImmediate(resolve));await f.api.save();assert.equal(count,1);finish({token:'one'});await pending;
 });
