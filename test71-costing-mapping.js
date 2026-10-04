/* Shared mapping selection for the canonical Material Master. */
(function(root){
 'use strict';
 function effectiveRows(rows,asOf){
  const scopes=new Map();
  for(const row of rows||[]){
   if(row.is_active===false||!row.effective_from||row.effective_from>asOf)continue;
   const key=[row.material_id,row.consumption_method,String(row.category_code||'').toUpperCase(),String(row.consume_department_code||'').toUpperCase(),!!row.execution_decision].join('|');
   const previous=scopes.get(key);
   const rank=r=>[r.effective_from,r.updated_at||r.created_at||'',r.id||''].join('|');
   if(!previous||rank(row)>rank(previous))scopes.set(key,row);
  }
  return [...scopes.values()].sort((a,b)=>b.effective_from.localeCompare(a.effective_from)||String(b.updated_at||b.created_at||'').localeCompare(String(a.updated_at||a.created_at||''))||String(b.id||'').localeCompare(String(a.id||'')));
 }
 const api={effectiveRows};
 if(typeof module==='object'&&module.exports)module.exports=api;
 else root.RRCostingMapping=api;
})(typeof window==='object'?window:globalThis);
