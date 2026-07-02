// ===== REDZED SUPABASE FUNCTIONS =====

async function getProducts() {
  const { data, error } = await supabaseClient
    .from("products")
    .select("*")
    .order("id", { ascending: false });

  if (error) throw error;
  return data || [];
}

async function saveProduct(product) {
  let result;

  if (product.id) {
    const id = product.id;
    delete product.id;

    result = await supabaseClient
      .from("products")
      .update(product)
      .eq("id", id);
  } else {
    result = await supabaseClient
      .from("products")
      .insert([product]);
  }

  if (result.error) throw result.error;
  return result.data;
}

async function deleteProduct(id) {
  const { error } = await supabaseClient
    .from("products")
    .delete()
    .eq("id", id);

  if (error) throw error;
}

async function uploadImage(file) {
  if (!file) return "";

  const fileName = Date.now() + "-" + file.name;

  const { error } = await supabaseClient.storage
    .from("product-images")
    .upload(fileName, file, {
      upsert: true
    });

  if (error) throw error;

  const { data } = supabaseClient.storage
    .from("product-images")
    .getPublicUrl(fileName);

  return data.publicUrl;
}
