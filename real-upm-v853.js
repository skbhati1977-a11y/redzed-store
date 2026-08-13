(() => {
  const tabs = [
    {key:"CUTTING", label:"Cutting", url:"real-cutting-master.html?v=805"},
    {key:"PRINTING", label:"Printing", url:"real-universal-production-v770.html?dept=PRINTING&label=Printing&v=805"},
    {key:"STICKER", label:"Sticker", url:"real-universal-production-v770.html?dept=STICKER&label=Sticker&v=805"},
    {key:"METAL_ID", label:"Metal ID", url:"real-universal-production-v770.html?dept=METAL_ID&label=Metal+ID&v=805"},
    {key:"KR", label:"Karigar / Stitching", url:"real-universal-production-v770.html?dept=KR&label=Karigar&v=805"},
    {key:"OVERLOCK", label:"Overlock", url:"real-universal-production-v770.html?dept=OVERLOCK&label=Overlock&v=805"},
    {key:"FOLDING", label:"Folding", url:"real-universal-production-v770.html?dept=FOLDING&label=Folding&v=805"},
    {key:"KAAJ_BUTTON", label:"Kaaj / Button", url:"real-universal-production-v770.html?dept=KAAJ_BUTTON&label=Kaaj+Button&v=805"},
    {key:"TEAK_TANKI", label:"Teak / Tanki", url:"real-universal-production-v770.html?dept=TEAK_TANKI&label=Teak+Tanki&v=805"},
    {key:"THREAD_CUT", label:"Thread Cutting", url:"real-universal-production-v770.html?dept=THREAD_CUT&label=Thread+Cutting&v=805"},
    {key:"QC", label:"QC", url:"real-universal-production-v770.html?dept=QC&label=QC&v=805"},
    {key:"PRESS", label:"Press", url:"real-universal-production-v770.html?dept=PRESS&label=Press&v=805"},
    {key:"PACKING", label:"Packing", kind:"finish", url:"real-finished-goods-v787.html?view=packing&v=805"},
    {key:"DESPATCH", label:"Despatch", kind:"finish", url:"real-finished-goods-v787.html?view=despatch&v=805"},
    {key:"SUBMITTED", label:"Submitted Work", kind:"finish", url:"real-upm-submitted-work-v772.html?v=805"},
    {key:"CONTROL", label:"All / Open Random Queue", kind:"finish", url:"real-universal-production-v770.html?v=805"}
  ];

  const $ = id => document.getElementById(id);
  const frame = $("upmFrame");
  const holder = $("upmTabs");
  const loading = $("loadingBadge");
  const current = $("currentView");
  const direct = $("openDirect");

  function selectTab(tab, push=true) {
    document.querySelectorAll(".upm-tab").forEach(b => b.classList.toggle("active", b.dataset.key === tab.key));
    loading.hidden = false;
    current.textContent = tab.label;
    direct.href = tab.url;
    frame.src = tab.url;
    if (push) {
      const u = new URL(location.href);
      u.searchParams.set("tab", tab.key);
      history.replaceState(null, "", u);
    }
  }

  tabs.forEach(tab => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "upm-tab";
    if (tab.kind) b.dataset.kind = tab.kind;
    b.dataset.key = tab.key;
    b.textContent = tab.label;
    b.addEventListener("click", () => selectTab(tab));
    holder.appendChild(b);
  });

  frame.addEventListener("load", () => { loading.hidden = true; });
  $("reloadTab").addEventListener("click", () => {
    loading.hidden = false;
    try { frame.contentWindow.location.reload(); }
    catch { frame.src = frame.src; }
  });

  const requested = new URL(location.href).searchParams.get("tab");
  selectTab(tabs.find(t => t.key === requested) || tabs.find(t => t.key === "CONTROL") || tabs[0], false);
})();
