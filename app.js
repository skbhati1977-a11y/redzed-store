 /******************************************************************
 * REDZED Dealer Catalog
 * File        : app.js
 * Recovery ID : RR-006-01
 * Version     : 720.0
 * Status      : PRODUCTION
 * Purpose     : Product Loading & Helpers
 ******************************************************************/

/* ==========================================================
   Global Variables
========================================================== */

let products = [];
let categories = [];

const placeholder =
    "https://placehold.co/800x1000/151515/d6a33a?text=REDZED";


/* ==========================================================
   Helper Functions
========================================================== */

function safe(value) {

    return (value ?? "").toString().trim();

}


/* ==========================================================
   Parse Image Array
========================================================== */

function getImages(product) {

    let images = [];

    try {

        if (Array.isArray(product.image_urls)) {

            images = product.image_urls;

        }

        else if (typeof product.image_urls === "string") {

            images = JSON.parse(product.image_urls);

        }

    }

    catch (e) {

        images = [];

    }

    if (!images.length && product.image_url) {

        images.push(product.image_url);

    }

    if (!images.length) {

        images.push(placeholder);

    }

    return images;

}


/* ==========================================================
   Build Category List
========================================================== */

function buildCategories() {

    categories = [

        ...new Set(

            products

                .map(product => safe(product.category))

                .filter(Boolean)

        )

    ].sort();

    const select =
        document.getElementById("categoryFilter");

    select.innerHTML =

        `<option value="all">
            All Categories
        </option>`

        +

        categories.map(category =>

            `<option value="${category}">
                ${category}
            </option>`

        ).join("");

}


/* ==========================================================
   Load Products
========================================================== */

async function loadProducts() {

    const container =
        document.getElementById("products");

    container.innerHTML =
        "<p>Loading Products...</p>";

    const { data, error } =
        await supabaseClient

            .from("products")

            .select("*")

            .order("created_at", {

                ascending: false

            });

    if (error) {

        console.error(error);

        container.innerHTML =

            `<div style="
                color:#ff4d4f;
                padding:20px;
                border:1px solid #ff4d4f;
                border-radius:8px;
                white-space:pre-wrap;
            ">

${error.message}

</div>`;

        return;

    }

    products = data || [];

    buildCategories();

    render();

}

    products = data || [];

    buildCategories();

    render();

}

/* ==========================================================
   Render Products
========================================================== */

function render() {

    const container =
        document.getElementById("products");

    const keyword =
        safe(document.getElementById("search").value).toLowerCase();

    const category =
        safe(document.getElementById("categoryFilter").value);

    let filtered = products.filter(product => {

        const text = [

            product.product_name,
            product.art_no,
            product.category,
            product.fabric,
            product.sizes,
            product.description

        ]

        .join(" ")

        .toLowerCase();

        const matchSearch =
            text.includes(keyword);

        const matchCategory =
            category === "all"
            || safe(product.category) === category;

        return matchSearch && matchCategory;

    });

    if (!filtered.length) {

        container.innerHTML =

        `
        <div class="empty">

            No Products Found

        </div>
        `;

        return;

    }

    container.innerHTML =

        filtered.map(product => productCard(product)).join("");

}


/* ==========================================================
   Product Card
========================================================== */

function productCard(product) {

    const images =
        getImages(product);

    const stock =
        safe(product.stock);

    const dealerPrice =
        product.dealer_price ?? product.rate;

    return `

<div class="product-card">

<div class="image-section">

<img

id="img-${product.id}"

src="${images[0]}"

alt="${product.product_name}"

class="main-image"

>

</div>

<div class="content">

<h3>

${safe(product.product_name)}

</h3>

<p>

<b>Art :</b>

${safe(product.art_no)}

</p>

<p>

<b>Category :</b>

${safe(product.category)}

</p>

<p>

<b>Fabric :</b>

${safe(product.fabric)}

</p>

<p>

<b>Sizes :</b>

${safe(product.sizes)}

</p>

<p>

<b>Pack Qty :</b>

${safe(product.pack_qty)}

</p>

<p class="price">

₹ ${dealerPrice}

</p>

<p class="stock">

${stock}

</p>

${thumbnailStrip(product)}

${whatsappButton(product)}

</div>

</div>

`;

}


/* ==========================================================
   Thumbnail Strip
========================================================== */

function thumbnailStrip(product) {

    const images =
        getImages(product);

    if (images.length <= 1) {

        return "";

    }

    return `

<div class="thumb-strip">

${images.map(img =>

`

<img

src="${img}"

class="thumb"

onclick="changeImage('${product.id}','${img}')"

>

`

).join("")}

</div>

`;

}


/* ==========================================================
   Change Main Image
========================================================== */

function changeImage(id,image){

    document
        .getElementById(`img-${id}`)
        .src = image;

}

/* ==========================================================
   WhatsApp Button
========================================================== */

function whatsappButton(product) {

    if (!CFG.DEFAULT_WHATSAPP) {

        return "";

    }

    const dealerPrice =
        product.dealer_price ?? product.rate;

    const message = encodeURIComponent(

`Hello,

I want to order this product.

Product : ${safe(product.product_name)}

Art No : ${safe(product.art_no)}

Category : ${safe(product.category)}

Fabric : ${safe(product.fabric)}

Sizes : ${safe(product.sizes)}

Dealer Price : ₹ ${dealerPrice}`

    );

    return `

<a

class="wa-btn"

target="_blank"

href="https://wa.me/${CFG.DEFAULT_WHATSAPP.number}?text=${message}"

>

WhatsApp Order

</a>

`;

}


/* ==========================================================
   WhatsApp UI
========================================================== */

function updateWhatsAppUI() {

    const container =
        document.getElementById("whatsappList");

    if (!container) return;

    if (!CFG.WHATSAPP.length) {

        container.innerHTML = "";

        return;

    }

    container.innerHTML =

        CFG.WHATSAPP.map(item =>

`

<a

class="wa-contact"

target="_blank"

href="https://wa.me/${item.number}"

>

${item.name}

</a>

`

        ).join("");

}


/* ==========================================================
   Search Events
========================================================== */

document

.getElementById("search")

.addEventListener(

"input",

render

);


/* ==========================================================
   Category Events
========================================================== */

document

.getElementById("categoryFilter")

.addEventListener(

"change",

render

);


/* ==========================================================
   Initialize App
========================================================== */

async function initializeApp() {

    await loadSettings();

    updateWhatsAppUI();

    await loadProducts();

}


/* ==========================================================
   Start Application
========================================================== */

initializeApp();