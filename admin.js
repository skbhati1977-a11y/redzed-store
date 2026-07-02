function getAdminPin(){
  return localStorage.getItem("redzed_admin_pin") || CFG.ADMIN_PIN || "9654";
}
function changePin(){
  const oldPin = document.getElementById("oldPin").value.trim();
  const newPin = document.getElementById("newPin").value.trim();
  if(oldPin !== getAdminPin()){ alert("Old PIN wrong"); return; }
  if(newPin.length < 4){ alert("New PIN minimum 4 digits rakhiye"); return; }
  localStorage.setItem("redzed_admin_pin", newPin);
  document.getElementById("oldPin").value = "";
  document.getElementById("newPin").value = "";
  alert("PIN changed successfully");
}
const fields = ["id","image_url","art_no","product_name","category","fabric","sizes","pack_qty","rate","stock","description"];
let products = [];
function login(){
  if(document.getElementById("pin").value === getAdminPin()){
    sessionStorage.setItem("redzed_admin","1");
    document.getElementById("loginBox").style.display="none";
    document.getElementById("adminBox").style.display="block";
    loadAdmin();
  } else alert("Wrong PIN");
}
if(sessionStorage.getItem("redzed_admin")==="1"){
  document.getElementById("loginBox").style.display="none";
  document.getElementById("adminBox").style.display="block";
  loadAdmin();
}
function v(id){ return document.getElementById(id).value.trim(); }
function s(id,val){ document.getElementById(id).value = val ?? ""; }
function clearForm(){ fields.forEach(f=>s(f,"")); s("stock","In Stock"); document.getElementById("imageFile").value=""; }
document.getElementById("productForm").addEventListener("submit", async e => {
  e.preventDefault();
  const btn = e.submitter; btn.disabled=true; btn.textContent="Saving...";
  try{
    let image_url = v("image_url");
    const file = document.getElementById("imageFile").files[0];
    if(file) image_url = await uploadImage(file);
    const p = {}; fields.forEach(f => p[f] = v(f)); p.image_url = image_url;
    await saveProduct(p);
    alert("Product saved live");
    clearForm(); await loadAdmin();
  }catch(err){ alert("Error: " + err.message); }
  btn.disabled=false; btn.textContent="Save Product";
});
async function loadAdmin(){
  try{ products = await getProducts(); document.getElementById("adminStatus").textContent = `${products.length} products`; renderAdmin(); }
  catch(e){ document.getElementById("adminStatus").textContent = "Error: " + e.message; }
}
function editProduct(id){ const p = products.find(x=>x.id===id); fields.forEach(f=>s(f,p[f])); scrollTo(0,0); }
async function removeProduct(id){ if(!confirm("Delete product?")) return; try{ await deleteProduct(id); await loadAdmin(); }catch(e){ alert(e.message); } }
function renderAdmin(){
  document.getElementById("adminProducts").innerHTML = products.map(p => `<div class="row">${p.image_url?`<img src="${p.image_url}">`:`<img>`}<div><b>${p.art_no || ""} - ${p.product_name || ""}</b><br><small>${p.category||""} | ${p.fabric||""} | ${p.sizes||""} | ₹${p.rate||""} | ${p.stock||""}</small></div><div><button class="btn" onclick="editProduct('${p.id}')">Edit</button><button class="btn danger" onclick="removeProduct('${p.id}')">Delete</button></div></div>`).join("");
}