(() => {
  const ownerName = document.getElementById("ownerName");
  const welcomeText = document.getElementById("welcomeText");
  const logoutBtn = document.getElementById("logoutBtn");
  const refreshBtn = document.getElementById("refreshBtn");
  const message = document.getElementById("dashboardMessage");
  const lotList = document.getElementById("lotList");
  const moduleSearch = document.getElementById("moduleSearch");
  const moduleCount = document.getElementById("moduleCount");

  function setMessage(text, type = "") {
    message.textContent = text || "";
    message.className = `rr-message ${type}`.trim();
  }

  function safeText(value) {
    return String(value ?? "").replace(/[&<>"']/g, (char) => {
      const map = {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;"
      };
      return map[char];
    });
  }

  function filterModules() {
    const query = String(moduleSearch?.value || "").trim().toLowerCase();
    const cards = [...document.querySelectorAll("[data-module]")];
    let visible = 0;
    cards.forEach((card) => {
      const match = !query || card.textContent.toLowerCase().includes(query);
      card.hidden = !match;
      if (match) visible += 1;
    });
    document.querySelectorAll("[data-module-section]").forEach((section) => {
      section.hidden = !section.querySelector("[data-module]:not([hidden])");
    });
    if (moduleCount) {
      moduleCount.textContent = query
        ? `${visible} of ${cards.length} modules`
        : `${cards.length} latest modules`;
    }
  }

  async function requireOwner() {
    const { data, error } = await supabaseClient.auth.getSession();
    if (error || !data.session) {
      window.location.replace("real-login.html");
      throw new Error("Login required.");
    }
    const user = data.session.user;
    const { data: profile, error: profileError } = await supabaseClient
      .from("rr_user_profiles")
      .select("full_name, role_code, is_active")
      .eq("auth_user_id", user.id)
      .single();
    if (profileError || !profile?.is_active || !["owner", "admin"].includes(profile.role_code)) {
      await supabaseClient.auth.signOut();
      window.location.replace("real-login.html");
      throw new Error("Owner/Admin access required.");
    }
    const publicRoleLabel = ["owner", "admin"].includes(profile.role_code)
      ? "SUPER ADMIN"
      : String(profile.role_code || "USER").replaceAll("_", " ").toUpperCase();
    if (ownerName) ownerName.textContent = publicRoleLabel;
    if (welcomeText) welcomeText.textContent = `Welcome, ${publicRoleLabel}`;
  }

  async function countRows(table, filterCallback) {
    let query = supabaseClient.from(table).select("*", { count: "exact", head: true });
    if (typeof filterCallback === "function") query = filterCallback(query);
    const { count, error } = await query;
    if (error) throw error;
    return count || 0;
  }

  async function loadStats() {
    const artPromise = countRows("rr_art_master", (query) => query.eq("is_active", true));
    const lotPromise = countRows("rr_lots", (query) => query.not("status", "in", '("closed","cancelled")'));
    const remakePromise = countRows("rr_remakes", (query) => query.not("status", "in", '("merged","closed","cancelled")'));
    const inventoryPromise = supabaseClient.from("rr_lot_inventory_summary").select("available_pcs");
    const [arts, lots, remakes, inventory] = await Promise.all([artPromise, lotPromise, remakePromise, inventoryPromise]);
    if (inventory.error) throw inventory.error;
    const stock = (inventory.data || []).reduce((sum, row) => sum + Number(row.available_pcs || 0), 0);
    const a=document.getElementById("artCount"),l=document.getElementById("lotCount"),r=document.getElementById("remakeCount"),s=document.getElementById("stockCount");
    if(a)a.textContent=arts;if(l)l.textContent=lots;if(r)r.textContent=remakes;if(s)s.textContent=stock;
  }

  async function loadLots() {
    const { data, error } = await supabaseClient.from("rr_live_lot_status").select("*").order("updated_at", { ascending: false }).limit(12);
    if (error) throw error;
    if (!lotList) return;
    if (!data || data.length === 0) {
      lotList.innerHTML = `<p class="rr-muted">No production lots yet.</p>`;
      return;
    }
    lotList.innerHTML = data.map((lot) => {
      const itemName = lot.item_name || lot.product_name || "";
      const department = lot.current_department || lot.current_department_code || "";
      return `<article class="rr-list-row"><div><strong>${safeText(lot.lot_no)}</strong><span>Art ${safeText(lot.art_no)} · ${safeText(itemName)}</span></div><div class="rr-list-meta"><span>${safeText(department)}</span><b>${safeText(lot.status)}</b></div></article>`;
    }).join("");
  }

  async function refreshDashboard() {
    setMessage("");
    if (refreshBtn) { refreshBtn.disabled = true; refreshBtn.textContent = "Loading..."; }
    try { await Promise.all([loadStats(), loadLots()]); }
    catch (error) { console.error(error); setMessage(error.message || "Dashboard data could not load.", "error"); }
    finally { if (refreshBtn) { refreshBtn.disabled = false; refreshBtn.textContent = "Refresh"; } }
  }

  if (logoutBtn) logoutBtn.addEventListener("click", async () => { await supabaseClient.auth.signOut(); window.location.replace("real-login.html"); });
  if (refreshBtn) refreshBtn.addEventListener("click", refreshDashboard);
  if (moduleSearch) { moduleSearch.addEventListener("input", filterModules); filterModules(); }

  (async () => {
    try { await requireOwner(); await refreshDashboard(); }
    catch (error) { console.error(error); setMessage(error.message || "Access failed.", "error"); }
  })();
})();

