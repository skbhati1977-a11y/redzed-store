(()=>{
'use strict';
if(window.__RR_PI_REOPEN_SAVED_V9566__)return;
window.__RR_PI_REOPEN_SAVED_V9566__=true;
const rid=new URLSearchParams(location.search).get('requirement_id')||'';
if(!rid||!window.RF853?.rpc)return;
try{
  const k='rr_pi_requirement_v9514';
  const c=JSON.parse(sessionStorage.getItem(k)||'{}');
  if(c&&String(c.requirement_id||'')===rid&&Array.isArray(c.lines)&&c.lines.length){delete c.lines;sessionStorage.setItem(k,JSON.stringify(c));}
}catch(_){}
const base=window.RF853.rpc.bind(window.RF853);
window.RF853.rpc=async function(name,args={}){
  if(name==='rr_pi_requirement_bootstrap_v9541'&&String(args?.p_requirement_id||'')===rid){
    try{
      const saved=await base('rr_pi_requirement_reopen_v9566',{p_requirement_id:rid});
      if(saved?.found&&Array.isArray(saved.lines)&&saved.lines.length)return saved;
    }catch(_){}
  }
  return base(name,args);
};
})();
