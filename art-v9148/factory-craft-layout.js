(() => {
  'use strict';

  if (!/\/art-v9148\/?$/i.test(window.location.pathname)) return;

  const STYLE_ID = 'artFactoryCraftLayoutV9148';
  const GROUPS = [
    { label: 'Collar', keys: ['collar'] },
    { label: 'Neck', keys: ['neck'] },
    { label: 'Sleeve', keys: ['sleeve', 'cuff'] },
    { label: 'Placket', keys: ['placket'] },
    { label: 'Panels', keys: ['panel', 'shoulder', 'pocket', 'waist', 'bottom', 'fit', 'construction'] },
    { label: 'Stitch / Finish', keys: ['stitch', 'finish'] }
  ];

  function installStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      #artCaptionBuilder .rr-caption-selected{margin-bottom:12px!important}
      #artCaptionBuilder .rr-caption-groups{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:12px!important}
      #artCaptionBuilder .rr-caption-group{display:block!important;min-width:0!important;border:1px solid #dfe3e8!important;border-radius:16px!important;background:#fff!important;padding:13px!important}
      #artCaptionBuilder .rr-caption-group h4{margin:0 0 10px!important;color:#101828!important;font-size:14px!important;font-weight:900!important}
      #artCaptionBuilder .rr-caption-options{display:flex!important;flex-wrap:wrap!important;gap:8px!important}
      #artCaptionBuilder .rr-caption-pill{display:inline-flex!important;align-items:center!important;justify-content:center!important;min-height:44px!important;padding:9px 13px!important;border:1px solid #cfd4dc!important;border-radius:999px!important;background:#fff!important;color:#344054!important;font-size:13px!important;font-weight:750!important;box-shadow:none!important;transition:background .15s ease,border-color .15s ease,color .15s ease,transform .08s ease!important}
      #artCaptionBuilder .rr-caption-pill:active{transform:scale(.98)!important}
      #artCaptionBuilder .rr-caption-pill.selected{background:#111!important;border-color:#111!important;color:#fff!important;font-weight:900!important;box-shadow:0 3px 10px rgba(0,0,0,.14)!important}
      #artCaptionBuilder .rr-caption-pill.selected::before{content:'✓';margin-right:5px;font-weight:900}
      #artCaptionBuilder .rr-caption-preview{display:none!important}
      #artCaptionBuilder .rr-caption-chosen{min-height:0!important;margin:0!important}
      #artCaptionBuilder .rr-caption-chosen:has(.rr-caption-empty){display:none!important}
      #artCaptionBuilder .rr-caption-empty{display:none!important}
      .art-material-professional{margin-top:12px!important;padding:13px!important}
      .art-material-professional .art-material-title{margin-bottom:8px!important}
      .art-material-professional .art-material-guide{display:none!important}
      #artMaterialRequirements{display:flex!important;flex-wrap:wrap!important;gap:7px!important;min-height:44px!important;padding:7px!important;margin-top:0!important;border:1px dashed #cfd5dd!important;border-radius:13px!important;background:#fafbfc!important}
      #artMaterialRequirements .art-material-chip{min-height:34px!important;padding:6px 9px!important;border-radius:999px!important;font-size:11px!important}
      @media(max-width:700px){
        #artCaptionBuilder .rr-caption-groups{grid-template-columns:1fr!important}
        #artCaptionBuilder .rr-caption-group{padding:12px!important}
        #artCaptionBuilder .rr-caption-pill{min-height:46px!important;flex:1 1 calc(50% - 8px)!important;white-space:normal!important;text-align:center!important}
      }
    `;
    document.head.appendChild(style);
  }

  function normalize(text) {
    return String(text || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '_');
  }

  function regroup() {
    const builder = document.getElementById('artCaptionBuilder');
    const grid = builder?.querySelector('.rr-caption-groups');
    if (!grid || grid.dataset.factoryGrouped === '1') return;

    const original = [...grid.querySelectorAll(':scope > .rr-caption-group')];
    if (!original.length) return;

    const buckets = GROUPS.map(group => ({ ...group, options: [] }));
    const advanced = [];

    for (const section of original) {
      const heading = normalize(section.querySelector('h4')?.textContent);
      const buttons = [...section.querySelectorAll('.rr-caption-pill')];
      const bucket = buckets.find(group => group.keys.some(key => heading.includes(key)));
      if (bucket) bucket.options.push(...buttons);
      else advanced.push(section);
    }

    grid.innerHTML = '';
    for (const bucket of buckets) {
      const section = document.createElement('section');
      section.className = 'rr-caption-group art-factory-primary-group';
      const h4 = document.createElement('h4');
      h4.textContent = bucket.label;
      const options = document.createElement('div');
      options.className = 'rr-caption-options';
      if (bucket.options.length) bucket.options.forEach(btn => options.appendChild(btn));
      else {
        const empty = document.createElement('span');
        empty.className = 'rr-caption-empty';
        empty.textContent = 'No options yet';
        options.appendChild(empty);
      }
      section.append(h4, options);
      grid.appendChild(section);
    }

    const more = document.getElementById('moreFeaturesContent');
    if (more) {
      more.replaceChildren(...advanced);
      document.getElementById('moreFeaturesBtn')?.toggleAttribute('hidden', advanced.length === 0);
    }

    grid.dataset.factoryGrouped = '1';
  }

  function observe() {
    installStyles();
    const builder = document.getElementById('artCaptionBuilder');
    if (!builder) return;
    const run = () => requestAnimationFrame(regroup);
    new MutationObserver(() => {
      const grid = builder.querySelector('.rr-caption-groups');
      if (grid && grid.dataset.factoryGrouped !== '1') run();
    }).observe(builder, { childList: true, subtree: true });
    run();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', observe);
  else observe();
})();