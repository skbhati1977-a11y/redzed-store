(() => {
  const modules = [
    {id:"product",group:"product",title:"Product Master",desc:"CB purchase, Art → Print → Sticker → Metal ID decision, due tabs and accessory requirement mapping.",href:"real-product-master-v804.html?v=804",tag:"V804",status:"ACTIVE"},
    {id:"art",group:"product",title:"Art Master",desc:"Art references, design images and style details.",href:"real-art-master.html?v=786329",tag:"MASTER",status:"ACTIVE"},
    {id:"print",group:"product",title:"Print Master",desc:"Print artwork, frame, colour, placement and garment preview.",href:"real-print-master.html?v=786329",tag:"MASTER",status:"ACTIVE"},
    {id:"cut",group:"product",title:"Cutting & Lots",desc:"Lot release, CB allocation, size/colour cutting and costing.",href:"real-cutting-master.html?v=786329",tag:"FINAL",status:"LOCKED"},

    {id:"upm",group:"production",title:"Universal Production Manager",desc:"Cutting, Printing, Sticker, Metal ID, Stitching, Finishing, Packing, Despatch and Open Random Queue tabs in one inlay.",href:"real-upm-home-v805.html?v=805",tag:"V805 INLAY",status:"ACTIVE"},
    {id:"submitted",group:"production",title:"Submitted Work",desc:"Submitted production, lot/worker/department audit and verification.",href:"real-upm-submitted-work-v772.html?v=805",tag:"V772",status:"ACTIVE"},

    {id:"packing",group:"finished",title:"Packing Dashboard",desc:"Press-ready cards, assign/accept, box algorithm and Submit Packing.",href:"real-finished-goods-v787.html?view=packing&v=789",tag:"PACKING",status:"TEST"},
    {id:"despatch",group:"finished",title:"Despatch Dashboard",desc:"Ready boxes, locked challan and Store travel gate.",href:"real-finished-goods-v787.html?view=despatch&v=789",tag:"DESPATCH",status:"TEST"},
    {id:"receive",group:"finished",title:"Store Receive",desc:"Despatch challan acceptance, box verification and custody receive.",href:"real-finished-goods-v787.html?view=receive&v=789",tag:"STORE",status:"TEST"},
    {id:"stock",group:"finished",title:"Webstore / Store Stock",desc:"Central physical and webstore saleable stock display.",href:"real-finished-goods-v787.html?view=stock&v=789",tag:"STOCK",status:"TEST"},
    {id:"sale",group:"finished",title:"Sales · PI / CPI",desc:"Buyer sale, PI draft and final CPI stock-out.",href:"real-finished-goods-v787.html?view=sale&v=789",tag:"SALES",status:"TEST"},
    {id:"verify",group:"finished",title:"Sales Qty Verify",desc:"Final CPI physical quantity verification gate.",href:"real-finished-goods-v787.html?view=verify&v=789",tag:"VERIFY",status:"TEST"},
    {id:"return",group:"finished",title:"Sales Return",desc:"Known buyer return, anonymous GR and reverse stock entry.",href:"real-finished-goods-v787.html?view=returns&v=789",tag:"RETURN",status:"TEST"},

    {id:"accounts",group:"accounts",title:"Accounts",desc:"Receipt & Payment, Sales & Purchase, Ledgers, Day Book, Suspense and approvals.",href:"real-accounts-v805.html?v=80529",tag:"V805",status:"TEST"},
    {id:"material",group:"accounts",title:"Material Master & Costing",desc:"Units, conversions, estimated consumption, weighted average rate and Material Cost / Good PCS.",href:"real-material-master-v805.html?v=80527",tag:"V805",status:"TEST"},

    {id:"salaryhome",group:"payroll",title:"Salary Home",desc:"PCS and Monthly salary dashboards main control.",href:"real-salary-home-v786.html?v=786329",tag:"V786",status:"ACTIVE"},
    {id:"salarypay",group:"payroll",title:"Salary Payment",desc:"PCS/Monthly manual zero, Flat Ratio and Percent Ratio payment.",href:"real-salary-payment-v785.html?mode=TEST&v=786329",tag:"FINAL",status:"LOCKED"},
    {id:"pcs",group:"payroll",title:"PCS Salary Dashboard",desc:"PCS setup, unpaid work, payment and worker audit.",href:"real-pcs-salary-dashboard-v786.html?v=786329",tag:"PCS",status:"TEST"},
    {id:"monthly",group:"payroll",title:"Monthly Salary Dashboard",desc:"Monthly salaried worker setup, payroll and payment.",href:"real-monthly-salary-dashboard-v786.html?v=786329",tag:"MONTHLY",status:"TEST"},
    {id:"workerpay",group:"payroll",title:"Worker Salary Setup",desc:"Worker payroll category and salary profile setup.",href:"real-worker-payroll-setup-v786.html?v=786329",tag:"SETUP",status:"ACTIVE"},
    {id:"attendance",group:"payroll",title:"Attendance & Monthly Salary",desc:"Attendance, monthly salary calculation and audit.",href:"real-attendance-salary-v778.html?v=786329",tag:"ATTENDANCE",status:"ACTIVE"},
    {id:"pcswork",group:"payroll",title:"PCS Salary Work",desc:"PCS payable work and actual-rate payroll flow.",href:"real-pcs-rate-payroll-v779.html?v=786329",tag:"PCS",status:"ACTIVE"},
    {id:"audit",group:"payroll",title:"Work & Payment Audit",desc:"Work, payment and worker-level audit trail.",href:"real-pcs-work-audit-v783.html?v=786329",tag:"AUDIT",status:"ACTIVE"},
    {id:"advance",group:"payroll",title:"Advance Payment",desc:"Worker advance payment and outstanding handling.",href:"real-advance-worker-payment-v785.html?v=786329",tag:"ADVANCE",status:"ACTIVE"},

    {id:"roles",group:"control",title:"Roles & Permissions",desc:"User, worker, department, action permission and field controls.",href:"real-role-permission-v777-4-final.html?v=786329",tag:"FINAL",status:"LOCKED"},
    {id:"mode",group:"control",title:"Data Mode Control",desc:"Global TEST default, REAL protection and permission-controlled mode.",href:"real-data-mode-control-v786.html?v=786329",tag:"TEST/REAL",status:"TEST"}
  ];

  const coreIds = ["product","upm","packing","sale","accounts","salarypay"];
  const $ = id => document.getElementById(id);

  function card(m){
    const cls = m.status==="TEST" ? "test" : m.status==="LOCKED" ? "locked" : "";
    return `<a class="card" href="${m.href}" data-module-card data-search="${(m.title+" "+m.desc+" "+m.tag).toLowerCase()}">
      <div class="card-top"><span class="tag">${m.tag}</span><span class="status ${cls}">${m.status}</span></div>
      <h3>${m.title}</h3><p>${m.desc}</p><div class="go">Open module →</div>
    </a>`;
  }

  function render(){
    document.querySelectorAll("[data-card-host]").forEach(host=>{
      const group=host.dataset.cardHost;
      const rows=group==="core" ? coreIds.map(id=>modules.find(m=>m.id===id)).filter(Boolean) : modules.filter(m=>m.group===group);
      host.innerHTML=rows.map(card).join("");
    });
  }

  function setView(name){
    document.querySelectorAll(".view").forEach(v=>v.classList.toggle("active",v.id===`view-${name}`));
    document.querySelectorAll("[data-view]").forEach(b=>b.classList.toggle("active",b.dataset.view===name && b.classList.contains("nav-btn")));
    const labels={home:"Flow Setter",product:"Product & Masters",production:"Production / UPM",finished:"Store & Sales",accounts:"Accounts",payroll:"Salary & Attendance",control:"Control Center"};
    $("pageTitle").textContent=labels[name]||"REAL FACTORY";
    $("sidebar").classList.remove("open");
    const u=new URL(location.href);u.searchParams.set("view",name);history.replaceState(null,"",u);
  }

  function search(q){
    q=String(q||"").trim().toLowerCase();
    if(!q){document.querySelectorAll("[data-module-card]").forEach(x=>x.hidden=false);return}
    setView("home");
    const host=document.querySelector('[data-card-host="core"]');
    const rows=modules.filter(m=>(m.title+" "+m.desc+" "+m.tag+" "+m.group).toLowerCase().includes(q));
    host.innerHTML=rows.length?rows.map(card).join(""):`<div class="empty">No matching module found.</div>`;
    document.querySelector(".section-head h2").textContent="Search Results";
    document.querySelector(".module-count").textContent=`${rows.length} found`;
  }

  async function loadUser(){
    try{
      if(!window.RR?.getClient)return;
      const client=RR.getClient();
      const {data:{user}}=await client.auth.getUser();
      if(!user)return;
      const {data}=await client.from("rr_user_profiles").select("full_name,role_code").eq("auth_user_id",user.id).maybeSingle();
      if(data){
        $("ownerName").textContent=data.full_name||user.email||"User";
        $("ownerRole").textContent=RR.friendlyRole?RR.friendlyRole(data.role_code):data.role_code||"User";
        $("avatar").textContent=(data.full_name||"S").trim().charAt(0).toUpperCase();
      }
    }catch(e){ console.warn(e); }
  }

  document.addEventListener("click",e=>{
    const b=e.target.closest("[data-view]");
    if(b){setView(b.dataset.view)}
  });

  $("menuBtn").addEventListener("click",()=> $("sidebar").classList.toggle("open"));
  $("globalSearch").addEventListener("input",e=>search(e.target.value));
  document.addEventListener("keydown",e=>{
    if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==="k"){e.preventDefault();$("globalSearch").focus();$("globalSearch").select()}
    if(e.key==="Escape"){$("sidebar").classList.remove("open");$("globalSearch").blur()}
  });
  $("logoutBtn").addEventListener("click",async()=>{
    try{if(window.RR?.getClient)await RR.getClient().auth.signOut();location.reload()}catch(e){alert(e.message)}
  });

  render();
  loadUser();
  const requested=new URL(location.href).searchParams.get("view");
  if(["home","product","production","finished","accounts","payroll","control"].includes(requested))setView(requested);
})();
