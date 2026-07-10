// REDZED V2 — Supabase database and storage functions

async function getProducts() {
  const { data, error } = await supabaseClient
    .from("products")
    .select("*")
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data || [];
}

function cleanProductPayload(product) {
  const payload = {
    art_no: product.art_no || "",
    product_name: product.product_name || "",
    category: product.category || "",
    fabric: product.fabric || "",
    sizes: product.sizes || "",
    pack_qty: product.pack_qty || "",
    rate:
      product.rate === "" ||
      product.rate === null ||
      product.rate === undefined
        ? null
        : Number(product.rate),
    stock: product.stock || "In Stock",
    description: product.description || "",
    image_url: product.image_url || "",
    image_urls: Array.isArray(product.image_urls)
      ? product.image_urls.filter(Boolean)
      : []
  };

  if (!payload.image_url && payload.image_urls.length) {
    payload.image_url = payload.image_urls[0];
  }

  return payload;
}

async function saveProduct(product) {
  const productId =
    typeof product.id === "string"
      ? product.id.trim()
      : product.id;

  const payload = cleanProductPayload(product);

  if (productId) {
    const { data, error } = await supabaseClient
      .from("products")
      .update(payload)
      .eq("id", productId)
      .select()
      .single();

    if (error) throw error;
    return data;
  }

  const { data, error } = await supabaseClient
    .from("products")
    .insert(payload)
    .select()
    .single();

  if (error) throw error;
  return data;
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

function safeFileName(name) {
  return String(name || "image")
    .toLowerCase()
    .replace(/[^a-z0-9._-]/g, "_");
}

async function uploadImage(file) {
  if (!file) return "";

  const path =
    "products/" +
    Date.now() +
    "-" +
    crypto.randomUUID() +
    "-" +
    safeFileName(file.name);

  const { error } = await supabaseClient.storage
    .from(STORAGE_BUCKET)
