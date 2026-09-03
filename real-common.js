(() => {
  const RR = {};

  RR.safeText = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"})[char]);
  RR.money = (value) => new Intl.NumberFormat("en-IN", {style:"currency",currency:"INR",maximumFractionDigits:2}).format(Number(value || 0));
  RR.number = (value, fallback = 0) => { const parsed=Number(value); return Number.isFinite(parsed)?parsed:fallback; };
  RR.roleCanViewFinancials = (role) => ["owner","admin","account","accounts"].includes(String(role||"").trim().toLowerCase());
  RR.roleCanOperateMasters = (role) => ["owner","admin"].includes(String(role||"").trim().toLowerCase());
  RR.requireRoles = async (allowedRoles=["owner","admin"]) => {const allowed=new Set((allowedRoles||[]).map(role=>String(role||"").trim().toLowerCase()));const {data,error}=await supabaseClient.auth.getSession();if(error||!data.session){window.location.replace("real-login.html");throw new Error("Login required.");}const user=data.session.user;const {data:profile,error:profileError}=await supabaseClient.from("rr_user_profiles").select("id, full_name, role_code, is_active").eq("auth_user_id",user.id).single();const role=String(profile?.role_code||"").trim().toLowerCase();if(profileError||!profile?.is_active||!allowed.has(role))throw new Error(`Required permission: ${[...allowed].join(" / ")}.`);return {session:data.session,user,profile:{...profile,role_code:role}};};
  RR.requireOwner = async()=>{const {data,error}=await supabaseClient.auth.getSession();if(error||!data.session){window.location.replace("real-login.html");throw new Error("Login required.");}const user=data.session.user;const {data:profile,error:profileError}=await supabaseClient.from("rr_user_profiles").select("id, full_name, role_code, is_active").eq("auth_user_id",user.id).single();if(profileError||!profile?.is_active||!["owner","admin"].includes(profile.role_code)){await supabaseClient.auth.signOut();window.location.replace("real-login.html");throw new Error("Owner/Admin access required.");}return {session:data.session,user,profile};};
  RR.getTableColumns=async(table)=>new Set(({rr_art_master:["id","art_no","item_name","product_name","description","default_margin","is_active","created_at"],rr_art_costs:["id","art_id","cutting_rate","printing_rate","sticker_rate","kr_rate","ov_rate","fld_rate","thread_cut_rate","press_rate","packing_rate","other_rate","created_at"],rr_media:["id","entity_type","entity_id","media_category","file_url","storage_path","file_name","mime_type","caption","source_type","visibility_scope","is_cover","sort_order","created_at"]})[table]||[]);
  RR.pickColumn=(columns,aliases)=>aliases.find(name=>columns.has(name))||null;
  RR.filterPayload=(payload,columns)=>Object.fromEntries(Object.entries(payload).filter(([key,value])=>columns.has(key)&&value!==undefined));
  RR.safeFileName=(name)=>String(name||"file").toLowerCase().replace(/[^a-z0-9._-]/g,"_");
  RR.inferMimeType=(file)=>{const declared=String(file?.type||"").trim().toLowerCase();if(declared&&declared!=="application/octet-stream")return declared;const extension=String(file?.name||"").split(".").pop().toLowerCase();return ({jpg:"image/jpeg",jpeg:"image/jpeg",png:"image/png",webp:"image/webp",gif:"image/gif",heic:"image/heic",heif:"image/heif",mp4:"video/mp4",mov:"video/quicktime",webm:"video/webm","3gp":"video/3gpp"})[extension]||"";};
  RR.uploadMedia=async({file,entityType,entityId,mediaCategory="reference",sourceType="gallery",visibilityScope="factory",caption=""})=>{if(!file)return null;const mimeType=RR.inferMimeType(file),path=[entityType,String(entityId),`${Date.now()}-${crypto.randomUUID()}-${RR.safeFileName(file.name)}`].join("/");const {error:uploadError}=await supabaseClient.storage.from("redzed-media").upload(path,file,{cacheControl:"3600",contentType:mimeType||undefined,upsert:false});if(uploadError)throw uploadError;const {data:publicData}=supabaseClient.storage.from("redzed-media").getPublicUrl(path),columns=await RR.getTableColumns("rr_media"),payload=RR.filterPayload({entity_type:entityType,entity_id:String(entityId),media_category:mediaCategory,file_url:publicData.publicUrl,storage_path:path,file_name:file.name,mime_type:mimeType||null,caption,source_type:sourceType,visibility_scope:visibilityScope,is_cover:false,sort_order:0},columns);const {data,error}=await supabaseClient.from("rr_media").insert(payload).select().single();if(error)throw error;return data;};
  RR.getMediaMap=async(entityType,category)=>{let query=supabaseClient.from("rr_media").select("*").eq("entity_type",entityType).order("sort_order",{ascending:true}).order("created_at",{ascending:true});if(category)query=query.eq("media_category",category);const {data,error}=await query;if(error)throw error;return(data||[]).reduce((map,item)=>{const key=String(item.entity_id);if(!map[key])map[key]=[];map[key].push(item);return map;},{});};
  RR.installHassleFreeNumberInputs=()=>{if(document.documentElement.dataset.rrNumberInputsReady==="1")return;document.documentElement.dataset.rrNumberInputsReady="1";document.addEventListener("focusin",event=>{const input=event.target;if(!(input instanceof HTMLInputElement)||input.type!=="number"||input.readOnly||input.disabled||input.dataset.keepNumberFormat==="1")return;const raw=String(input.value||"").trim();if(/^[+-]?0+(?:\.0+)?$/.test(raw)){input.value="";return;}if(raw)requestAnimationFrame(()=>{try{input.select()}catch(_){}});});document.addEventListener("focusout",event=>{const input=event.target;if(!(input instanceof HTMLInputElement)||input.type!=="number"||input.readOnly||input.disabled||input.dataset.keepNumberFormat==="1")return;const raw=String(input.value||"").trim();if(!raw)return;const number=Number(raw);if(Number.isFinite(number))input.value=String(number);});};
  RR.installHassleFreeNumberInputs();window.RR=RR;
})();

