(()=>{
 'use strict';
 const modules=new Set('CUSTOMERS SUPPLIERS WORKERS ART PRODUCTS LEDGERS OPENING_GL OPENING_STOCK OPENING_WIP CB MC1 MATERIAL ACCESSORIES CUTTING FABRICATION PRINTING STICKER METAL_ID STITCHING OVERLOCK FOLDING KAAJ_BUTTON TEAK_TANKI THREAD_CUT QC PRESS PACKING DISPATCH SALES RETURNS RCI COMMITTEE ATTENDANCE PAYROLL ADVANCE CLAIM PAYMENT RECEIPT'.split(' '));
 const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
 const decimal=value=>{
  if(typeof value!=='string'&&typeof value!=='number')return null;
  if(typeof value==='number'&&(!Number.isFinite(value)||Math.abs(value)>Number.MAX_SAFE_INTEGER))return null;
  const text=String(value).trim();if(!/^\d+(?:\.\d+)?$/.test(text))return null;
  const [whole,fraction='']=text.split('.');return {amount:BigInt(whole+fraction),scale:fraction.length};
 };
 function csv(text){
  const records=[];let row=[],field='',quoted=false,closed=false;
  text=String(text).replace(/^\uFEFF/,'');
  for(let i=0;i<text.length;i++){
   const c=text[i];
   if(quoted){if(c==='"'){if(text[i+1]==='"'){field+='"';i++;}else{quoted=false;closed=true;}}else field+=c;continue;}
   if(c==='"'){if(field||closed)throw Error('Invalid CSV quote at character '+i);quoted=true;continue;}
   if(c===','||c==='\n'||c==='\r'){row.push(field);field='';closed=false;if(c!==','){if(c==='\r'&&text[i+1]==='\n')i++;if(row.some(value=>value!==''))records.push(row);row=[];}continue;}
   if(closed)throw Error('Unexpected text after a quoted CSV field.');field+=c;
  }
  if(quoted)throw Error('Unclosed CSV quote.');
  row.push(field);if(row.some(value=>value!==''))records.push(row);
  if(records.length<2)throw Error('CSV header and at least one data row required.');
  const headers=records.shift().map(value=>value.trim());
  if(headers.some(value=>!value)||new Set(headers).size!==headers.length)throw Error('CSV headers must be unique and nonempty.');
  for(const key of ['module','source_key','record_date','evidence_status','values_json','references_json'])if(!headers.includes(key))throw Error('Missing CSV column: '+key);
  return records.map((values,index)=>{
   if(values.length!==headers.length)throw Error('CSV row '+(index+2)+' has a different column count.');
   const original=Object.fromEntries(headers.map((key,i)=>[key,values[i]]));
   let data,refs;try{data=JSON.parse(original.values_json);refs=JSON.parse(original.references_json);}catch(_){throw Error('CSV row '+(index+2)+' has invalid values_json or references_json.');}
   return {module:original.module,source_key:original.source_key,record_date:original.record_date,evidence_status:original.evidence_status,values:data,references:refs,original_csv:original};
  });
 }
 function inspect(input){
  if(!Array.isArray(input)||input.length<1||input.length>10000)throw Error('Provide 1–10000 source rows.');
  const findings=[],keys=new Map(),dates=[],opening=[];
  const rows=input.map((raw,index)=>{
   const n=index+1,add=(code,detail)=>findings.push({row_no:n,code,detail});
   if(!object(raw)){add('ROW_CONTRACT','Source row must be an object.');return raw;}
   const row={...raw,original_source:raw,module:String(raw.module??'').trim().toUpperCase(),source_key:String(raw.source_key??'').trim(),evidence_status:String(raw.evidence_status??'').trim().toUpperCase()};
   if(!modules.has(row.module))add('MODULE_MAPPING','Unknown source module.');
   if(!row.source_key)add('SOURCE_KEY','Stable original source key required.');
   const key=row.module+'|'+row.source_key;if(keys.has(key))add('DUPLICATE_SOURCE_KEY','Duplicate module/source key.');keys.set(key,(keys.get(key)||0)+1);
   const date=String(row.record_date??'');const parsed=new Date(date+'T00:00:00Z');
   if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||Number.isNaN(parsed.valueOf())||parsed.toISOString().slice(0,10)!==date)add('RECORD_DATE','Valid ISO source date required; no default cutoff.');else dates.push(date);
   if(!object(row.values)||!Array.isArray(row.references))add('ROW_CONTRACT','Values object and references array required.');
   if(!['KNOWN','ZERO','UNKNOWN','NOT_APPLICABLE'].includes(row.evidence_status))add('EVIDENCE_STATUS','Explicit evidence status required.');
   if(row.evidence_status==='UNKNOWN')add('UNKNOWN_EVIDENCE','Unknown source values cannot be posted as zero.');
   if(row.evidence_status==='NOT_APPLICABLE'&&!String(row.values?.reason??'').trim())add('NA_REASON','Source reason required.');
   if(['KNOWN','ZERO'].includes(row.evidence_status)&&row.module==='OPENING_GL'){
    const debit=decimal(row.values?.debit),credit=decimal(row.values?.credit);
    if(!String(row.values?.ledger_key??'').trim()||!debit||!credit||(debit.amount>0n&&credit.amount>0n)||(row.evidence_status==='ZERO'&&(debit.amount!==0n||credit.amount!==0n)))add('OPENING_GL_VALUES','Opening requires ledger key and explicit nonnegative debit/credit; ZERO requires exact zeros.');
    else opening.push({debit,credit});
   }
   if(['KNOWN','ZERO'].includes(row.evidence_status)&&['OPENING_STOCK','OPENING_WIP'].includes(row.module)){
    const quantity=decimal(row.values?.quantity),value=decimal(row.values?.value);
    if(!String(row.values?.item_key??'').trim()||!String(row.values?.unit??'').trim()||!quantity||!value||(row.evidence_status==='ZERO'&&(quantity.amount!==0n||value.amount!==0n)))add('OPENING_STOCK_VALUES','Stock/WIP requires item key, unit and explicit nonnegative quantity/value; ZERO requires exact zeros.');
   }
   return row;
  });
  rows.forEach((row,index)=>{for(const ref of Array.isArray(row?.references)?row.references:[]){if(!object(ref)||keys.get(String(ref.module??'').toUpperCase()+'|'+String(ref.source_key??''))!==1)findings.push({row_no:index+1,code:'UNRESOLVED_SOURCE_REFERENCE',detail:'Reference must resolve uniquely to supplied source rows.'});}});
  if(opening.length&&!findings.some(f=>['OPENING_GL_VALUES','ROW_CONTRACT','UNKNOWN_EVIDENCE'].includes(f.code))){
   const scale=Math.max(...opening.flatMap(row=>[row.debit.scale,row.credit.scale]));
   const total=side=>opening.reduce((sum,row)=>sum+row[side].amount*10n**BigInt(scale-row[side].scale),0n);
   if(total('debit')!==total('credit'))findings.push({row_no:null,code:'OPENING_GL_UNBALANCED',detail:'Supplied opening debit and credit totals differ.'});
  }
  dates.sort();return {rows,row_count:rows.length,earliest_source_date:dates[0]||null,latest_source_date:dates.at(-1)||null,findings,cleared_for_import:false,business_records_posted:0};
 }
 window.RRSourceIntake71={csv,inspect};
})();
