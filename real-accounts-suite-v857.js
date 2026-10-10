// Retired generic report fallbacks. Keep existing links on the canonical Accounts reports.
(()=>{
  'use strict';
  const source=new URLSearchParams(location.search),target=new URL('real-accounts-v805.html',location.href);
  target.searchParams.set('tab','ledgers');
  for(const key of ['ledger_id','category','from'])if(source.has(key))target.searchParams.set(key,source.get(key));
  location.replace(target.pathname+target.search);
})();
