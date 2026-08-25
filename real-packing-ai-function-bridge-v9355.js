(()=>{
  'use strict';
  if(window.__RR_PACKING_AI_FUNCTION_BRIDGE_V9355__)return;
  window.__RR_PACKING_AI_FUNCTION_BRIDGE_V9355__=true;
  const FN='rr-ai-garment-images-v9330';
  const getClient=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
  const connectMsg='AI service connect nahi ho pa raha. Internet/Supabase Function status check karke retry karein.';
  function patch(){
    const c=getClient();
    if(!c?.functions?.invoke||c.__rrAiFunctionBridge9355)return false;
    const original=c.functions.invoke.bind(c.functions);
    c.functions.invoke=async function(name,options){
      if(name!==FN)return original(name,options);
      try{
        return await invokeDirect(c,options&&options.body);
      }catch(error){
        console.warn('Packing AI direct bridge failed',error);
        try{return await original(name,options)}catch(e){return {data:null,error:e||error}}
      }
    };
    c.__rrAiFunctionBridge9355=true;
    return true;
  }
  async function invokeDirect(c,body){
    const auth=await c.auth.getSession();
    const token=auth?.data?.session?.access_token;
    if(!token)throw Error('Login session required');
    const base=(typeof SUPABASE_URL!=='undefined'&&SUPABASE_URL)||c.supabaseUrl;
    const key=(typeof SUPABASE_ANON_KEY!=='undefined'&&SUPABASE_ANON_KEY)||c.supabaseKey;
    if(!base||!key)throw Error('Supabase config missing');
    const ctl=new AbortController();
    const timer=setTimeout(()=>ctl.abort(),120000);
    try{
      const res=await fetch(base.replace(/\/$/,'')+'/functions/v1/'+FN,{
        method:'POST',
        headers:{'Content-Type':'application/json','apikey':key,'Authorization':'Bearer '+token},
        body:JSON.stringify(body||{}),
        signal:ctl.signal,
        cache:'no-store'
      });
      const raw=await res.text();
      let data=null;
      try{data=raw?JSON.parse(raw):null}catch(_){data={ok:false,error:raw}}
      if(!res.ok)return {data,error:new Error(data?.error||data?.message||connectMsg)};
      return {data,error:null};
    }catch(e){
      if(String(e?.name||'')==='AbortError')return {data:null,error:new Error('AI service timeout. Retry karein.')};
      return {data:null,error:new Error(e?.message||connectMsg)};
    }finally{clearTimeout(timer)}
  }
  [0,200,800,1600,3000].forEach(ms=>setTimeout(patch,ms));
  document.addEventListener('click',()=>setTimeout(patch,50),true);
})();