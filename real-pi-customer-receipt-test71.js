(() => {
  'use strict';
  const money = value => '₹' + Number(value || 0).toLocaleString('en-IN', {maximumFractionDigits:2});
  function jpgPages(doc) {
    const pages = [], lines = doc.lines || [], perPage = 18;
    const count = Math.ceil(lines.length / perPage);
    if (!count || count > 20) throw Error('Receipt requires 1 to 20 pages.');
    for (let page = 0; page < count; page++) {
      const items = lines.slice(page * perPage, (page + 1) * perPage);
      const canvas = document.createElement('canvas');
      canvas.width = 1200; canvas.height = 760 + items.length * 94;
      const c = canvas.getContext('2d');
      if (!c) throw Error('JPG receipt could not be generated on this browser.');
      c.fillStyle = '#fff'; c.fillRect(0,0,canvas.width,canvas.height);
      const text = (value,x,y,size=23,bold=false,align='left') => {
        c.fillStyle = '#152334'; c.font = `${bold?'bold ':''}${size}px Arial, sans-serif`; c.textAlign = align;
        c.fillText(String(value ?? ''),x,y);
      };
      const rule = y => { c.strokeStyle = '#d3dae2'; c.beginPath(); c.moveTo(40,y); c.lineTo(1160,y); c.stroke(); };
      const wrap = (value,width,size=23,max=3) => {
        c.font = `${size}px Arial, sans-serif`;
        const words = String(value || '').replace(/\s+/g,' ').split(' '), rows=[]; let row='';
        for (const word of words) { const next = row ? row+' '+word : word; if (row && c.measureText(next).width > width) {rows.push(row);row=word;} else row=next; }
        if (row) rows.push(row);
        if (rows.length > max) { rows.length=max; rows[max-1]+='…'; }
        return rows;
      };
      text('REDZED',40,65,40,true); text(doc.document_kind==='CI'?'COMMERCIAL INVOICE':'PROFORMA INVOICE',1160,65,28,true,'right');
      text(doc.document_no,1160,103,26,true,'right');
      text(doc.customer_name,40,127,28,true);
      text([doc.mobile,doc.gstin && 'GSTIN '+doc.gstin].filter(Boolean).join(' · '),40,166,21);
      wrap(doc.address,1100,21,2).forEach((row,i)=>text(row,40,198+i*25,21));
      wrap('Dispatch / Remarks: '+(doc.dispatch_details||'—'),1100,20,2).forEach((row,i)=>text(row,40,253+i*25,20));
      text(`Page ${page+1} / ${count}`,1160,305,20,false,'right');rule(320);
      const cols=[40,590,700,800,940,1160];
      ['LOT / ITEM','PCS','GROSS ₹','DISC ₹/PCS','NET ₹','AMOUNT ₹'].forEach((label,i)=>text(label,cols[i],351,18,true,i===5?'right':'left'));
      let y=375;
      for (const item of items) {
        text(item.lot_no,40,y+27,25,true);
        wrap(item.item_name,490,20,2).forEach((row,i)=>text(row,40,y+55+i*23,20));
        text(item.qty,590,y+30,22);text(money(item.gross_rate),700,y+30,22);
        text(money(item.discount),800,y+30,22);text(money(item.net_rate),940,y+30,22);text(money(item.amount),1160,y+30,22,true,'right');
        rule(y+87);y+=94;
      }
      y+=35;
      if (page===count-1) {
        const totals=[['Subtotal',doc.sub_total],[`Value Added (${Number(doc.value_added_pct||0)}%)`,doc.value_added_amount],['Freight',doc.freight_amount],['Other Charges',doc.other_charges],['GST',doc.gst_amount],['Round Off',doc.round_off],['TOTAL',doc.grand_total]];
        totals.forEach(([label,value],i)=>{text(label,740,y+i*38,i===6?28:22,i===6);text(money(value),1160,y+i*38,i===6?28:22,i===6,'right');});
        text(`Total Items ${lines.length} · Total Qty ${doc.total_qty} PCS`,40,y+250,22,true);
      } else { text('Continued on next page',40,y,22); }
      text('REDZED · Customer invoice receipt',40,canvas.height-30,18);
      const data = canvas.toDataURL('image/jpeg',0.9);
      if (!data.startsWith('data:image/jpeg;base64,')) throw Error('Browser could not create a JPG receipt.');
      pages.push({base64:data.split(',')[1]});
      canvas.width=canvas.height=0;
    }
    return pages;
  }
  async function send(piId,chatId,progress=()=>{}) {
    progress('Preparing saved invoice JPG…');
    const context=await RF853.rpc('rr_pi_customer_document_test71',{p_pi_id:piId,p_chat_id:chatId||null});
    if (context.already_sent) return {sent:true,already_sent:true,message_ids:context.message_ids};
    const pages=jpgPages(context.document);
    progress('Sending JPG and details to party chat…');
    return RF853.rpc('rr_pi_customer_document_send_test71',{p_pi_id:piId,p_chat_id:context.chat_id,p_fingerprint:context.fingerprint,p_pages:pages});
  }
  window.RRPIReceipt71={send,jpgPages};
})();
