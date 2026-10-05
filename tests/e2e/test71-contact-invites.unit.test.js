const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const source=fs.readFileSync(path.resolve(__dirname,'../../real-chat-add-customer-test67.js'),'utf8');
function fixture(){
  const nodes=new Map();
  function node(){return {textContent:'',disabled:false,children:[],style:{},append(...items){this.children.push(...items)},appendChild(item){this.children.push(item)},replaceChildren(...items){this.children=items},scrollIntoView(){},setAttribute(){}}}
  const document={getElementById:id=>{if(!nodes.has(id))nodes.set(id,node());return nodes.get(id)},createElement:node};
  const calls=[],opened=[];
  const window={open:()=>({opener:null,location:{replace:url=>opened.push(url)},close(){}})};
  const supabaseClient={auth:{getSession:async()=>({data:{session:{user:{id:'auth'}}}})},from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{id:'owner',role_code:'SUPER_ADMIN',is_active:true}})})})})};
  const RF853={rpc:async(name,args)=>{calls.push({name,args});return {token:'token-'+args.p_default_mobile}}};
  const context={window,document,supabaseClient,RF853,URL,location:{href:'https://fixture.test/chat.html?chat_id=secret&t=old#private'},setTimeout:()=>0};
  const instrumented=source.replace("document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot,{once:true}):boot()",'window.testApi={inviteRecipients,queueInvites,sendQueuedInvite,setRows:r=>{directoryRows=r},select:ids=>{selectedContacts=new Set(ids)},queue:()=>inviteQueue}');
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
  assert.equal(f.calls.length,2);const url=new URL(f.opened[0]);assert.equal(url.pathname,'/919000000000');const message=url.searchParams.get('text');assert(message.includes('token-9000000000'));assert(!message.includes('chat_id=secret'));assert(!message.includes('t=old'));assert(!message.includes('#private'));
  assert(f.opened[2].includes('token-9000000001'));assert(first.statusNode.textContent.includes('delivery की पुष्टि नहीं'));assert.equal(wa.disabled,false);
});
test('blocked popup exposes a clickable link, RPC failure restores actions',async()=>{
  const f=fixture();f.window.open=()=>null;f.api.setRows(f.api.inviteRecipients(rows.slice(0,2)));f.api.queueInvites(true);const [first,second]=f.api.queue();const wa=f.node(),sms=f.node();
  await f.api.sendQueuedInvite(first,'whatsapp',wa,sms);assert.equal(first.statusNode.children[0].target,'_blank');assert(first.statusNode.children[0].href.startsWith('https://wa.me/'));
  f.RF853.rpc=async()=>{throw Error('sensitive backend error')};await f.api.sendQueuedInvite(second,'whatsapp',wa,sms);assert.equal(second.statusNode.textContent,'लिंक तैयार नहीं हुआ। दोबारा कोशिश करें।');assert.equal(wa.disabled,false);assert.equal(f.nodes.get('rr67SendAll').disabled,false);
});
test('invite controls are wired into staff chat and hidden directory stays hidden',()=>{
  const html=fs.readFileSync(path.resolve(__dirname,'../../real-sales-live-chat-v9434.html'),'utf8');assert(html.includes('real-chat-add-customer-test67.js?v=TEST71-CONTACT-INVITES-20261005'));assert(source.includes('#rr67Directory[hidden]{display:none}'));
});