/* REAL FACTORY GLOBAL TABLE PLATFORM V775.1 */
(()=>{
  if(window.__REAL_FACTORY_GLOBAL_UI_LOADER_V775__)return;
  window.__REAL_FACTORY_GLOBAL_UI_LOADER_V775__=true;
  const current=document.currentScript?.src||location.href,base=new URL('.',current);
  const load=(file,id)=>new Promise((resolve,reject)=>{if(document.getElementById(id)){resolve();return;}const script=document.createElement('script');script.id=id;script.src=new URL(file,base).href;script.async=false;script.onload=resolve;script.onerror=()=>reject(new Error(`REAL FACTORY global utility failed to load: ${file}`));document.head.appendChild(script);});
  const installPermanentGlobalGuards=()=>{
    if(document.getElementById('rr-global-permanent-ui-guard'))return;
    const style=document.createElement('style');
    style.id='rr-global-permanent-ui-guard';
    style.textContent='.rr-gsheet-toolbar{display:none!important}.rr-gsheet-filter-btn{display:none!important}#rrGsheetBottomScrollV775{display:none!important}.hero>h2,.hero>p:not(.kicker),#tab-matrix .note,[data-rr-directional-comment],.rr-directional-comment{display:none!important}html{scroll-behavior:smooth}.matrix-wrap{-webkit-overflow-scrolling:touch!important;overscroll-behavior:auto!important;scroll-behavior:smooth!important;touch-action:pan-x pan-y!important}.matrix th,.matrix td{box-sizing:border-box!important}.matrix select,.matrix button{box-sizing:border-box!important;max-width:100%!important}';
    document.head.appendChild(style);
  };
  installPermanentGlobalGuards();
  const dataModeLoader=load('real-data-mode-controller-v786-1-1.js?v=884','rr-data-mode-controller-v786-1-1');
  window.RRDataModeLoaderPromise=dataModeLoader;
  dataModeLoader.then(()=>load('real-mobile-compat-v775.js?v=884','rr-mobile-compat-v775')).then(()=>load('real-google-sheet-table-v775.js?v=9324','rr-google-sheet-table-v775')).then(installPermanentGlobalGuards).catch(error=>console.error(error));
})();

/* TEST65: approved TEST64 Role Permission behavior on current MAIN */
(()=>{
  if(!/real-role-permission-v776-4\.html$/i.test(location.pathname))return;
  const style=document.createElement('style');
  style.id='rr-test65-v7764-approved-cleanup';
  style.textContent='.hero>h2{display:none!important}#matrixRefresh{display:none!important}#tab-matrix .note{display:none!important}.matrix th,.matrix td{box-sizing:border-box!important;overflow:hidden!important}.matrix th *,.matrix td *{box-sizing:border-box!important;max-width:100%!important}.matrix .field-cell strong,.matrix .field-cell small{display:block!important;max-width:100%!important;white-space:normal!important;overflow:hidden!important}.matrix select,.matrix button,.matrix input{max-width:100%!important;min-width:0!important}.matrix-wrap{overflow:auto!important;overflow-x:auto!important;overflow-y:auto!important;-webkit-overflow-scrolling:touch!important;overscroll-behavior:auto!important;touch-action:pan-x pan-y!important;scroll-behavior:smooth!important}';
  document.head.appendChild(style);
  const hideInactiveButtonQuantity=()=>{
    const body=document.querySelector('#tab-matrix .matrix tbody');
    if(!body)return;
    let hide=false;
    [...body.children].forEach(row=>{
      if(row.classList.contains('group')){
        const label=(row.textContent||'').trim().replace(/\s+/g,' ').toUpperCase();
        hide=label==='BUTTON · QUANTITY';
      }
      if(hide)row.style.display='none';
    });
  };
  const observer=new MutationObserver(hideInactiveButtonQuantity);
  observer.observe(document.documentElement,{childList:true,subtree:true});
  hideInactiveButtonQuantity();
})();
