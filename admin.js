// REDZED V2 — MULTIPLE IMAGE OWNER PANEL

const ADMIN_PIN_KEY = "redzed_admin_pin";
const ADMIN_SESSION_KEY = "redzed_admin_session";

const formFieldIds = [
  "id",
  "image_url",
  "product_name",
  "art_no",
  "category",
  "sizes",
  "pack_qty",
  "rate",
  "fabric",
  "stock",
  "description"
];

let adminProducts = [];
let existingImageUrls = [];
let selectedPreviewUrls = [];


/* =========================
   PIN AND LOGIN
========================= */

function getDefaultAdminPin() {
  if (typeof DEFAULT_ADMIN_PIN !== "undefined") {
    return DEFAULT_ADMIN_PIN;
  }

  if (typeof ADMIN_PIN !== "undefined") {
    return ADMIN_PIN;
  }

  if (
    typeof CFG !== "undefined" &&
    CFG.ADMIN_PIN
  ) {
    return CFG.ADMIN_PIN;
  }

  return "9654";
}


function getAdminPin() {
  return (
    localStorage.getItem(ADMIN_PIN_KEY) ||
    getDefaultAdminPin()
  );
}


function showAdmin() {
  document.getElementById("loginBox").hidden = true;
  document.getElementById("loginBox").style.display = "none";

  document.getElementById("adminBox").hidden = false;
  document.getElementById("adminBox").style.display = "block";

  loadAdminProducts();
}


function login() {
  const enteredPin = document
    .getElementById("pin")
    .value
    .trim();

  if (enteredPin !== getAdminPin()) {
    alert("Wrong PIN");
    return;
  }

  sessionStorage.setItem(
    ADMIN_SESSION_KEY,
    "1"
  );

  showAdmin();
}


function logout() {
  sessionStorage.removeItem(
    ADMIN_SESSION_KEY
  );

  location.reload();
}


function changePin() {
  const oldPin = document
    .getElementById("oldPin")
    .value
    .trim();

  const newPin = document
    .getElementById("newPin")
    .value
    .trim();

  if (oldPin !== getAdminPin()) {
    alert("Current PIN is incorrect");
    return;
  }

  if (!/^\d{4,}$/.test(newPin)) {
    alert(
      "New PIN minimum 4 digits होना चाहिए"
    );
    return;
  }

  localStorage.setItem(
    ADMIN_PIN_KEY,
    newPin
  );

  document.getElementById("oldPin").value = "";
  document.getElementById("newPin").value = "";

  alert("PIN changed successfully");
}


/* =========================
   FORM HELPERS
========================= */

function getValue(id) {
  const element = document.getElementById(id);

  if (!element) return "";

  return element.value.trim();
}


function setValue(id, value) {
  const element = document.getElementById(id);

  if (!element) return;

  element.value = value ?? "";
}


function parseStoredImages(product) {
  let images = [];

  if (
    Array.isArray(product?.image_urls)
  ) {
    images = product.image_urls.filter(Boolean);
  }

  if (
    images.length === 0 &&
    product?.image_url
  ) {
    images.push(product.image_url);
  }

  return [...new Set(images)];
}


/* =========================
   IMAGE PREVIEW
========================= */

function renderImagePreview() {
  const preview =
    document.getElementById("imagePreview");

  if (!preview) return;

  const combinedImages = [
    ...existingImageUrls.map((url) => ({
      url: url,
      existing: true
    })),

    ...selectedPreviewUrls.map((url) => ({
      url: url,
      existing: false
    }))
  ];

  if (combinedImages.length === 0) {
    preview.innerHTML = "";
    return;
  }

  preview.innerHTML = combinedImages
    .map((item, index) => {
      return `
        <div class="preview-item">

          <img
            src="${item.url}"
            alt="Product image ${index + 1}"
          >

          <span>
            ${
              index === 0
                ? "Cover"
                : index + 1
            }
          </span>

          ${
            item.existing
              ? `
                <button
                  type="button"
                  onclick="removeExistingImage('${encodeURIComponent(
                    item.url
                  )}')"
                  aria-label="Remove image"
                >
                  ×
                </button>
              `
              : ""
          }

        </div>
      `;
    })
    .join("");
}


