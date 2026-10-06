(() => {
 'use strict';
 const q=new URLSearchParams(location.search);
 if(q.get('share_mode')!=='chooser'||q.get('from_chat')==='1'||q.get('rr_partner_mode'))return;
 const shared=window.RRMarketCustomer71;
 const explicit=q.getAll('recipient_chat').filter(Boolean);
 const recipients=[...new Set(explicit.length?explicit:(q.get('outside')==='1'?[]:shared?.get()||[]))];
 if(recipients.length)shared?.set(recipients);
 const outside=q.get('outside')==='1';
 const base=RF853.rpc.bind(RF853);
 window.RRMarketRecipientFirst71={recipients,outside,choose(ids){shared?.set(ids);const url=new URL(location.href);url.searchParams.delete('recipient_chat');url.searchParams.delete('outside');ids.forEach(id=>url.searchParams.append('recipient_chat',id));location.href=url.href;},chooseOutside(){shared?.clear();const url=new URL(location.href);url.searchParams.delete('recipient_chat');url.searchParams.set('outside','1');location.href=url.href;},change(){shared?.clear();const url=new URL(location.href);url.searchParams.delete('recipient_chat');url.searchParams.delete('outside');url.searchParams.delete('selected_lot');location.href=url.href;}};
 if(outside)return;
 const mode=document.getElementById('dataMode');if(mode){mode.value='TEST';mode.disabled=true;}
 RF853.rpc=async(name,args={})=>{
  if(name!=='rr_web_window_cards_v9329')return base(name,args);
  if(!recipients.length)return [];
  const union=new Map();
  for(const chat of recipients){let offset=0;for(;;){const page=await base('rr_sales_collection_cards_test71',{p_chat_id:chat,p_search:args.p_search||null,p_category:args.p_category||null,p_stock_status:args.p_stock_status||null,p_limit:150,p_offset:offset});const sent=new Set((page.context?.sent_lots||[]).map(l=>String(l).trim().toUpperCase()));for(const row of page.rows||[]){const lot=String(row.lot_no).trim().toUpperCase();if(!sent.has(lot))union.set(lot,row);}if((page.rows||[]).length<150)break;offset+=150;}}
  return [...union.values()].slice(Math.max(0,args.p_offset||0),Math.max(0,args.p_offset||0)+Math.min(150,args.p_limit||150));
 };
})();
