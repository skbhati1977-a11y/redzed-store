(()=>{
'use strict';

if(window.__REDZED_GOOGLE_TABLES_V775__)return;
window.__REDZED_GOOGLE_TABLES_V775__=true;

const VERSION='775.1';
const STYLE_ID='rrGoogleTablesStyleV775';
const STORAGE_PREFIX='rr-gsheet:';

let serial=0;
let activeTarget=null;
let syncing=false;
let refreshQueued=false;
let openMenu=null;

const enhancedTables=new Set();
const tableMeta=new WeakMap();

const clean=value=>String(value??'')
  .replace(/\s+/g,' ')
  .trim();

const safe=value=>String(value??'').replace(/[&<>"']/g,char=>({
  '&':'&amp;',
  '<':'&lt;',
  '>':'&gt;',
  '"':'&quot;',
  "'":'&#039;'
}[char]));

function installStyle(){
  if(document.getElementById(STYLE_ID))return;

  const style=document.createElement('style');
  style.id=STYLE_ID;
  style.textContent=`
  .rr-gsheet-wrap{
    position:relative!important;
    overflow-x:auto!important;
    overflow-y:visible!important;
    max-height:none!important;
    -webkit-overflow-scrolling:touch;
    overscroll-behavior:contain;
    scrollbar-gutter:stable both-edges
  }

  .rr-gsheet-wrap.rr-gsheet-vertical{
    overflow:auto!important;
    max-height:min(70vh,760px)!important
  }

  .rr-gsheet-toolbar{
    display:flex;
    align-items:center;
    justify-content:flex-end;
    gap:7px;
    flex-wrap:wrap;
    margin:0 0 8px;
    position:relative;
    z-index:20
  }

  .rr-gsheet-toolbar button,
  .rr-gsheet-toolbar select{
    min-height:40px;
    border-radius:9px!important;
    padding:8px 10px!important;
    font:750 12px system-ui,-apple-system,"Segoe UI",Arial,sans-serif!important;
    color:#fff!important;
    border:1px solid #49618d!important;
    background:#26324a!important;
    cursor:pointer!important;
    white-space:nowrap
  }

  .rr-gsheet-toolbar button.rr-on{
    background:#174936!important;
    border-color:#318b65!important
  }

  .rr-gsheet-toolbar .rr-filter-master{
    background:#493915!important;
    border-color:#8a6b2b!important
  }

  .rr-gsheet-toolbar .rr-clear-all{
    background:#481d24!important;
    border-color:#8c3c49!important
  }

  .rr-gsheet-toolbar .rr-row-count{
    min-height:40px;
    display:flex;
    align-items:center;
    justify-content:center;
    padding:0 10px;
    border:1px solid #39414d;
    border-radius:9px;
    background:#171b23;
    color:#dce5f3;
    font:750 12px system-ui,-apple-system,"Segoe UI",Arial,sans-serif;
    white-space:nowrap
  }

  .rr-gsheet-header-label{
    display:inline-flex;
    align-items:center;
    gap:4px;
    max-width:100%
  }

  .rr-gsheet-filter-btn{
    width:28px!important;
    min-width:28px!important;
    height:28px!important;
    min-height:28px!important;
    padding:0!important;
    margin-left:5px!important;
    border:1px solid #56647a!important;
    border-radius:7px!important;
    background:#2a3240!important;
    color:#fff!important;
    font:900 13px/1 system-ui,-apple-system,"Segoe UI",Arial,sans-serif!important;
    vertical-align:middle!important;
    cursor:pointer!important
  }

  .rr-gsheet-filter-btn:hover,
  .rr-gsheet-filter-btn:focus{
    background:#3a4659!important;
    outline:2px solid #56efb2!important
  }

  .rr-gsheet-filter-btn.rr-active{
    background:#8a6415!important;
    border-color:#d3a234!important
  }

  .rr-gsheet-filters-off .rr-gsheet-filter-btn{
    display:none!important
  }

  .rr-gsheet-row-hidden{
    display:none!important
  }

  .rr-gsheet-menu{
    position:fixed;
    z-index:2147483000;
    width:min(340px,calc(100vw - 16px));
    max-height:min(72dvh,610px);
    display:grid;
    grid-template-rows:auto auto auto minmax(120px,1fr) auto;
    background:#11161f;
    color:#fff;
    border:1px solid #4b586d;
    border-radius:12px;
    box-shadow:0 18px 50px #000d;
    overflow:hidden
  }

  .rr-gsheet-menu-header{
    display:flex;
    align-items:center;
    justify-content:space-between;
    gap:8px;
    padding:10px;
    background:#1b2330;
    border-bottom:1px solid #3d4654
  }

  .rr-gsheet-menu-header b{
    white-space:normal
  }

  .rr-gsheet-menu-close{
    width:34px!important;
    min-width:34px!important;
    height:34px!important;
    min-height:34px!important;
    padding:0!important;
    border-radius:8px!important
  }

  .rr-gsheet-menu-search{
    width:calc(100% - 16px)!important;
    margin:8px!important;
    min-height:44px!important;
    padding:9px 11px!important;
    border:1px solid #56647a!important;
    border-radius:9px!important;
    background:#202631!important;
    color:#fff!important;
    font:16px system-ui,-apple-system,"Segoe UI",Arial,sans-serif!important
  }

  .rr-gsheet-sort-row,
  .rr-gsheet-select-row,
  .rr-gsheet-menu-actions{
    display:flex;
    gap:6px;
    flex-wrap:wrap;
    padding:8px;
    border-bottom:1px solid #303a48
  }

  .rr-gsheet-menu-actions{
    border-bottom:0;
    border-top:1px solid #303a48
  }

  .rr-gsheet-sort-row button,
  .rr-gsheet-select-row button,
  .rr-gsheet-menu-actions button{
    flex:1 1 auto;
    min-height:38px;
    border-radius:8px;
    border:1px solid #4b586d;
    background:#26324a;
    color:#fff;
    font-weight:750;
    cursor:pointer
  }

  .rr-gsheet-menu-actions .rr-apply{
    background:#174936;
    border-color:#318b65
  }

  .rr-gsheet-menu-actions .rr-clear{
    background:#481d24;
    border-color:#8c3c49
  }

  .rr-gsheet-values{
    overflow:auto;
    padding:6px 8px;
    -webkit-overflow-scrolling:touch
  }

  .rr-gsheet-value{
    display:flex;
    align-items:flex-start;
    gap:9px;
    min-height:38px;
    padding:7px 5px;
    border-bottom:1px solid #ffffff12;
    cursor:pointer
  }

  .rr-gsheet-value input{
    width:20px;
    height:20px;
    flex:0 0 20px;
    margin-top:1px
  }

  .rr-gsheet-value span{
    white-space:normal;
    overflow-wrap:anywhere
  }

  /*
   * Existing modules may already use sticky cells.
   * Global utility controls every sticky state with inline styles.
   */
  .rr-gsheet-wrap table th,
  .rr-gsheet-wrap table td{
    scroll-margin-top:52px
  }

  #rrGsheetBottomScrollV775{
    position:fixed;
    left:max(5px,var(--rr-safe-left,0px));
    right:max(5px,var(--rr-safe-right,0px));
    bottom:max(
      var(--rr-safe-bottom,0px),
      var(--rr-keyboard-inset,0px)
    );
    z-index:2147482000;
    display:none;
    grid-template-columns:46px minmax(0,1fr);
    gap:8px;
    align-items:center;
    min-height:38px;
    padding:5px 9px;
    background:#10131af8;
    border:1px solid #3d4654;
    border-radius:11px 11px 0 0;
    box-shadow:0 -7px 22px #000b;
    backdrop-filter:blur(5px)
  }

  #rrGsheetBottomScrollV775.rr-visible{
    display:grid
  }

  #rrGsheetBottomScrollV775 .rr-label{
    height:28px;
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

  #rrGsheetBottomScrollV775 input[type="range"]{
    width:100%;
    min-width:0;
    height:29px;
    margin:0;
    padding:0;
    accent-color:#56efb2;
    cursor:ew-resize;
    touch-action:pan-x
  }

  #rrGsheetBottomScrollV775 input[type="range"]::-webkit-slider-runnable-track{
    height:9px;
    background:#3b4656;
    border-radius:999px;
    border:1px solid #64738a
  }

  #rrGsheetBottomScrollV775 input[type="range"]::-webkit-slider-thumb{
    -webkit-appearance:none;
    width:29px;
    height:29px;
    margin-top:-11px;
    border-radius:50%;
    background:#56efb2;
    border:3px solid #0b2419;
    box-shadow:0 1px 6px #000c
  }

  body.rr-gsheet-bottom-active{
    padding-bottom:calc(
      48px +
      max(
        var(--rr-safe-bottom,0px),
        var(--rr-keyboard-inset,0px)
      )
    )!important
  }

  @media(max-width:700px),(pointer:coarse){
    .rr-gsheet-toolbar{
      justify-content:stretch
    }

    .rr-gsheet-toolbar button,
    .rr-gsheet-toolbar select{
      flex:1 1 calc(50% - 7px);
      min-height:44px;
      font-size:11px!important
    }

    .rr-gsheet-toolbar .rr-row-count{
      flex:1 1 100%
    }

    .rr-gsheet-menu{
      width:calc(100vw - 8px);
      left:4px!important;
      right:4px!important;
      bottom:max(
        4px,
        var(--rr-keyboard-inset,0px),
        var(--rr-safe-bottom,0px)
      )!important;
      top:auto!important;
      max-height:min(76dvh,650px)
    }

    .rr-gsheet-wrap.rr-gsheet-vertical{
      max-height:min(60dvh,640px)!important
    }
  }
  `;

  document.head.appendChild(style);
}

function installBottomScroll(){
  if(document.getElementById('rrGsheetBottomScrollV775'))return;

  const bar=document.createElement('div');
  bar.id='rrGsheetBottomScrollV775';
  bar.innerHTML=`
    <div class="rr-label" title="Always visible horizontal table scroll">↔</div>
    <input
      id="rrGsheetBottomRangeV775"
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

function ensureWrap(table){
  const known=table.closest(
    '.rr-gsheet-wrap,.table-wrap,.size-wrap,.rr-wrap,.collab-eval-box,[data-table-wrap]'
  );

  if(known){
    known.classList.add('rr-gsheet-wrap');
    return known;
  }

  const wrap=document.createElement('div');
  wrap.className='rr-gsheet-wrap';
  table.parentNode.insertBefore(wrap,table);
  wrap.appendChild(table);
  return wrap;
}

function tableKey(table){
  if(!table.dataset.rrGsheetKey){
    serial+=1;
    table.dataset.rrGsheetKey=
      `${location.pathname}:${table.id||'table'}:${serial}`;
  }
  return table.dataset.rrGsheetKey;
}

function readSetting(meta,name,fallback){
  try{
    const value=localStorage.getItem(
      `${STORAGE_PREFIX}${meta.key}:${name}`
    );
    return value===null?fallback:JSON.parse(value);
  }catch{
    return fallback;
  }
}

function writeSetting(meta,name,value){
  try{
    localStorage.setItem(
      `${STORAGE_PREFIX}${meta.key}:${name}`,
      JSON.stringify(value)
    );
  }catch{}
}

function lastHeaderRow(table){
  if(!table.tHead||!table.tHead.rows.length)return null;
  return table.tHead.rows[table.tHead.rows.length-1];
}

function columnCount(table){
  const header=lastHeaderRow(table);
  if(header)return header.cells.length;

  let max=0;
  for(const row of table.rows){
    max=Math.max(max,row.cells.length);
  }
  return max;
}

function rowPairs(table){
  const pairs=[];

  for(const tbody of table.tBodies){
    const rows=[...tbody.rows];

    for(let index=0;index<rows.length;index+=1){
      const row=rows[index];

      if(row.classList.contains('collab-eval-row'))continue;

      const related=[];
      if(rows[index+1]?.classList.contains('collab-eval-row')){
        related.push(rows[index+1]);
        index+=1;
      }

      pairs.push({row,related});
    }
  }

  return pairs;
}

function cellValue(row,column){
  const cell=row.cells[column];
  return clean(cell?.innerText||cell?.textContent||'')||'(Blank)';
}

function uniqueValues(meta,column){
  const values=new Set();

  for(const pair of rowPairs(meta.table)){
    values.add(cellValue(pair.row,column));
  }

  return [...values].sort((a,b)=>
    a.localeCompare(b,undefined,{numeric:true,sensitivity:'base'})
  );
}

function filtersActive(meta){
  return [...meta.filters.values()].some(set=>set instanceof Set);
}

function applyFilters(meta){
  const pairs=rowPairs(meta.table);
  let visible=0;

  for(const pair of pairs){
    let show=true;

    for(const [column,selected] of meta.filters.entries()){
      if(!(selected instanceof Set))continue;
      if(!selected.has(cellValue(pair.row,column))){
        show=false;
        break;
      }
    }

    pair.row.classList.toggle('rr-gsheet-row-hidden',!show);
    for(const related of pair.related){
      related.classList.toggle('rr-gsheet-row-hidden',!show);
    }

    if(show)visible+=1;
  }

  meta.count.textContent=filtersActive(meta)
    ?`ROWS ${visible} / ${pairs.length}`
    :`ROWS ${pairs.length}`;

  for(const [column,button] of meta.filterButtons.entries()){
    button.classList.toggle(
      'rr-active',
      meta.filters.get(column) instanceof Set
    );
  }

  meta.clearButton.disabled=!filtersActive(meta);
  writeSetting(
    meta,
    'filters',
    [...meta.filters.entries()].map(([column,set])=>[
      column,
      set instanceof Set?[...set]:null
    ])
  );
}

function restoreFilters(meta){
  const stored=readSetting(meta,'filters',[]);

  if(!Array.isArray(stored))return;

  for(const item of stored){
    if(!Array.isArray(item)||item.length!==2)continue;
    const [column,values]=item;
    if(Array.isArray(values)){
      meta.filters.set(Number(column),new Set(values));
    }
  }
}

function clearAllFilters(meta){
  meta.filters.clear();
  applyFilters(meta);
  closeFilterMenu();
}

function sortRows(meta,column,direction){
  const pairs=rowPairs(meta.table);
  const tbody=meta.table.tBodies[0];
  if(!tbody)return;

  const multiplier=direction==='desc'?-1:1;

  pairs.sort((a,b)=>{
    const av=cellValue(a.row,column);
    const bv=cellValue(b.row,column);

    const an=Number(av.replace(/[^0-9.+-]/g,''));
    const bn=Number(bv.replace(/[^0-9.+-]/g,''));

    if(
      Number.isFinite(an)&&
      Number.isFinite(bn)&&
      /\d/.test(av)&&
      /\d/.test(bv)
    ){
      return (an-bn)*multiplier;
    }

    return av.localeCompare(
      bv,
      undefined,
      {numeric:true,sensitivity:'base'}
    )*multiplier;
  });

  const fragment=document.createDocumentFragment();
  for(const pair of pairs){
    fragment.appendChild(pair.row);
    for(const related of pair.related){
      fragment.appendChild(related);
    }
  }
  tbody.appendChild(fragment);

  applyFilters(meta);
  applyFreeze(meta);
}

function closeFilterMenu(){
  if(openMenu?.isConnected)openMenu.remove();
  openMenu=null;
}

function positionMenu(menu,button){
  const rect=button.getBoundingClientRect();
  const width=Math.min(340,window.innerWidth-16);
  let left=Math.min(
    Math.max(8,rect.left),
    Math.max(8,window.innerWidth-width-8)
  );
  let top=rect.bottom+6;

  const estimatedHeight=Math.min(610,window.innerHeight*.72);
  if(top+estimatedHeight>window.innerHeight-8){
    top=Math.max(8,rect.top-estimatedHeight-6);
  }

  menu.style.left=`${left}px`;
  menu.style.top=`${top}px`;
}

function openFilterMenu(meta,column,button){
  closeFilterMenu();

  const allValues=uniqueValues(meta,column);
  const current=meta.filters.get(column);
  const selected=new Set(
    current instanceof Set?current:allValues
  );

  const headerCell=lastHeaderRow(meta.table)?.cells[column];
  const title=clean(
    headerCell?.dataset.rrOriginalHeader||
    headerCell?.innerText||
    `Column ${column+1}`
  );

  const menu=document.createElement('section');
  menu.className='rr-gsheet-menu';
  menu.innerHTML=`
    <div class="rr-gsheet-menu-header">
      <b>${safe(title)}</b>
      <button class="rr-gsheet-menu-close" type="button">×</button>
    </div>

    <input
      class="rr-gsheet-menu-search"
      type="search"
      placeholder="Search values"
      autocomplete="off">

    <div>
      <div class="rr-gsheet-sort-row">
        <button data-sort="asc" type="button">SORT A → Z</button>
        <button data-sort="desc" type="button">SORT Z → A</button>
      </div>
      <div class="rr-gsheet-select-row">
        <button data-select-all type="button">SELECT ALL</button>
        <button data-select-none type="button">CLEAR SELECTION</button>
      </div>
    </div>

    <div class="rr-gsheet-values"></div>

    <div class="rr-gsheet-menu-actions">
      <button class="rr-clear" data-clear-column type="button">CLEAR FILTER</button>
      <button class="rr-apply" data-apply type="button">APPLY</button>
    </div>
  `;

  document.body.appendChild(menu);
  openMenu=menu;
  positionMenu(menu,button);

  const search=menu.querySelector('.rr-gsheet-menu-search');
  const list=menu.querySelector('.rr-gsheet-values');

  function renderValues(){
    const query=search.value.trim().toLowerCase();
    const visible=allValues.filter(value=>
      !query||value.toLowerCase().includes(query)
    );

    list.innerHTML=visible.length
      ?visible.map((value,index)=>`
        <label class="rr-gsheet-value">
          <input
            type="checkbox"
            data-value-index="${index}"
            ${selected.has(value)?'checked':''}>
          <span>${safe(value)}</span>
        </label>
      `).join('')
      :'<div style="padding:14px;color:#9eabc0">No matching values.</div>';

    [...list.querySelectorAll('input[data-value-index]')].forEach(
      (checkbox,index)=>{
        const value=visible[index];
        checkbox.addEventListener('change',()=>{
          if(checkbox.checked)selected.add(value);
          else selected.delete(value);
        });
      }
    );
  }

  renderValues();
  search.addEventListener('input',renderValues);

  menu.querySelector('.rr-gsheet-menu-close').onclick=closeFilterMenu;

  menu.querySelector('[data-select-all]').onclick=()=>{
    allValues.forEach(value=>selected.add(value));
    renderValues();
  };

  menu.querySelector('[data-select-none]').onclick=()=>{
    selected.clear();
    renderValues();
  };

  menu.querySelector('[data-clear-column]').onclick=()=>{
    meta.filters.delete(column);
    applyFilters(meta);
    closeFilterMenu();
  };

  menu.querySelector('[data-apply]').onclick=()=>{
    if(selected.size===allValues.length){
      meta.filters.delete(column);
    }else{
      meta.filters.set(column,new Set(selected));
    }
    applyFilters(meta);
    closeFilterMenu();
  };

  [...menu.querySelectorAll('[data-sort]')].forEach(sortButton=>{
    sortButton.onclick=()=>{
      sortRows(meta,column,sortButton.dataset.sort);
      closeFilterMenu();
    };
  });

  requestAnimationFrame(()=>{
    search.focus();
    search.select();
  });
}

function installHeaderFilters(meta){
  const row=lastHeaderRow(meta.table);
  if(!row)return;

  [...row.cells].forEach((cell,column)=>{
    if(cell.querySelector(':scope > .rr-gsheet-filter-btn'))return;

    if(!cell.dataset.rrOriginalHeader){
      cell.dataset.rrOriginalHeader=clean(cell.innerText||cell.textContent);
    }

    const button=document.createElement('button');
    button.type='button';
    button.className='rr-gsheet-filter-btn';
    button.textContent='▼';
    button.title=`Filter ${cell.dataset.rrOriginalHeader||`Column ${column+1}`}`;
    button.setAttribute('aria-label',button.title);

    button.addEventListener('click',event=>{
      event.stopPropagation();
      openFilterMenu(meta,column,button);
    });

    cell.appendChild(button);
    meta.filterButtons.set(column,button);
  });
}

function createSelect(label,max,value){
  const select=document.createElement('select');
  select.setAttribute('aria-label',label);

  for(let index=0;index<=max;index+=1){
    const option=document.createElement('option');
    option.value=String(index);
    option.textContent=index===0
      ?`${label}: NONE`
      :`${label}: ${index}`;
    select.appendChild(option);
  }

  select.value=String(
    Math.min(max,Math.max(0,Number(value)||0))
  );

  return select;
}

function logicalColumnWidths(meta){
  const row=lastHeaderRow(meta.table)||meta.table.rows[0];
  const count=columnCount(meta.table);
  const widths=Array(count).fill(0);

  if(row){
    [...row.cells].forEach((cell,index)=>{
      widths[index]=cell.getBoundingClientRect().width;
    });
  }

  for(let index=0;index<count;index+=1){
    if(widths[index]>0)continue;

    for(const rowItem of meta.table.rows){
      const cell=rowItem.cells[index];
      if(cell){
        widths[index]=cell.getBoundingClientRect().width;
        break;
      }
    }
  }

  return widths;
}

function resetStickyStyles(meta){
  for(const cell of meta.table.querySelectorAll('th,td')){
    cell.style.removeProperty('position');
    cell.style.removeProperty('top');
    cell.style.removeProperty('left');
    cell.style.removeProperty('z-index');
    cell.style.removeProperty('box-shadow');
    cell.style.removeProperty('background');
  }
}

function applyFreeze(meta){
  resetStickyStyles(meta);

  const freezeRows=Math.max(0,Number(meta.freezeRows.value)||0);
  const freezeColumns=Math.max(0,Number(meta.freezeColumns.value)||0);
  const allRows=[...meta.table.rows];

  meta.wrap.classList.toggle(
    'rr-gsheet-vertical',
    freezeRows>0
  );

  const rowOffsets=[];
  let top=0;

  for(let index=0;index<freezeRows&&index<allRows.length;index+=1){
    rowOffsets[index]=top;
    top+=allRows[index].getBoundingClientRect().height;
  }

  const widths=logicalColumnWidths(meta);
  const leftOffsets=[];
  let left=0;

  for(let index=0;index<freezeColumns&&index<widths.length;index+=1){
    leftOffsets[index]=left;
    left+=widths[index]||0;
  }

  allRows.forEach((row,rowIndex)=>{
    [...row.cells].forEach((cell,columnIndex)=>{
      const rowFrozen=rowIndex<freezeRows;
      const columnFrozen=columnIndex<freezeColumns;

      if(!rowFrozen&&!columnFrozen)return;

      cell.style.setProperty('position','sticky','important');

      if(rowFrozen){
        cell.style.setProperty(
          'top',
          `${rowOffsets[rowIndex]||0}px`,
          'important'
        );
      }

      if(columnFrozen){
        cell.style.setProperty(
          'left',
          `${leftOffsets[columnIndex]||0}px`,
          'important'
        );
        cell.style.setProperty(
          'box-shadow',
          '2px 0 0 #303641',
          'important'
        );
      }

      cell.style.setProperty(
        'z-index',
        rowFrozen&&columnFrozen
          ?'45'
          :rowFrozen
            ?'35'
            :'25',
        'important'
      );

      const computed=getComputedStyle(cell).backgroundColor;
      const transparent=
        !computed||
        computed==='rgba(0, 0, 0, 0)'||
        computed==='transparent';

      cell.style.setProperty(
        'background',
        transparent
          ?(
            cell.tagName==='TH'
              ?'#20252e'
              :'#151922'
          )
          :computed,
        'important'
      );
    });
  });

  writeSetting(meta,'freezeRows',freezeRows);
  writeSetting(meta,'freezeColumns',freezeColumns);
  queueRefresh();
}

function createToolbar(meta){
  const toolbar=document.createElement('div');
  toolbar.className='rr-gsheet-toolbar';

  const filterToggle=document.createElement('button');
  filterToggle.type='button';
  filterToggle.className='rr-filter-master rr-on';
  filterToggle.textContent='COLUMN FILTERS ON';

  const clearButton=document.createElement('button');
  clearButton.type='button';
  clearButton.className='rr-clear-all';
  clearButton.textContent='CLEAR ALL FILTERS';
  clearButton.disabled=true;

  const maxRows=Math.min(5,Math.max(1,meta.table.rows.length));
  const maxColumns=Math.min(8,Math.max(1,columnCount(meta.table)));

  const defaultRows=Math.min(
    maxRows,
    Number(readSetting(meta,'freezeRows',1))||0
  );
  const defaultColumns=Math.min(
    maxColumns,
    Number(readSetting(meta,'freezeColumns',1))||0
  );

  const freezeRows=createSelect('FREEZE TOP ROWS',maxRows,defaultRows);
  const freezeColumns=createSelect('FREEZE LEFT COLUMNS',maxColumns,defaultColumns);

  const count=document.createElement('span');
  count.className='rr-row-count';

  toolbar.append(
    filterToggle,
    clearButton,
    freezeRows,
    freezeColumns,
    count
  );

  meta.wrap.parentNode.insertBefore(toolbar,meta.wrap);

  meta.toolbar=toolbar;
  meta.filterToggle=filterToggle;
  meta.clearButton=clearButton;
  meta.freezeRows=freezeRows;
  meta.freezeColumns=freezeColumns;
  meta.count=count;

  filterToggle.addEventListener('click',()=>{
    const off=meta.wrap.classList.toggle('rr-gsheet-filters-off');
    filterToggle.classList.toggle('rr-on',!off);
    filterToggle.textContent=off
      ?'COLUMN FILTERS OFF'
      :'COLUMN FILTERS ON';
    if(off)closeFilterMenu();
  });

  clearButton.addEventListener('click',()=>clearAllFilters(meta));
  freezeRows.addEventListener('change',()=>applyFreeze(meta));
  freezeColumns.addEventListener('change',()=>applyFreeze(meta));
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
  const height=window.visualViewport?.height||window.innerHeight;
  const top=Math.max(rect.top,0);
  const bottom=Math.min(rect.bottom,height);
  const visible=Math.max(0,bottom-top);

  if(visible<=0)return -Infinity;

  return (visible*10)-Math.abs(
    ((top+bottom)/2)-(height/2)
  );
}

function bestTarget(){
  let best=null;
  let score=-Infinity;

  for(const table of enhancedTables){
    const meta=tableMeta.get(table);
    if(!meta||!hasOverflow(meta.wrap))continue;

    const current=visibleScore(meta.wrap);
    if(current>score){
      score=current;
      best=meta.wrap;
    }
  }

  return best;
}

function activateTarget(target){
  if(!hasOverflow(target))return;
  activeTarget=target;
  updateBottomScroll();
}

function updateBottomScroll(){
  const bar=document.getElementById('rrGsheetBottomScrollV775');
  const range=document.getElementById('rrGsheetBottomRangeV775');
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
    document.body.classList.remove('rr-gsheet-bottom-active');
    return;
  }

  const max=Math.max(
    0,
    activeTarget.scrollWidth-activeTarget.clientWidth
  );

  if(max<=0){
    bar.classList.remove('rr-visible');
    document.body.classList.remove('rr-gsheet-bottom-active');
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
  document.body.classList.add('rr-gsheet-bottom-active');
}

function queueRefresh(){
  if(refreshQueued)return;

  refreshQueued=true;
  requestAnimationFrame(()=>{
    refreshQueued=false;
    updateBottomScroll();
  });
}

function enhanceTable(table){
  if(
    !table||
    table.dataset.rrGoogleSheetReady==='1'||
    table.closest('.rr-gsheet-menu')
  ){
    return;
  }

  table.dataset.rrGoogleSheetReady='1';

  const wrap=ensureWrap(table);
  const meta={
    table,
    wrap,
    key:tableKey(table),
    filters:new Map(),
    filterButtons:new Map()
  };

  tableMeta.set(table,meta);
  enhancedTables.add(table);

  createToolbar(meta);
  installHeaderFilters(meta);
  restoreFilters(meta);
  applyFilters(meta);
  applyFreeze(meta);

  const activate=()=>activateTarget(wrap);
  wrap.addEventListener('pointerenter',activate);
  wrap.addEventListener('pointerdown',activate);
  wrap.addEventListener('touchstart',activate,{passive:true});
  wrap.addEventListener('focusin',activate);

  wrap.addEventListener('scroll',()=>{
    activeTarget=wrap;

    if(!syncing){
      syncing=true;
      const range=document.getElementById('rrGsheetBottomRangeV775');
      if(range)range.value=String(Math.round(wrap.scrollLeft));
      requestAnimationFrame(()=>{syncing=false});
    }
  },{passive:true});

  const observer=new MutationObserver(()=>{
    installHeaderFilters(meta);
    applyFilters(meta);
    applyFreeze(meta);
    queueRefresh();
  });

  observer.observe(table,{
    childList:true,
    subtree:true,
    characterData:true
  });

  if(window.ResizeObserver){
    const resizeObserver=new ResizeObserver(()=>{
      applyFreeze(meta);
      queueRefresh();
    });
    resizeObserver.observe(wrap);
    resizeObserver.observe(table);
  }

  queueRefresh();
}

function scan(){
  document.querySelectorAll('table').forEach(enhanceTable);
  queueRefresh();
}

function boot(){
  installStyle();
  installBottomScroll();
  scan();

  new MutationObserver(scan).observe(
    document.body,
    {childList:true,subtree:true}
  );

  document.addEventListener('pointerdown',event=>{
    if(
      openMenu&&
      !openMenu.contains(event.target)&&
      !event.target.closest('.rr-gsheet-filter-btn')
    ){
      closeFilterMenu();
    }
  });

  window.addEventListener('scroll',queueRefresh,{passive:true});
  window.addEventListener('resize',queueRefresh,{passive:true});
  window.addEventListener('orientationchange',()=>{
    closeFilterMenu();
    setTimeout(queueRefresh,150);
  },{passive:true});

  if(window.visualViewport){
    visualViewport.addEventListener('resize',queueRefresh,{passive:true});
    visualViewport.addEventListener('scroll',queueRefresh,{passive:true});
  }

  window.RRGoogleSheetsTables={
    version:VERSION,
    refresh:scan,
    clearAll(){
      for(const table of enhancedTables){
        const meta=tableMeta.get(table);
        if(meta)clearAllFilters(meta);
      }
    }
  };

  if(window.RR){
    window.RR.googleSheetsTables=window.RRGoogleSheetsTables;
  }
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',boot);
}else{
  boot();
}

window.REDZED_GOOGLE_TABLES_VERSION=VERSION;
})();