function removeExistingImage(encodedUrl) {
  const url =
    decodeURIComponent(encodedUrl);

  existingImageUrls =
    existingImageUrls.filter(
      (imageUrl) => imageUrl !== url
    );

  renderImagePreview();
}


function clearSelectedPreviewUrls() {
  selectedPreviewUrls.forEach((url) => {
    URL.revokeObjectURL(url);
  });

  selectedPreviewUrls = [];
}


function handleFileSelection() {
  clearSelectedPreviewUrls();

  const fileInput =
    document.getElementById("imageFile");

  const files = Array.from(
    fileInput.files || []
  );

  selectedPreviewUrls = files.map(
    (file) => URL.createObjectURL(file)
  );

  renderImagePreview();

  const uploadStatus =
    document.getElementById("uploadStatus");

  if (uploadStatus) {
    uploadStatus.textContent =
      files.length > 0
        ? `${files.length} new image(s) selected`
        : "";
  }
}


/* =========================
   CLEAR FORM
========================= */

function clearForm() {
  formFieldIds.forEach((id) => {
    setValue(id, "");
  });

  setValue("stock", "In Stock");
  setValue("category", "");

  existingImageUrls = [];

  clearSelectedPreviewUrls();

  const imageUrlsField =
    document.getElementById("image_urls");

  if (imageUrlsField) {
    imageUrlsField.value = "";
  }

  const fileInput =
    document.getElementById("imageFile");

  if (fileInput) {
    fileInput.value = "";
  }

  const uploadStatus =
    document.getElementById("uploadStatus");

  if (uploadStatus) {
    uploadStatus.textContent = "";
  }

  const saveButton =
    document.getElementById("saveButton");

  if (saveButton) {
    saveButton.textContent =
      "Save product";
  }

  renderImagePreview();

  window.scrollTo({
    top: 0,
    behavior: "smooth"
  });
}


/* =========================
   SAVE PRODUCT
========================= */

async function submitProduct(event) {
  event.preventDefault();

  const saveButton =
    document.getElementById("saveButton");

  const uploadStatus =
    document.getElementById("uploadStatus");

  const fileInput =
    document.getElementById("imageFile");

  const files = fileInput.files || [];

  saveButton.disabled = true;
  saveButton.textContent = "Saving...";

  try {
    let uploadedUrls = [];

    if (files.length > 0) {
      uploadStatus.textContent =
        `Uploading 0 of ${files.length}...`;

      uploadedUrls =
        await uploadImages(
          files,
          (completed, total) => {
            uploadStatus.textContent =
              `Uploading ${completed} of ${total}...`;
          }
        );
    }

    const allImageUrls = [
      ...existingImageUrls,
      ...uploadedUrls
    ].filter(Boolean);

    const product = {
      id: getValue("id"),

      image_url:
        allImageUrls[0] ||
        getValue("image_url") ||
        "",

      image_urls: allImageUrls,

      product_name:
        getValue("product_name"),

      art_no:
        getValue("art_no"),

      category:
        getValue("category"),

      sizes:
        getValue("sizes"),

      pack_qty:
        getValue("pack_qty"),

      rate:
        getValue("rate"),

      fabric:
        getValue("fabric"),

      stock:
        getValue("stock"),

      description:
        getValue("description")
    };

    await saveProduct(product);

    uploadStatus.textContent =
      "Product saved successfully";

    alert(
      "Product saved successfully"
    );

    clearForm();

    await loadAdminProducts();

  } catch (error) {
    console.error(error);

    uploadStatus.textContent = "";

    alert(
      `Error: ${error.message}`
    );

  } finally {
    saveButton.disabled = false;
    saveButton.textContent =
      "Save product";
  }
}


/* =========================
   EDIT PRODUCT
========================= */

