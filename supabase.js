// ===== REDZED SUPABASE FUNCTIONS =====

async function getProducts() {
  const { data, error } = await supabaseClient
    .from("products")
    .select("*")
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data || [];
}

async function saveProduct(product) {
  let result;

  const productId =
    typeof product.id === "string"
      ? product.id.trim()
      : product.id;

  if (productId) {
    const updateData = { ...product };
    delete updateData.id;

    result = await supabaseClient
      .from("products")
      .update(updateData)
      .eq("id", productId)
      .select();
  } else {
    const insertData = { ...product };
    delete insertData.id;

    result = await supabaseClient
      .from("products")
      .insert([insertData])
      .select();
  }

  if (result.error) throw result.error;
  return result.data || [];
}

async function deleteProduct(id) {
  if (!id) {
    throw new Error("Product ID missing");
  }

  const { error } = await supabaseClient
    .from("products")
    .delete()
    .eq("id", id);

  if (error) throw error;
}

async function uploadImage(file) {
  if (!file) return "";

  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_");
  const fileName = `${Date.now()}-${safeName}`;

  const { error } = await supabaseClient.storage
    .from("product-images")
    .upload(fileName, file, {
      upsert: false
    });

  if (error) throw error;

  const { data } = supabaseClient.storage
    .from("product-images")
    .getPublicUrl(fileName);

  return data.publicUrl;
}
