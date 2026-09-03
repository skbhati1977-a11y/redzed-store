(()=>{
  'use strict';
  if(window.__RR_MARKET_TEST67_SEQUENCE__)return;
  window.__RR_MARKET_TEST67_SEQUENCE__=1;
  let wired=false;
  function wire(){
    if(wired||!window.RF853||typeof RF853.rpc!=='function')return false;
    const base=RF853.rpc.bind(RF853);
    RF853.rpc=(name,args={})=>{
      const mode=String(typeof RF853.mode==='function'?RF853.mode():'').toUpperCase();
      if(mode==='TEST'&&name==='rr_market_create_share_v9420'&&args.p_customer_id){
        return base('rr_collection_create_first_v67',{
          p_customer_id:args.p_customer_id,
          p_lots:args.p_lots,
          p_data_mode:'TEST'
        });
      }
      if(mode==='TEST'&&name==='rr_collection_submit_requirement_v9588'){
        return base('rr_collection_submit_requirement_v67',args);
      }
      return base(name,args);
    };
    wired=true;
    return true;
  }
  let tries=0;
  const timer=setInterval(()=>{if(wire()||++tries>=40)clearInterval(timer)},100);
  if(document.readyState!=='loading')wire();
})();