function editProduct(id) {
  const product =
    adminProducts.find(
      (item) => item.id === id
    );

  if (!product) return;

  formFieldIds.forEach((fieldId) => {
    setValue(
      fieldId,
      product[fieldId]
    );
  });

  existingImageUrls =
    parseStoredImages(product);

  clearSelectedPreviewUrls();

  const imageUrlsField =
    document.getElementById("image_urls");

  if (imageUrlsField) {
    imageUrlsField.value =
      JSON.stringify(existingImageUrls);
  }

  document
    .getElementById("imageFile")
    .value = "";

  const saveButton =
    document.getElementById("saveButton");

  saveButton.textContent =
    "Update product";

  renderImagePreview();

  window.scrollTo({
    top: 0,
    behavior: "smooth"
  });
}


/* =========================
   DELETE PRODUCT
========================= */

async function removeProduct(id) {
  const confirmation = confirm(
    "Delete this product permanently?"
  );

  if (!confirmation) return;

  try {
    await deleteProduct(id);

    await loadAdminProducts();

  } catch (error) {
    alert(
      `Error: ${error.message}`
    );
  }
}


/* =========================
   PRODUCT LIST
========================= */

function renderAdminProducts() {
  const searchInput =
    document.getElementById("adminSearch");

  const query = searchInput
    ? searchInput.value
        .trim()
        .toLowerCase()
    : "";

  const filteredProducts =
    adminProducts.filter((product) => {
      return JSON.stringify(product)
        .toLowerCase()
        .includes(query);
    });

  const status =
    document.getElementById("adminStatus");

  status.textContent =
    `${filteredProducts.length} product(s)`;

  const container =
    document.getElementById("adminProducts");

  container.innerHTML =
    filteredProducts
      .map((product) => {
        const images =
          parseStoredImages(product);

        const coverImage =
          images[0] || "";

        return `
          <article class="admin-product-card">

            <div class="admin-product-image">

              ${
                coverImage
                  ? `
                    <img
                      src="${coverImage}"
                      alt="${product.art_no || "Product"}"
                    >
                  `
                  : `
                    <div class="image-placeholder">
                      No image
                    </div>
                  `
              }

              <span>
                ${images.length}
                photo${images.length === 1 ? "" : "s"}
              </span>

            </div>


            <div class="admin-product-info">

              <small>
                ${
                  product.category ||
                  "Uncategorised"
                }
              </small>

              <h3>
                ${product.art_no || ""}
                ${product.product_name || ""}
              </h3>

              <p>
                ${product.fabric || "—"}
                ·
                ${product.sizes || "—"}
                ·
                ${product.pack_qty || "—"}
              </p>

              <strong>
                ${
                  product.rate
                    ? `₹${product.rate}`
                    : "Ask rate"
                }
              </strong>

            </div>


            <div class="admin-product-actions">

              <button
                class="secondary-btn"
                type="button"
                onclick="editProduct('${product.id}')"
              >
                Edit
              </button>

              <button
                class="danger-btn"
                type="button"
                onclick="removeProduct('${product.id}')"
              >
                Delete
              </button>

            </div>

          </article>
        `;
      })
      .join("");
}


/* =========================
   LOAD PRODUCTS
========================= */

async function loadAdminProducts() {
  const status =
    document.getElementById("adminStatus");

  status.textContent =
    "Loading products...";

  try {
    adminProducts =
      await getProducts();

    renderAdminProducts();

  } catch (error) {
    status.textContent =
      `Error: ${error.message}`;
  }
}


/* =========================
   EVENT LISTENERS
========================= */

const productForm =
  document.getElementById("productForm");

if (productForm) {
  productForm.addEventListener(
    "submit",
    submitProduct
  );
}


const imageFileInput =
  document.getElementById("imageFile");

if (imageFileInput) {
  imageFileInput.addEventListener(
    "change",
    handleFileSelection
  );
}


const adminSearchInput =
  document.getElementById("adminSearch");

if (adminSearchInput) {
  adminSearchInput.addEventListener(
    "input",
    renderAdminProducts
  );
}


/* =========================
   AUTO LOGIN SESSION
========================= */

if (
  sessionStorage.getItem(
    ADMIN_SESSION_KEY
  ) === "1"
) {
  showAdmin();
}