/* V9130: Sidebar-only business hierarchy. Main dashboard body remains unchanged. */
(() => {
  'use strict';
  const V='9130';
  const side=document.getElementById('sideList');
  const search=document.getElementById('moduleSearch');
  if(!side)return;

  const style=document.createElement('style');
  style.textContent=`
    .rf-acc{margin:3px 0;border-radius:11px;overflow:hidden}
    .rf-acc-head{width:100%;display:flex;align-items:center;gap:10px;min-height:48px;padding:9px 10px;border:0;background:transparent;color:#f2f5fa;text-align:left;cursor:pointer;border-radius:10px}
    .rf-acc-head:active,.rf-acc.open>.rf-acc-head{background:#1b2230}
    .rf-acc-icon{width:30px;height:30px;display:grid;place-items:center;flex:0 0 30px;border-radius:8px;background:#202735;font-weight:900}
    .rf-acc-title{flex:1;font-weight:900;font-size:14px}
    .rf-acc-arrow{font-size:13px;color:#9aa7b9;transition:transform .15s ease}.rf-acc.open .rf-acc-arrow{transform:rotate(90deg)}
    .rf-acc-body{display:none;padding:3px 4px 7px 30px;margin-left:15px;border-left:1px solid #2d3746}.rf-acc.open .rf-acc-body{display:block}
    .rf-acc-body .rf-side-item{font-size:13px;min-height:39px;padding:7px 9px}.rf-acc-body .rf-icon{width:24px;height:24px;flex-basis:24px;font-size:11px}
    .rf-acc.search-hit .rf-acc-body{display:block}.rf-side-divider{height:1px;background:#252d3a;margin:8px 7px}
  `;
  document.head.appendChild(style);

  const A=(href,icon,label)=>`<a class="rf-side-item" data-module href="${href}"><span class="rf-icon">${icon}</span><span>${label}</span></a>`;
  const group=(id,icon,title,body,open=false)=>`<div class="rf-acc${open?' open':''}" data-acc="${id}"><button class="rf-acc-head" type="button"><span class="rf-acc-icon">${icon}</span><span class="rf-acc-title">${title}</span><span class="rf-acc-arrow">›</span></button><div class="rf-acc-body">${body}</div></div>`;

  side.innerHTML =
    group('product','▣','Product Master',
      A(`real-product-master-v804.html?view=cb_new&v=${V}&cbfix=20260816a`,'CB','CB New')+
      A(`real-product-master-v720.html?view=matching-cloth&v=${V}`,'MC','Matching Cloth')+
      A(`real-art-master.html?v=${V}`,'AR','Art Master')+
      A(`real-print-master.html?v=${V}`,'PR','Print Master')+
      A(`real-product-master-v720.html?view=sticker-master&v=${V}`,'ST','Sticker Master')+
      A(`real-product-master-v720.html?view=metal-id-master&v=${V}`,'ID','Metal ID Master'),true)+
    group('cutting','✂','Cutting Master',
      A(`real-cutting-master.html?view=ready-lot&v=${V}`,'RD','Ready Lot')+
      A(`real-cutting-master.html?view=release-lot&v=${V}`,'RL','Release Lot')+
      A(`real-cutting-master.html?view=all-lot&v=${V}`,'AL','All Lot')+
      A(`real-cutting-master.html?view=filters&v=${V}`,'⌕','Cutting Filters'))+
    group('upm','◉','Universal Product Master',
      A(`real-universal-production-v770-v9059.html?v=${V}`,'UPM','UPM Master · All Departments')+
      A(`real-department-lite-v9127.html?dept=PRINTING&v=${V}`,'PR','Printing')+
      A(`real-department-lite-v9127.html?dept=STICKER&v=${V}`,'ST','Sticker')+
      A(`real-department-lite-v9127.html?dept=METAL_ID&v=${V}`,'ID','Metal ID')+
      A(`real-department-lite-v9127.html?dept=KR&v=${V}`,'KR','Karigar / Stitching')+
      A(`real-department-lite-v9127.html?dept=OV&v=${V}`,'OV','Overlock')+
      A(`real-department-lite-v9127.html?dept=FLD&v=${V}`,'FL','Folding')+
      A(`real-department-lite-v9127.html?dept=KAAJ&v=${V}`,'KJ','Kaaj')+
      A(`real-department-lite-v9127.html?dept=BUTTON&v=${V}`,'BT','Button')+
      A(`real-department-lite-v9127.html?dept=TEAK_TANKI&v=${V}`,'TT','Teak / Tanki')+
      A(`real-department-lite-v9127.html?dept=THREAD_CUT&v=${V}`,'TC','Thread Cut')+
      A(`real-department-lite-v9127.html?dept=QC&v=${V}`,'QC','QC')+
      A(`real-department-lite-v9127.html?dept=PRESS&v=${V}`,'PS','Press')+
      A(`real-department-lite-v9127.html?dept=PACKING&v=${V}`,'PK','Packing'))+
    group('despatch','⇢','Despatch',
      A(`real-department-lite-v9127.html?dept=DESPATCH&v=${V}`,'DP','Despatch Department')+
      A(`real-finished-goods-v787.html?view=despatch&v=${V}`,'DC','Despatch Challan'))+
    group('webstore','▦','Web Store',
      A(`real-finished-goods-v787.html?view=stock&v=${V}`,'WS','Webstore / Store Stock')+
      A(`real-commerce-v849.html?v=${V}`,'MW','Market Window')+
      A(`real-finished-goods-v787.html?view=receive&v=${V}`,'SR','Store Receive'))+
    group('sales','₹','Sales',
      A(`real-finished-goods-v787.html?view=sale&v=${V}`,'PI','Sales · PI / CPI')+
      A(`real-finished-goods-v787.html?view=verify&v=${V}`,'QV','Sales Qty Verify')+
      A(`real-finished-goods-v787.html?view=returns&v=${V}`,'RT','Sales Return'))+
    group('accounts','▤','Accounts',
      A(`real-accounts-suite-v857.html?v=${V}`,'AC','Accounts Suite')+
      A(`real-accounts-costing-v850.html?v=${V}`,'CO','Accounts & Costing')+
      A(`real-reports-ai-v857.html?v=${V}`,'RP','Reports & AI Query'))+
    group('salary','₹','Salary & Workers',
      A(`real-salary-home-v786.html?v=${V}`,'SH','Salary Home')+
      A(`real-salary-payment-v785.html?mode=TEST&v=${V}`,'SP','Salary Payment')+
      A(`real-attendance-salary-v778.html?v=${V}`,'AT','Attendance & Monthly Salary')+
      A(`real-worker-payroll-setup-v786.html?v=${V}`,'WK','Worker Salary Setup'))+
    group('admin','⚙','Admin & Control',
      A(`real-role-permission-v777-4-final.html?v=${V}`,'RP','Roles & Permissions')+
      A(`real-data-mode-control-v786.html?v=${V}`,'DM','Data Mode Control')+
      A(`real-communications-v853.html?v=${V}`,'WA','WhatsApp Messages')+
      A(`real-flow-audit-v857.html?v=${V}`,'FA','Full Flow Audit'));

  side.addEventListener('click',e=>{
    const head=e.target.closest('.rf-acc-head');
    if(!head)return;
    const acc=head.closest('.rf-acc');
    acc.classList.toggle('open');
  });

  const applySearch=()=>{
    const q=String(search?.value||'').trim().toLowerCase();
    side.querySelectorAll('.rf-acc').forEach(acc=>{
      let hit=false;
      acc.querySelectorAll('[data-module]').forEach(a=>{
        const m=!q||a.textContent.toLowerCase().includes(q)||acc.querySelector('.rf-acc-title').textContent.toLowerCase().includes(q);
        a.hidden=!m;
        if(m)hit=true;
      });
      acc.style.display=hit?'':'none';
      acc.classList.toggle('search-hit',!!q&&hit);
    });
  };
  if(search){search.addEventListener('input',applySearch);applySearch();}
})();
