(()=>{
  'use strict';
  if(window.__RR_DIRECT_CUSTOMER_SINGLE_CARD_V9684__)return;
  window.__RR_DIRECT_CUSTOMER_SINGLE_CARD_V9684__=true;
  const requirementId=new URLSearchParams(location.search).get('r')||null;
  let attempts=0;
  const timer=setInterval(()=>{
    if(!window.RF853||typeof RF853.rpc!=='function'){
      if(++attempts>60)clearInterval(timer);
      return;
    }
    if(RF853.__rrDirectSingleCard9684){clearInterval(timer);return;}
    const base=RF853.rpc.bind(RF853);
    RF853.rpc=(name,args={})=>name==='rr_collection_submit_requirement_v9588'
      ?base('rr_direct_collection_submit_requirement_v9684',{
        ...args,p_requirement_id:requirementId||args.p_requirement_id||null
      })
      :base(name,args);
    RF853.__rrDirectSingleCard9684=true;
    clearInterval(timer);
  },50);
})();
