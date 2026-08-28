(()=>{
  'use strict';
  if(window.__RR_WS_STOCK_FREEZE_V9414__)return;
  window.__RR_WS_STOCK_FREEZE_V9414__=true;
  if(!/\/real-finished-goods-v787\.html$/i.test(location.pathname))return;

  const STYLE_ID='rrWsStockFreezeV9414';
  function install(){
    if(document.getElementById(STYLE_ID))return;
    const s=document.createElement('style');
    s.id=STYLE_ID;
    s.textContent=`
      [data-view="stock"] .rr-ws-table-wrap{
        position:relative!important;
        max-height:calc(100dvh - 220px)!important;
        overflow:auto!important;
        -webkit-overflow-scrolling:touch!important;
      }
      [data-view="stock"] #stockRowsV9411Table thead th{
        position:sticky!important;
        top:0!important;
        z-index:30!important;
        background:#20232b!important;
        box-shadow:0 2px 0 #30343d!important;
      }
      [data-view="stock"] #stockRowsV9411Table th:nth-child(1),
      [data-view="stock"] #stockRowsV9411Table td:nth-child(1){
        position:sticky!important;
        left:0!important;
        width:60px!important;
        min-width:60px!important;
        max-width:60px!important;
        z-index:22!important;
        background:#17191f!important;
      }
      [data-view="stock"] #stockRowsV9411Table th:nth-child(2),
      [data-view="stock"] #stockRowsV9411Table td:nth-child(2){
        position:sticky!important;
        left:60px!important;
        min-width:112px!important;
        z-index:21!important;
        background:#17191f!important;
        box-shadow:2px 0 0 #30343d!important;
      }
      [data-view="stock"] #stockRowsV9411Table thead th:nth-child(1),
      [data-view="stock"] #stockRowsV9411Table thead th:nth-child(2){
        z-index:40!important;
        background:#20232b!important;
      }
      @media(max-width:650px){
        [data-view="stock"] .rr-ws-table-wrap{max-height:calc(100dvh - 205px)!important}
        [data-view="stock"] #stockRowsV9411Table th:nth-child(1),
        [data-view="stock"] #stockRowsV9411Table td:nth-child(1){
          width:48px!important;min-width:48px!important;max-width:48px!important
        }
        [data-view="stock"] #stockRowsV9411Table th:nth-child(2),
        [data-view="stock"] #stockRowsV9411Table td:nth-child(2){left:48px!important;min-width:104px!important}
      }
    `;
    document.head.appendChild(s);
  }

  install();
})();