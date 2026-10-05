(() => {
  'use strict';
  const pendingResends = new Map();
  const money = value => '₹' + Number(value || 0).toLocaleString('en-IN', {maximumFractionDigits:2});
  function jpgPages(doc, images = new Map()) {
    const pages=[], lines=doc.lines||[], perPage=12, count=Math.ceil(lines.length/perPage);
    if(!count||count>20) throw Error('Receipt requires 1 to 20 pages.');
    const groups=new Map();let loose=0,boxes=0;
    for(const l of lines){const pack=Number(l.pack_pcs_per_box||0),q=Number(l.qty||0);const full=pack>0?Math.floor(q/pack):0;loose+=q-full*pack;boxes+=full;if(full)groups.set(pack,(groups.get(pack)||0)+full);}
    for(let page=0;page<count;page++) {
      const items=lines.slice(page*perPage,(page+1)*perPage), last=page===count-1;
      const canvas=document.createElement('canvas');canvas.width=1600;canvas.height=Math.max(1700,470+items.length*130+(last?Math.max(520,170+groups.size*40):100));
      const c=canvas.getContext('2d');if(!c)throw Error('JPG receipt could not be generated on this browser.');
      c.fillStyle='#fff';c.fillRect(0,0,canvas.width,canvas.height);
      const text=(v,x,y,size=20,bold=false,align='left')=>{c.fillStyle='#111';c.font=`${bold?'bold ':''}${size}px Arial, sans-serif`;c.textAlign=align;c.fillText(String(v??''),x,y);};
      const cell=(x,y,w,h,shade=false)=>{if(shade){c.fillStyle='#dceef5';c.fillRect(x,y,w,h);}c.strokeStyle='#78848a';c.strokeRect(x,y,w,h);};
      const wrap=(v,x,y,w,size=20,max=3)=>{
        c.font=`${size}px Arial, sans-serif`;const rows=[];let row='';
        for(const word of String(v||'—').split(/\s+/)){
          if(c.measureText(word).width>w){if(row){rows.push(row);row='';}let chunk='';for(const ch of word){if(chunk&&c.measureText(chunk+ch).width>w){rows.push(chunk);chunk=ch;}else chunk+=ch;}row=chunk;}
          else{const next=row?row+' '+word:word;if(row&&c.measureText(next).width>w){rows.push(row);row=word;}else row=next;}
        }
        if(row)rows.push(row);if(rows.length>max){rows.length=max;let last=rows[max-1];while(last&&c.measureText(last+'…').width>w)last=last.slice(0,-1);rows[max-1]=last+'…';}
        rows.forEach((r,i)=>text(r,x,y+i*25,size));
      };
      const kind=doc.document_kind||'PI';
      text(`${kind} No: ${doc.document_no}`,70,85,32,true);text('REDZED',1530,85,28,true,'right');
      text('Party Name: '+(doc.customer_name||''),70,140,23,true);text('Mobile Number: '+(doc.mobile||'—'),70,180,22);
      text('Created Date: '+(doc.created_at?new Date(doc.created_at).toLocaleDateString('en-IN'):'—'),70,218,22);
      if(doc.gstin)text('GSTIN: '+doc.gstin,70,254,20);
      if(doc.address)wrap(doc.address,70,285,1430,20,2);
      text(`Page ${page+1} / ${count}`,1530,345,20,false,'right');
      const widths=[55,125,345,150,175,90,165,220,140], labels=['Sr. No.','Image','Item Name','Size','Lot No.','QTY','Rate','Amount','Box Count'];let y=365;
      let x=70;labels.forEach((label,i)=>{cell(x,y,widths[i],65,true);wrap(label,x+8,y+27,widths[i]-16,18,2);x+=widths[i];});y+=65;
      items.forEach((l,i)=>{const pack=Number(l.pack_pcs_per_box||0),q=Number(l.qty||0),full=pack>0?Math.floor(q/pack):0,rem=q-full*pack;
        const vals=[page*perPage+i+1,'',l.item_name,l.size_text||'—',l.lot_no,q,money(l.net_rate),money(l.amount),[full?full+' BOX':'',rem?rem+' Loose':''].filter(Boolean).join(' + ')||'—'];
        x=70;vals.forEach((v,j)=>{cell(x,y,widths[j],130);if(j!==1)wrap(v,x+8,y+35,widths[j]-16,19,3);else{const img=images.get(l.image_url);if(img)c.drawImage(img,x+8,y+8,widths[j]-16,114);else text('—',x+55,y+65,20);}x+=widths[j];});y+=130;
      });
      cell(70,y,1465,48,true);text(last?'Total':'Page Total',80,y+32,21,true);text(items.reduce((n,l)=>n+Number(l.qty||0),0),960,y+32,21,true);text(money(items.reduce((n,l)=>n+Number(l.amount||0),0)),1390,y+32,21,true,'right');y+=95;
      if(last){
        const qx=70,qw=850, ax=970,aw=565;
        cell(qx,y,qw,44,true);text('QTY DETAILS',qx+qw/2,y+29,22,true,'center');
        const qwds=[160,160,160,175,195];let xx=qx;['Box Count','Box Qty (PCS)','Box Count (PCS)','TTL Qty (PCS)','Remarks'].forEach((v,i)=>{cell(xx,y+44,qwds[i],50,true);wrap(v,xx+7,y+67,qwds[i]-14,17,2);xx+=qwds[i];});
        let yy=y+94;const rows=[...groups].map(([pack,n])=>[n,pack,n+' Box',n*pack,'']);rows.push(['Loose','—','—',loose,''],['Total','—',boxes+' Box',doc.total_qty,'']);
        rows.forEach((r,ri)=>{xx=qx;r.forEach((v,i)=>{cell(xx,yy,qwds[i],40,ri===rows.length-1);text(v,xx+8,yy+27,19,ri===rows.length-1);xx+=qwds[i];});yy+=40;});
        cell(ax,y,aw,44,true);text('AMOUNT SUMMARY',ax+aw/2,y+29,22,true,'center');
        const totals=[['Grand Total Amount',doc.sub_total],[`Value Added (${Number(doc.value_added_pct||0)}%)`,doc.value_added_amount],['Freight',doc.freight_amount],['Other Charges',doc.other_charges]];if(Number(doc.gst_amount))totals.push(['GST',doc.gst_amount]);totals.push(['Round Off',doc.round_off],['Net Payable Amount',doc.grand_total]);
        totals.forEach(([label,v],i)=>{cell(ax,y+44+i*40,aw-180,40,i===totals.length-1);cell(ax+aw-180,y+44+i*40,180,40,i===totals.length-1);text(label,ax+8,y+71+i*40,20,i===totals.length-1);text(money(v),ax+aw-8,y+71+i*40,20,i===totals.length-1,'right');});
        y=Math.max(yy,y+44+totals.length*40)+45;cell(70,y,1465,75,true);text(`Grand Total Items ${lines.length}     Grand Total Qty (PCS) ${doc.total_qty}`,80,y+28,21,true);wrap('Remarks: '+(doc.dispatch_details||'—'),80,y+57,1440,19,1);
      }else text('Continued on next page',70,y,22);
      const data=canvas.toDataURL('image/jpeg',0.9);if(!data.startsWith('data:image/jpeg;base64,'))throw Error('Browser could not create a JPG receipt.');pages.push({base64:data.split(',')[1]});canvas.width=canvas.height=0;
    }
    return pages;
  }
  async function render(doc) {
    const images=new Map(),failed=[];
    await Promise.all([...new Set((doc.lines||[]).map(l=>l.image_url).filter(Boolean))].map(url=>new Promise(resolve=>{
      if(!/^https?:\/\//i.test(url)&&!/^data:image\/(jpeg|png|webp);base64,/i.test(url)){failed.push(url);return resolve();}
      const img=new Image();img.crossOrigin='anonymous';let done=false;const finish=ok=>{if(done)return;done=true;clearTimeout(timer);if(ok)images.set(url,img);else failed.push(url);resolve();};
      const timer=setTimeout(()=>finish(false),8000);img.onload=()=>finish(true);img.onerror=()=>finish(false);img.src=url;
    })));
    if(failed.length)throw Error('Item photo could not load for JPG. Check connection and retry; bill remains saved.');
    return jpgPages(doc,images);
  }
  async function share(piId,chatId,kind='PI') {
    const ctx=await RF853.rpc(kind==='RCI'?'rr_rci_customer_document_test71':'rr_pi_customer_document_test71',kind==='RCI'?{p_rci_id:piId,p_chat_id:chatId||null}:{p_pi_id:piId,p_chat_id:chatId||null});
    const pages=await render(ctx.document),d=ctx.document;
    const files=pages.map((p,i)=>{const bytes=Uint8Array.from(atob(p.base64),c=>c.charCodeAt(0));return new File([bytes],`${d.document_kind}-${String(d.document_no).replace(/[^a-z0-9_-]/gi,'_')}-${i+1}.jpg`,{type:'image/jpeg'});});
    const data={files,title:`${d.document_kind} ${d.document_no}`,text:`${d.document_kind} No. ${d.document_no} · ${d.customer_name} · ${d.total_qty} PCS · ${money(d.grand_total)}\nTeam REDZED`};
    if(navigator.canShare?.({files})&&navigator.share){await navigator.share(data);return {shared:true};}
    files.forEach(file=>{const url=URL.createObjectURL(file),a=document.createElement('a');a.href=url;a.download=file.name;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);});return {downloaded:true};
  }
  async function send(piId,chatId,progress=()=>{},options={}) {
    progress('Preparing saved invoice JPG…');
    const rci=options.kind==='RCI';const context=await RF853.rpc(rci?'rr_rci_customer_document_test71':'rr_pi_customer_document_test71',rci?{p_rci_id:piId,p_chat_id:chatId||null}:{p_pi_id:piId,p_chat_id:chatId||null});
    if (context.already_sent && !options.resend) return {sent:true,already_sent:true,message_ids:context.message_ids};
    const pages=await render(context.document);
    progress('Sending JPG and details to party chat…');
    const args={p_chat_id:context.chat_id,p_fingerprint:context.fingerprint,p_pages:pages};if(rci)args.p_rci_id=piId;else args.p_pi_id=piId;const key=(rci?'RCI':'PI')+':'+piId+':'+context.chat_id;if(options.resend){if(!pendingResends.has(key))pendingResends.set(key,options.requestId||crypto.randomUUID());args.p_request_id=pendingResends.get(key);}
    const result=await RF853.rpc(rci?'rr_rci_customer_document_send_test71':options.resend?'rr_pi_customer_document_resend_test71':'rr_pi_customer_document_send_test71',args);if(result?.sent)pendingResends.delete(key);return result;
  }
  window.RRPIReceipt71={send,jpgPages,render,share};
})();
