(()=>{
'use strict';

const VERSION='773.3';
const STYLE_ID='rrTableControlsStyleV773';
const KEY_PREFIX='rr-table-controls:';

let sequence=0;
let activeTarget=null;
let syncing=false;
let refreshQueued=false;

const targets=new Set();
const metadata=new WeakMap();

function clean(value){
  return String(value??'')
    .replace(/\s+/g,' ')
    .trim();
}

function installStyle(){
  if(document.getElementById(STYLE_ID))return;

  const style=document.createElement('style');
  style.id=STYLE_ID;
  style.textContent=`
  .rr-table-control{
    display:flex;
    align-items:center;
    justify-content:flex-end;
    gap:7px;
    flex-wrap:wrap;
    margin:0 0 8px;
    position:relative;
    z-index:8
  }

  .rr-table-control button{
    min-height:38px;
    border-radius:9px!important;
    padding:8px 10px!important;
    font:750 12px system-ui,-apple-system,"Segoe UI",Arial,sans-serif!important;
    cursor:pointer!important;
    white-space:nowrap
  }

  .rr-table-toggle{
    background:#26324a!important;
    border:1px solid #49618d!important;
    color:#fff!important
  }

  .rr-table-toggle.rr-on{
    background:#174936!important;
    border-color:#318b65!important
  }

  .rr-table-filter-btn{
    background:#493915!important;
    border:1px solid #8a6b2b!important;
    color:#fff!important
  }

  .rr-table-clear-btn{
    background:#481d24!important;
    border:1px solid #8c3c49!important;
    color:#fff!important
  }

  .rr-table-row-count{
    min-height:38px;
    display:flex;
    align-items:center;
    justify-content:center;
    padding:0 10px;
    border:1px solid #39414d;
    border-radius:9px;
    background:#171b23;
    color:#dce5f3;
    font:750 12px system-ui,-apple-system,"Segoe UI",Arial,sans-serif
  }

  .rr-table-filter-panel{
    display:none;
    grid-template-columns:minmax(220px,1fr) auto;
    gap:8px;
    align-items:center;
    margin:0 0 8px;
    padding:9px;
    border:1px solid #39414d;
    border-radius:10px;
    background:#11161f;
    position:relative;
    z-index:7
  }

  .rr-table-filter-panel.rr-open{
    display:grid
  }

  .rr-table-filter-input{
    width:100%!important;
    min-height:42px;
    padding:9px 11px!important;
    border:1px solid #49618d!important;
    border-radius:9px!important;
    background:#202631!important;
    color:#fff!important;
    font:16px system-ui,-apple-system,"Segoe UI",Arial,sans-serif!important
  }

  .rr-table-filter-input:focus{
    outline:2px solid #56efb2;
    box-shadow:0 0 0 4px #56efb233
  }

  .rr-table-filter-help{
    color:#9eabc0;
    font:12px system-ui,-apple-system,"Segoe UI",Arial,sans-serif;
    white-space:normal
  }

  .rr-table-filter-hidden{
    display:none!important
  }

  .rr-table-target{
    position:relative!important;
    overflow:auto!important;
    -webkit-overflow-scrolling:touch;
    overscroll-behavior-x:contain;
    scrollbar-gutter:stable both-edges
  }

  .rr-freeze-header table thead th{
    position:sticky!important;
    top:0!important;
    z-index:30!important;
    background:#20252e!important
  }

  .rr-freeze-column table th:first-child,
  .rr-freeze-column table td:first-child{
    position:sticky!important;
    left:0!important;
    z-index:20!important;
    background:#151922!important;
    box-shadow:2px 0 0 #303641
  }

  .rr-freeze-header.rr-freeze-column table thead th:first-child{
    z-index:40!important;
    background:#20252e!important
  }

  .rr-freeze-column table tbody tr:hover td:first-child{
    background:#1b2029!important
  }

  /* Range slider is used because iOS can auto-hide native scrollbars. */
  #rrPersistentHorizontalV773{
    position:fixed;
    left:max(5px,var(--rr-safe-left,0px));
    right:max(5px,var(--rr-safe-right,0px));
    bottom:max(
      var(--rr-safe-bottom,0px),
      var(--rr-keyboard-inset,0px)
    );
    z-index:99999;
    display:none;
    grid-template-columns:46px minmax(0,1fr);
    gap:8px;
    align-items:center;
    min-height:36px;
    padding:5px 9px;
    background:#10131af7;
    border:1px solid #3d4654;
    border-radius:11px 11px 0 0;
    box-shadow:0 -7px 22px #000b;
    backdrop-filter:blur(5px)
  }

  #rrPersistentHorizontalV773.rr-visible{
    display:grid
  }

  #rrPersistentHorizontalV773 .rr-horizontal-label{
    height:27px;
    display:flex;
    align-items:center;
    justify-content:center;
    color:#fff;
    background:#174936;
    border:1px solid #318b65;
    border-radius:8px;
    font:900 15px system-ui,-apple-system,"Segoe UI",Arial,sans-serif;
    user-select:none
  }

  #rrPersistentHorizontalV773 input[type="range"]{
    width:100%;
    min-width:0;
    height:27px;
    margin:0;
    padding:0;
    accent-color:#56efb2;
    cursor:ew-resize;
    touch-action:pan-x
  }

  #rrPersistentHorizontalV773 input[type="range"]::-webkit-slider-runnable-track{
    height:9px;
    background:#3b4656;
    border-radius:999px;
    border:1px solid #64738a
  }

  #rrPersistentHorizontalV773 input[type="range"]::-webkit-slider-thumb{
    -webkit-appearance:none;
    width:28px;
    height:28px;
    margin-top:-10px;
    border-radius:50%;
    background:#56efb2;
    border:3px solid #0b2419;
    box-shadow:0 1px 6px #000c
  }

  body.rr-horizontal-control-active{
    padding-bottom:calc(
      46px +
      max(
        var(--rr-safe-bottom,0px),
        var(--rr-keyboard-inset,0px)
      )
    )!important
  }

  @media(max-width:700px), (pointer:coarse){
    .rr-table-control{
      justify-content:stretch;
      gap:6px
    }

    .rr-table-control button{
      flex:1 1 calc(50% - 6px);
      min-height:44px;
      padding:9px 7px!important;
      font-size:11px!important
    }

    .rr-table-row-count{
      flex:1 1 100%;
      min-height:38px
    }

    .rr-table-filter-panel{
      grid-template-columns:1fr
    }

    .rr-table-filter-input{
      min-height:46px;
      font-size:16px!important
    }

    #rrPersistentHorizontalV773{
      left:max(3px,var(--rr-safe-left,0px));
      right:max(3px,var(--rr-safe-right,0px));
      min-height:42px;
      grid-template-columns:40px minmax(0,1fr);
      padding:6px 8px
    }

    #rrPersistentHorizontalV773 input[type="range"]{
      height:31px
    }
  }
  `;

  document.head.appendChild(style);
}

function installPersistentControl(){
  if(document.getElementById('rrPersistentHorizontalV773'))return;

  const bar=document.createElement('div');
  bar.id='rrPersistentHorizontalV773';
  bar.innerHTML=`
    <div class="rr-horizontal-label" title="Horizontal table scroll">↔</div>
    <input
      id="rrPersistentHorizontalRangeV773"
      type="range"
      min="0"
      max="0"
      value="0"
      step="1"
      aria-label="Horizontal table scrollbar">
  `;

  document.body.appendChild(bar);

  const range=bar.querySelector('input');

  range.addEventListener('input',()=>{
    if(syncing||!activeTarget)return;

    syncing=true;
    activeTarget.scrollLeft=Number(range.value||0);
    requestAnimationFrame(()=>{syncing=false});
  });
}

function targetFor(table){
  return table.closest(
    '.table-wrap,.size-wrap,.rr-wrap,.collab-eval-box'
  )||table.parentElement;
}

function storageKey(target,name){
  if(!target.dataset.rrTableKey){
    sequence+=1;
    target.dataset.rrTableKey=
      `${location.pathname}:${sequence}`;
  }

  return `${KEY_PREFIX}${target.dataset.rrTableKey}:${name}`;
}

function readSetting(target,name,defaultValue=true){
  try{
    const value=localStorage.getItem(
      storageKey(target,name)
    );

    return value===null
      ?defaultValue
      :value==='1';
  }catch{
    return defaultValue;
  }
}

function writeSetting(target,name,value){
  try{
    localStorage.setItem(
      storageKey(target,name),
      value?'1':'0'
    );
  }catch{}
}

function setFreeze(meta,type,on){
  const header=type==='header';

  meta.target.classList.toggle(
    header?'rr-freeze-header':'rr-freeze-column',
    on
  );

  const button=header
    ?meta.headerButton
    :meta.columnButton;

  button.classList.toggle('rr-on',on);
  button.textContent=header
    ?(
      on
        ?'HEADER FREEZE ON'
        :'HEADER FREEZE OFF'
    )
    :(
      on
        ?'FIRST COLUMN FREEZE ON'
        :'FIRST COLUMN FREEZE OFF'
    );

  writeSetting(
    meta.target,
    header?'header':'column',
    on
  );

  queueRefresh();
}

function pairedRows(table){
  const pairs=[];

  for(const tbody of table.tBodies){
    const rows=[...tbody.rows];

    for(let index=0;index<rows.length;index+=1){
      const row=rows[index];

      if(row.classList.contains('collab-eval-row')){
        continue;
      }

      const related=[];

      if(
        rows[index+1]?.classList.contains(
          'collab-eval-row'
        )
      ){
        related.push(rows[index+1]);
        index+=1;
      }

      pairs.push({
        row,
        related,
        text:clean([
          row.textContent,
          ...related.map(item=>item.textContent)
        ].join(' ')).toLowerCase()
      });
    }
  }

  return pairs;
}

function applyFilter(meta){
  const query=meta.filterInput.value
    .trim()
    .toLowerCase();

  const pairs=pairedRows(meta.table);
  let visible=0;

  for(const pair of pairs){
    const show=!query||pair.text.includes(query);

    pair.row.classList.toggle(
      'rr-table-filter-hidden',
      !show
    );

    for(const related of pair.related){
      related.classList.toggle(
        'rr-table-filter-hidden',
        !show
      );
    }

    if(show)visible+=1;
  }

  meta.rowCount.textContent=query
    ?`ROWS ${visible} / ${pairs.length}`
    :`ROWS ${pairs.length}`;

  meta.clearButton.disabled=!query;
}

function toggleFilter(meta){
  const open=!meta.filterPanel.classList.contains(
    'rr-open'
  );

  meta.filterPanel.classList.toggle(
    'rr-open',
    open
  );

  meta.filterButton.classList.toggle(
    'rr-on',
    open
  );

  if(open){
    requestAnimationFrame(()=>{
      meta.filterInput.focus();
      meta.filterInput.select();
    });
  }
}

function clearFilter(meta){
  meta.filterInput.value='';
  applyFilter(meta);
  meta.filterInput.focus();
}

function hasOverflow(target){
  return Boolean(
    target&&
    target.isConnected&&
    target.scrollWidth>target.clientWidth+2
  );
}

function visibleScore(target){
  if(!target?.isConnected)return -Infinity;

  const rect=target.getBoundingClientRect();
  const height=
    window.visualViewport?.height||
    window.innerHeight||
    document.documentElement.clientHeight;

  const top=Math.max(rect.top,0);
  const bottom=Math.min(rect.bottom,height);
  const visible=Math.max(0,bottom-top);

  if(visible<=0)return -Infinity;

  return (
    visible*10
  )-Math.abs(
    ((top+bottom)/2)-(height/2)
  );
}

function bestTarget(){
  let best=null;
  let score=-Infinity;

  for(const target of targets){
    if(!hasOverflow(target))continue;

    const current=visibleScore(target);

    if(current>score){
      score=current;
      best=target;
    }
  }

  return best;
}

function activate(target){
  if(!hasOverflow(target))return;

  activeTarget=target;
  updatePersistentControl();
}

function updatePersistentControl(){
  const bar=document.getElementById(
    'rrPersistentHorizontalV773'
  );
  const range=document.getElementById(
    'rrPersistentHorizontalRangeV773'
  );

  if(!bar||!range)return;

  if(
    !activeTarget||
    !hasOverflow(activeTarget)||
    visibleScore(activeTarget)===-Infinity
  ){
    activeTarget=bestTarget();
  }

  if(!activeTarget){
    bar.classList.remove('rr-visible');
    document.body.classList.remove(
      'rr-horizontal-control-active'
    );
    return;
  }

  const max=Math.max(
    0,
    activeTarget.scrollWidth-
    activeTarget.clientWidth
  );

  if(max<=0){
    bar.classList.remove('rr-visible');
    document.body.classList.remove(
      'rr-horizontal-control-active'
    );
    return;
  }

  range.max=String(Math.ceil(max));
  range.value=String(
    Math.min(
      Math.ceil(max),
      Math.max(0,Math.round(activeTarget.scrollLeft))
    )
  );

  bar.classList.add('rr-visible');
  document.body.classList.add(
    'rr-horizontal-control-active'
  );
}

function queueRefresh(){
  if(refreshQueued)return;

  refreshQueued=true;

  requestAnimationFrame(()=>{
    refreshQueued=false;

    for(const target of [...targets]){
      if(!target.isConnected){
        targets.delete(target);
      }
    }

    updatePersistentControl();
  });
}

function enhance(table){
  if(
    !table||
    table.dataset.rrTableControlReady==='1'
  ){
    return;
  }

  const target=targetFor(table);
  if(!target)return;

  table.dataset.rrTableControlReady='1';
  target.classList.add('rr-table-target');
  targets.add(target);

  const control=document.createElement('div');
  control.className='rr-table-control';

  const headerButton=document.createElement('button');
  headerButton.type='button';
  headerButton.className='rr-table-toggle';
  headerButton.title='Header row freeze/unfreeze';

  const columnButton=document.createElement('button');
  columnButton.type='button';
  columnButton.className='rr-table-toggle';
  columnButton.title='First column freeze/unfreeze';

  const filterButton=document.createElement('button');
  filterButton.type='button';
  filterButton.className='rr-table-filter-btn rr-table-toggle';
  filterButton.textContent='FILTER';
  filterButton.title='Filter/search this table';

  const clearButton=document.createElement('button');
  clearButton.type='button';
  clearButton.className='rr-table-clear-btn';
  clearButton.textContent='CLEAR FILTER';
  clearButton.disabled=true;

  const rowCount=document.createElement('span');
  rowCount.className='rr-table-row-count';

  control.append(
    headerButton,
    columnButton,
    filterButton,
    clearButton,
    rowCount
  );

  const panel=document.createElement('div');
  panel.className='rr-table-filter-panel';

  const input=document.createElement('input');
  input.type='search';
  input.className='rr-table-filter-input';
  input.placeholder='Search Worker, Lot, Department, Colour, Size, Rate or Status';
  input.autocomplete='off';
  input.spellcheck=false;

  const help=document.createElement('div');
  help.className='rr-table-filter-help';
  help.textContent='Search applies only to this table. CLEAR FILTER restores every row.';

  panel.append(input,help);

  if(target.parentNode){
    target.parentNode.insertBefore(control,target);
    target.parentNode.insertBefore(panel,target);
  }

  const meta={
    table,
    target,
    headerButton,
    columnButton,
    filterButton,
    clearButton,
    rowCount,
    filterPanel:panel,
    filterInput:input
  };

  metadata.set(table,meta);

  setFreeze(
    meta,
    'header',
    readSetting(target,'header',true)
  );

  setFreeze(
    meta,
    'column',
    readSetting(target,'column',true)
  );

  headerButton.addEventListener('click',()=>{
    setFreeze(
      meta,
      'header',
      !target.classList.contains('rr-freeze-header')
    );
  });

  columnButton.addEventListener('click',()=>{
    setFreeze(
      meta,
      'column',
      !target.classList.contains('rr-freeze-column')
    );
  });

  filterButton.addEventListener(
    'click',
    ()=>toggleFilter(meta)
  );

  clearButton.addEventListener(
    'click',
    ()=>clearFilter(meta)
  );

  input.addEventListener(
    'input',
    ()=>applyFilter(meta)
  );

  input.addEventListener('keydown',event=>{
    if(event.key==='Escape'){
      clearFilter(meta);
      panel.classList.remove('rr-open');
      filterButton.classList.remove('rr-on');
    }
  });

  const activateTarget=()=>activate(target);

  target.addEventListener('pointerenter',activateTarget);
  target.addEventListener('pointerdown',activateTarget);
  target.addEventListener('touchstart',activateTarget,{passive:true});
  target.addEventListener('focusin',activateTarget);

  target.addEventListener('scroll',()=>{
    if(activeTarget!==target){
      activeTarget=target;
    }

    if(!syncing){
      syncing=true;

      const range=document.getElementById(
        'rrPersistentHorizontalRangeV773'
      );

      if(range){
        range.value=String(
          Math.round(target.scrollLeft)
        );
      }

      requestAnimationFrame(()=>{syncing=false});
    }
  },{passive:true});

  const bodyObserver=new MutationObserver(()=>{
    applyFilter(meta);
    queueRefresh();
  });

  for(const tbody of table.tBodies){
    bodyObserver.observe(
      tbody,
      {
        childList:true,
        subtree:true,
        characterData:true
      }
    );
  }

  if(window.ResizeObserver){
    const resizeObserver=new ResizeObserver(
      queueRefresh
    );

    resizeObserver.observe(target);
    resizeObserver.observe(table);
  }

  applyFilter(meta);
  queueRefresh();
}

function scan(){
  document.querySelectorAll('table').forEach(
    enhance
  );

  queueRefresh();
}

function boot(){
  installStyle();
  installPersistentControl();
  scan();

  new MutationObserver(scan).observe(
    document.body,
    {
      childList:true,
      subtree:true
    }
  );

  window.addEventListener(
    'scroll',
    queueRefresh,
    {passive:true}
  );

  window.addEventListener(
    'resize',
    queueRefresh,
    {passive:true}
  );

  window.addEventListener(
    'orientationchange',
    ()=>setTimeout(queueRefresh,150),
    {passive:true}
  );

  if(window.visualViewport){
    visualViewport.addEventListener(
      'resize',
      queueRefresh,
      {passive:true}
    );

    visualViewport.addEventListener(
      'scroll',
      queueRefresh,
      {passive:true}
    );
  }
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',boot);
}else{
  boot();
}

window.REDZED_TABLE_CONTROLS_VERSION=VERSION;
})();
