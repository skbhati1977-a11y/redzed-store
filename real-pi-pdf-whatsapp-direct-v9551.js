(()=>{
  'use strict';
  if(window.__RR_PI_PDF_WA_V9551__)return;
  window.__RR_PI_PDF_WA_V9551__=true;
  const $=id=>document.getElementById(id);
  const moneyText=id=>($(id)?.textContent||'₹0').trim();
  const clean=v=>String(v||'').trim();
  const phone=value=>{let n=clean(value).replace(/[^0-9]/g,'');if(n.length===10)n='91'+n;return /^[1-9][0-9]{7,14}$/.test(n)?n:'';};
  const piNo=()=>clean($('piNo')?.textContent).replace(/^PI No\.\s*/i,'');
  const isSaved=()=>!!piNo()&&piNo()!=='—';
  const caption=()=>`PI No. ${piNo()}\nPI attached.\nTeam REDZED`;
  function update(){const b=$('rrPiPdfWa');if(b)b.disabled=!isSaved();}
  function mount(){
    const save=$('save');if(!save||$('rrPiWaBox'))return;
    const card=save.closest('.card')||save.parentElement;
    const box=document.createElement('div');box.id='rrPiWaBox';box.className='rr-pi-wa-box';
    box.innerHTML=`<button id="rrPiPdfWa" class="btn rr-pi-wa-btn" type="button" disabled>WHATSAPP</button>`;
    card.appendChild(box);$('rrPiPdfWa').onclick=run;
    const pn=$('piNo');if(pn)new MutationObserver(update).observe(pn,{childList:true,subtree:true,characterData:true});update();
  }
  async function customerMobile(){
    const tr=$('rows')?.querySelector('tr');if(!tr)throw Error('PI me Lot row nahi mili.');
    const lot=clean(tr.children[2]?.textContent);if(!lot)throw Error('Lot No. missing.');
    const customer=clean($('customer')?.value);
    const c=await RF853.rpc('rr_pi_lot_context_v9517',{p_lot_no:lot,p_customer_name:customer,p_data_mode:'TEST'});
    const n=phone(c?.mobile||c?.customer_mobile||c?.whatsapp_mobile||c?.phone);if(!n)throw Error('Customer WhatsApp mobile mapped nahi mila.');return n;
  }
  function rows(){return [...($('rows')?.querySelectorAll('tr')||[])].map((tr,i)=>{const c=tr.children;const val=idx=>c[idx]?.querySelector('input')?.value||clean(c[idx]?.textContent);return [String(i+1),clean(c[2]?.textContent),clean(c[3]?.textContent),clean(c[4]?.textContent),val(5),clean(c[10]?.textContent),clean(c[11]?.textContent)];});}
  function makePdf(){
    const J=window.jspdf?.jsPDF;if(!J)throw Error('PDF library load nahi hui.');const doc=new J({orientation:'landscape',unit:'mm',format:'a4'});
    const no=piNo(),customer=clean($('customer')?.value),dispatch=clean($('dispatch')?.value),date=clean($('piDate')?.textContent),remarks=clean($('remarks')?.value);
    doc.setFont('helvetica','bold');doc.setFontSize(17);doc.text('REDZED',14,15);doc.setFontSize(14);doc.text(`PI ${no}`,283,15,{align:'right'});
    doc.setFont('helvetica','normal');doc.setFontSize(10);doc.text(`Date: ${date}`,14,22);doc.text(`Customer: ${customer}`,14,28);if(dispatch)doc.text(`Dispatch: ${dispatch}`,14,34,{maxWidth:268});
    const y=dispatch?40:34;if(typeof doc.autoTable!=='function')throw Error('PDF table library load nahi hui.');
    doc.autoTable({startY:y,head:[['#','Lot No.','Category','Size','Qty','Final Rate','Amount']],body:rows(),styles:{fontSize:9,cellPadding:2},headStyles:{fillColor:[35,45,58]},columnStyles:{0:{cellWidth:10},1:{cellWidth:32},2:{cellWidth:72},3:{cellWidth:35},4:{cellWidth:24},5:{cellWidth:35},6:{cellWidth:42}}});
    let ty=(doc.lastAutoTable?.finalY||y)+8;doc.setFontSize(10);doc.setFont('helvetica','normal');
    const totals=[['Gross Amount',moneyText('gross')],['Value Added',moneyText('valueAmt')],['Freight',moneyText('freightAmt')],['Other Charges',moneyText('otherAmt')],['Round Off',moneyText('round')],['TTL Amount',moneyText('total')]];
    totals.forEach(([k,v])=>{doc.text(k,220,ty);doc.text(v,283,ty,{align:'right'});ty+=6;});
    doc.setFont('helvetica','bold');doc.text(`TTL Items ${clean($('items')?.textContent)}  |  TTL Qty ${clean($('qty')?.textContent)}`,14,ty);
    if(remarks){ty+=7;doc.setFont('helvetica','normal');doc.text(`Remarks: ${remarks}`,14,ty,{maxWidth:185});}
    const fileName=`PI-${no.replace(/[^A-Za-z0-9_-]/g,'-')}.pdf`;return {doc,fileName};
  }
  async function run(){
    if(!isSaved())return;const btn=$('rrPiPdfWa');btn.disabled=true;
    try{
      const {doc,fileName}=makePdf();const blob=doc.output('blob');const file=new File([blob],fileName,{type:'application/pdf'});
      const shareData={title:`PI ${piNo()}`,text:caption(),files:[file]};
      if(navigator.share&&(!navigator.canShare||navigator.canShare({files:[file]}))){
        await navigator.share(shareData);
      }else{
        doc.save(fileName);
        const mobile=await customerMobile();window.open(`https://wa.me/${mobile}?text=${encodeURIComponent(caption())}`,'_blank','noopener,noreferrer');
        const m=$('msg');if(m)m.textContent='Browser file-share support nahi karta; PDF download hui hai.';
      }
    }catch(e){if(e?.name!=='AbortError'){const m=$('msg');if(m)m.textContent=e?.message||'WhatsApp share failed.';}}
    finally{btn.disabled=!isSaved();}
  }
  const style=document.createElement('style');style.textContent='.rr-pi-wa-box{margin-top:14px;padding-top:12px;border-top:1px solid #33445a}.rr-pi-wa-btn{width:100%;background:#18794e;border-color:#2ea66b}.rr-pi-wa-btn:disabled{opacity:.45;cursor:not-allowed}';document.head.appendChild(style);
  addEventListener('DOMContentLoaded',mount);mount();
})();