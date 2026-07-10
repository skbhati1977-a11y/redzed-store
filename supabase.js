async function saveProduct(product) {
  let result;

  if (product.id && product.id.trim() !== "") {
    const id = product.id;
    const updateData = { ...product };
    delete updateData.id;

    result = await supabaseClient
      .from("products")
      .update(updateData)
      .eq("id", id);
  } else {
    const insertData = { ...product };
    delete insertData.id;

    result = await supabaseClient
      .from("products")
      .insert([insertData]);
  }

  if (result.error) throw result.error;
  return result.data;
}
