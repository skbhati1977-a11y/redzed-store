(() => {
  'use strict';

  const frame = document.getElementById('upmFrame');
  if (!frame) return;

  let activeFilter = 'ALL';
  let refreshTimer = null;
  let observer = null;
  let lastDept = null;
  let lastPayload = null;

  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const upper = v => String(v || '').trim().toUpperCase();
  const num = v => Number(v || 0);

  function canonicalDept(v) {
    const x = upper(v).replace(/[^A-Z0-9]+/g, '');
    const m = {
      KR:'STITCHING', KARIGAR:'STITCHING', STITCH:'STITCHING', STITCHING:'STITCHING',
      OV:'OVERLOCK', OVERLOCKING:'OVERLOCK', OVERLOCK:'OVERLOCK',
      FLD:'FOLDING', FOLD:'FOLDING', FLATLOCK:'FOLDING', FOLDING:'FOLDING',
      KAJ:'KAAJ', KAAJ:'KAAJ', BTN:'BUTTON', BUTTON:'BUTTON', KAAJBUTTON:'KAAJ_BUTTON',
      TEAK:'TEAK_TANKI', TANKI:'TEAK_TANKI', TEAKTANKI:'TEAK_TANKI', TANKITACK:'TEAK_TANKI',
      THCUT:'THREAD_CUT', THREADCUT:'THREAD_CUT', THREADCUTTING:'THREAD_CUT',
      CHECK:'QC', CHECKING:'QC', QUALITYCHECK:'QC', QC:'QC',
      PRESSFINISHING:'PRESS', FINISHING:'PRESS', PRESS:'PRESS',
      PACK:'PACKING', PACKING:'PACKING', DISPATCH:'DESPATCH', DESPATCH:'DESPATCH',
      PRINT:'PRINTING', PRINTER:'PRINTING', PRINTING:'PRINTING',
      ID:'METAL_ID', METAL:'METAL_ID', METALID:'METAL_ID', STICKER:'STICKER', CUT:'CUTTING', CUTTING:'CUTTING'
    };
    return m[x] || upper(v) || null;
  }

  function getContext() {
    try {
      const w = frame.contentWindow;
      const d = frame.contentDocument;
      if (!w || !d) return null;
      const url = new URL(w.location.href);
      const fixed = url.searchParams.get('dept');
      const selected = d.getElementById('homeDept')?.value || d.getElementById('dept')?.value;
      const dept = canonicalDept(fixed || selected || '');
      const sb = w.supabaseClient || w.redzedSupabase || w.sb || window.supabaseClient || window.redzedSupabase || window.sb;
      return {w,d,dept,sb};
    } catch {
      return null;
    }
  }

  function ensureStyle(d) {
    if (d.getElementById('rr-v9092-style')) return;
    const s = d.createElement('style');
    s.id = 'rr-v9092-style';
    s.textContent = `
      .rr-v9092-filterbar{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0;padding:9px;border:1px solid #303641;border-radius:12px;background:#10151d;position:sticky;top:0;z-index:7}
      .rr-v9092-filter{border:1px solid #485364;background:#1b222d;color:#fff;border-radius:999px;padding:8px 11px;font-weight:900;cursor:pointer}
      .rr-v9092-filter.active{background:#6b1f2b;border-color:#d64559}.rr-v9092-filter.assign{border-color:#c8992d}.rr-v9092-filter.submit{border-color:#318b65}.rr-v9092-filter.alter{border-color:#9b7a16}
      .rr-v9092-cardhead{display:grid;gap:5px;margin:8px 0 5px;padding:7px;border:1px solid #343b47;border-radius:9px;background:#0d1118}
      .rr-v9092-due{display:flex;gap:6px;flex-wrap:wrap}.rr-v9092-pill{display:inline-flex;gap:5px;align-items:center;border:1px solid #485364;border-radius:999px;padding:4px 7px;font-size:10px;font-weight:900}
      .rr-v9092-pill.assign{border-color:#c8992d;color:#ffd66f}.rr-v9092-pill.submit{border-color:#318b65;color:#83f0bd}.rr-v9092-pill.alter{border-color:#9b7a16;color:#ffe067}
      .rr-v9092-alterline{display:flex;gap:6px;flex-wrap:wrap;align-items:center;border-top:1px solid #ffffff18;padding-top:5px;font-size:10px;font-weight:800}
      .rr-v9092-owner{color:#fff;font-weight:950}.rr-v9092-stage{color:#9ec5ff}.rr-v9092-hidden{display:none!important}
      @media(max-width:520px){.rr-v9092-filterbar{gap:5px}.rr-v9092-filter{padding:7px 8px;font-size:11px}}
    `;
    d.head.appendChild(s);
  }

  function lotMap(payload) {
    return new Map((payload?.lots || []).map(x => [upper(x.lot_no), x]));
  }

  function renderFilterBar(ctx, payload) {
    const {d,dept} = ctx;
    let bar = d.getElementById('rr-v9092-filterbar');
    if (!bar) {
      bar = d.createElement('div');
      bar.id = 'rr-v9092-filterbar';
      bar.className = 'rr-v9092-filterbar';
      const board = d.getElementById('board');
      if (board?.parentNode) board.parentNode.insertBefore(bar, board);
    }
    const t = payload?.totals || {};
    bar.innerHTML = `
      <button type="button" class="rr-v9092-filter ${activeFilter==='ALL'?'active':''}" data-v9092-filter="ALL">ALL</button>
      <button type="button" class="rr-v9092-filter assign ${activeFilter==='ASSIGN'?'active':''}" data-v9092-filter="ASSIGN">ASSIGN DUE · ${num(t.assign_due_count)}</button>
      <button type="button" class="rr-v9092-filter submit ${activeFilter==='SUBMIT'?'active':''}" data-v9092-filter="SUBMIT">SUBMIT DUE · ${num(t.submit_due_count)}</button>
      <button type="button" class="rr-v9092-filter alter ${activeFilter==='ALTER'?'active':''}" data-v9092-filter="ALTER">ALTER ACTIVE · ${num(t.active_alter_count)}</button>
      <span style="margin-left:auto;align-self:center;font-size:11px;color:#98a2b3;font-weight:800">${esc(dept || 'ALL DEPARTMENTS')}</span>`;
    bar.querySelectorAll('[data-v9092-filter]').forEach(b => {
      b.onclick = e => {
        e.preventDefault(); e.stopPropagation();
        activeFilter = b.dataset.v9092Filter;
        renderFilterBar(ctx, lastPayload || payload);
        decorateCards(ctx, lastPayload || payload);
      };
    });
  }

  function alterLine(j) {
    const owner = j.owner_name || 'OWNER PENDING';
    const role = String(j.owner_role || '').replaceAll('_',' ');
    const ownerDept = j.owner_department_code ? ` · ${j.owner_department_code}` : '';
    return `<div class="rr-v9092-alterline">
      <span class="rr-v9092-pill alter">${esc(j.journey_code || 'ALTER')}</span>
      <span>${esc(j.colour_code || '')} ${esc(j.size_code || '')} · ${num(j.qty)} PCS</span>
      <span class="rr-v9092-owner">OWNER: ${esc(owner)}${role ? ` [${esc(role)}]` : ''}${esc(ownerDept)}</span>
      <span class="rr-v9092-stage">${esc(j.stage || '')}</span>
    </div>`;
  }

  function decorateCards(ctx, payload) {
    const {d} = ctx;
    const byLot = lotMap(payload);
    [...d.querySelectorAll('.lot-card')].forEach(card => {
      const lotNo = upper(card.querySelector('.lot-no')?.textContent);
      const row = byLot.get(lotNo) || {assign_due_count:0,submit_due_count:0,active_alter_count:0,alter_journeys:[]};
      card.querySelector('.rr-v9092-cardhead')?.remove();
      const head = d.createElement('div');
      head.className = 'rr-v9092-cardhead';
      head.innerHTML = `<div class="rr-v9092-due">
        <span class="rr-v9092-pill assign">ASSIGN DUE ${num(row.assign_due_count)}</span>
        <span class="rr-v9092-pill submit">SUBMIT DUE ${num(row.submit_due_count)}</span>
        ${num(row.active_alter_count) ? `<span class="rr-v9092-pill alter">ALTER ${num(row.active_alter_count)} · ${num(row.active_alter_qty)} PCS</span>` : ''}
      </div>${(row.alter_journeys || []).map(alterLine).join('')}`;
      card.querySelector('.lot-head')?.insertAdjacentElement('afterend', head);

      let show = true;
      if (activeFilter === 'ASSIGN') show = num(row.assign_due_count) > 0;
      else if (activeFilter === 'SUBMIT') show = num(row.submit_due_count) > 0;
      else if (activeFilter === 'ALTER') show = num(row.active_alter_count) > 0;
      card.classList.toggle('rr-v9092-hidden', !show);
    });
  }

  async function refresh(force=false) {
    const ctx = getContext();
    if (!ctx?.d || !ctx?.sb) return;
    ensureStyle(ctx.d);
    const dept = ctx.dept;
    if (force || dept !== lastDept || !lastPayload) {
      const {data,error} = await ctx.sb.rpc('rr_upm_lot_card_due_alter_header_v9092', {p_department_code: dept || null});
      if (error) { console.warn('V9092 header RPC unavailable', error); return; }
      lastDept = dept;
      lastPayload = data || {};
    }
    renderFilterBar(ctx, lastPayload);
    decorateCards(ctx, lastPayload);
    bindInnerChanges(ctx);
  }

  function bindInnerChanges(ctx) {
    const {d} = ctx;
    const home = d.getElementById('homeDept');
    if (home && !home.dataset.v9092Bound) {
      home.dataset.v9092Bound='1';
      home.addEventListener('change', () => setTimeout(() => { lastPayload=null; refresh(true); }, 250));
    }
    const refreshBtn = d.getElementById('refresh');
    if (refreshBtn && !refreshBtn.dataset.v9092Bound) {
      refreshBtn.dataset.v9092Bound='1';
      refreshBtn.addEventListener('click', () => setTimeout(() => { lastPayload=null; refresh(true); }, 400));
    }
    const board = d.getElementById('board');
    if (board && observer?.target !== board) {
      observer?.disconnect?.();
      observer = new MutationObserver(() => setTimeout(() => decorateCards(getContext() || ctx, lastPayload || {}), 30));
      observer.observe(board,{childList:true,subtree:false});
      observer.target = board;
    }
  }

  function start() {
    observer?.disconnect?.(); observer = null;
    lastDept = null; lastPayload = null; activeFilter = 'ALL';
    setTimeout(() => refresh(true), 250);
    setTimeout(() => refresh(true), 1200);
    clearInterval(refreshTimer);
    refreshTimer = setInterval(() => { lastPayload=null; refresh(true); }, 15000);
  }

  frame.addEventListener('load', start);
  if (frame.contentDocument?.readyState === 'complete') start();
})();
