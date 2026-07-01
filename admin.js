async function loadCategories(){
  const { data } = await supabaseClient.from('categories').select('*').order('name');
  document.getElementById('categorySelect').innerHTML=(data||[]).map(c=>`<option value="${c.id}">${c.name}</option>`).join('');
}
async function uploadPhoto(file){
  if(!file) return '';
  const ext=file.name.split('.').pop();
  const path=`${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;
  const { error } = await supabaseClient.storage.from('products').upload(path, file);
  if(error) throw error;
  const { data } = supabaseClient.storage.from('products').getPublicUrl(path);
  return data.publicUrl;
}
document.getElementById('productForm').addEventListener('submit', async (e)=>{
  e.preventDefault();
  const msg=document.getElementById('msg'); msg.textContent='Saving...';
  try{
    const fd=new FormData(e.target);
    const main_image=await uploadPhoto(fd.get('photo'));
    const row={
      item_name: fd.get('item_name'), art_no: fd.get('art_no'), category_id: Number(fd.get('category_id')),
      size: fd.get('size'), pcs: fd.get('pcs')?Number(fd.get('pcs')):null, rate: fd.get('rate')?Number(fd.get('rate')):null,
      fabric: fd.get('fabric'), description: fd.get('description'), main_image, featured: fd.get('featured')==='on', in_stock:true
    };
    const { error } = await supabaseClient.from('products').insert(row);
    if(error) throw error;
    msg.textContent='Product saved successfully.'; e.target.reset();
  }catch(err){ msg.textContent='Error: '+err.message; }
});
loadCategories();
