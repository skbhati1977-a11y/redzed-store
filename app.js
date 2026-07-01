let allProducts = [];
let selectedCategory = 'all';

async function loadCategories(){
  const { data } = await supabaseClient.from('categories').select('*').order('name');
  const box = document.getElementById('categories');
  box.innerHTML = '<button class="chip active" data-id="all">All</button>' + (data||[]).map(c=>`<button class="chip" data-id="${c.id}">${c.name}</button>`).join('');
  box.querySelectorAll('.chip').forEach(btn=>btn.onclick=()=>{selectedCategory=btn.dataset.id; document.querySelectorAll('.chip').forEach(b=>b.classList.remove('active')); btn.classList.add('active'); render();});
}
async function loadProducts(){
  const { data, error } = await supabaseClient.from('products').select('*, categories(name)').order('created_at',{ascending:false});
  if(error){ document.getElementById('products').innerHTML='<p>Connect Supabase config first.</p>'; return; }
  allProducts=data||[]; render();
}
function render(){
  const q=document.getElementById('search').value.toLowerCase();
  const items=allProducts.filter(p => (selectedCategory==='all'||String(p.category_id)===selectedCategory) && [p.item_name,p.art_no,p.fabric,p.size].join(' ').toLowerCase().includes(q));
  document.getElementById('products').innerHTML = items.map(p=>{
    const msg=encodeURIComponent(`Order enquiry: ${p.item_name || ''} ${p.art_no || ''} Rate ${p.rate || ''}`);
    return `<article class="card"><img src="${p.main_image||'https://placehold.co/600x700?text=REDZED'}"/><div class="card-body"><h3>${p.item_name}</h3><p>Art: ${p.art_no||'-'}</p><p>Size: ${p.size||'-'} | Pcs: ${p.pcs||'-'}</p><p>Fabric: ${p.fabric||'-'}</p><strong>₹${p.rate||'-'}</strong><a class="wa" href="https://wa.me/91${WHATSAPP_NUMBER}?text=${msg}">WhatsApp Order</a></div></article>`;
  }).join('') || '<p>No products found.</p>';
}
document.getElementById('search').addEventListener('input', render);
loadCategories(); loadProducts();
