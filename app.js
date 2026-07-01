let products = [];
let categories = [];
const placeholder = 'https://placehold.co/800x1000/151515/d6a33a?text=REDZED';
function safe(v){return (v ?? '').toString();}
async function loadCategories(){
  const {data,error}=await supabaseClient.from('categories').select('*').order('name');
  if(error){console.warn(error);return;}
  categories=data||[];
  const s=document.getElementById('categoryFilter');
  s.innerHTML='<option value="all">All Categories</option>'+categories.map(c=>`<option value="${c.id}">${c.name}</option>`).join('');
}
async function loadProducts(){
  const box=document.getElementById('products');
  box.innerHTML='<p>Loading products...</p>';
  const {data,error}=await supabaseClient.from('products').select('*, categories(name)').order('created_at',{ascending:false});
  if(error){box.innerHTML='<p>Supabase config अभी बाकी है. config.js में URL और anon key डालें.</p>';return;}
  products=data||[]; render();
}
function render(){
  const q=document.getElementById('search').value.toLowerCase();
  const cat=document.getElementById('categoryFilter').value;
  const stock=document.getElementById('stockFilter').value;
  const rows=products.filter(p=>{
    const text=[p.item_name,p.art_no,p.fabric,p.size,p.colors,p.description,p.categories?.name].join(' ').toLowerCase();
    return text.includes(q) && (cat==='all'||String(p.category_id)===cat) && (stock==='all'||(stock==='yes'?p.in_stock:!p.in_stock));
  });
  document.getElementById('products').innerHTML=rows.map(p=>{
    const order=encodeURIComponent(`REDZED order enquiry\nItem: ${safe(p.item_name)}\nArt: ${safe(p.art_no)}\nSize: ${safe(p.size)}\nRate: ${safe(p.rate)}\nFabric: ${safe(p.fabric)}`);
    return `<article class="card"><img src="${p.main_image||placeholder}" alt="${safe(p.item_name)}"><div class="card-body"><span class="badge">${p.categories?.name||'Product'}</span><h3>${safe(p.item_name)}</h3><p>Art: ${safe(p.art_no)||'-'}</p><p>Size: ${safe(p.size)||'-'} • Pcs: ${safe(p.pcs)||'-'}</p><p>Fabric: ${safe(p.fabric)||'-'}</p><p>Colors: ${safe(p.colors)||'-'}</p><div class="price">₹${safe(p.rate)||'-'}</div><a class="wa" href="https://wa.me/91${WHATSAPP_NUMBER}?text=${order}">WhatsApp Order</a></div></article>`;
  }).join('') || '<p>No products found.</p>';
}
['search','categoryFilter','stockFilter'].forEach(id=>document.getElementById(id).addEventListener('input',render));
loadCategories().then(loadProducts);
