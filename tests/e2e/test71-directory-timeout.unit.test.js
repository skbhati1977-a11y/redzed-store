const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../test70-real-chat-live-v70.js'),'utf8');
function setup(){const timers=new Map();let next=0;const context={Promise,Error,setTimeout:(fn,ms)=>{assert.equal(ms,15000);timers.set(++next,fn);return next},clearTimeout:id=>timers.delete(id)};vm.createContext(context);vm.runInContext(source.slice(source.indexOf('async function directoryRequestTest71('),source.indexOf('async function rpc(')),context);return{context,timers}}
test('Pending directory request exits loading after 15 seconds and late response cannot replace timeout',async()=>{const {context,timers}=setup();let resolve;const response=new Promise(r=>resolve=r);const result=context.directoryRequestTest71(()=>response);await Promise.resolve();const rejection=assert.rejects(result,/Directory request timed out/);[...timers.values()][0]();await rejection;assert.equal(timers.size,0);resolve({departments:[{department_code:'LATE'}]});await Promise.resolve();assert.equal(timers.size,0)});
test('Successful directory response retains canonical data and clears watchdog',async()=>{const {context,timers}=setup(),data={departments:[{department_code:'READYMADE'}]};assert.equal(await context.directoryRequestTest71(()=>Promise.resolve(data)),data);assert.equal(timers.size,0)});
test('Directory backend error propagates and clears watchdog',async()=>{const {context,timers}=setup();await assert.rejects(context.directoryRequestTest71(()=>Promise.reject(Error('Permission denied'))),/Permission denied/);assert.equal(timers.size,0)});

test('Early background refresh fetches canonical directory instead of committing empty boot state',async()=>{
 const expression=source.match(/directory=(fast[^;]+);/)[1];
 for(const [departments,actor,expected] of [[[],null,1],[[{department_code:'FOLDING'}],null,1],[[{department_code:'FOLDING'}],{worker_id:'owner'},0]]){
  let requests=0;const canonical={departments:[{department_code:'FOLDING'}],people:[{worker_id:'owner'}],actor:{worker_id:'owner'}};
  const result=await vm.runInNewContext(expression,{fast:true,S:{departments,people:[],actor},Promise,rpc:name=>{assert.equal(name,'rr_real_chat_directory_v85');requests++;return Promise.resolve(canonical)}});
  assert.equal(requests,expected);assert.equal(result.departments.length,1);
 }
});
