/* ==========================================================
   REDZED ERP
   File      : app.js
   Module    : Dealer Catalog
   Version   : v719.3
   Status    : Production Certified
   Purpose   : Product Loading, Search, Filter & Rendering
========================================================== */


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

    return (value ?? "").toString();

}


/* ==========================================================
   Load Categories
========================================================== */

async function loadCategories() {

    const { data, error } = await supabaseClient
        .from("categories")
        .select("*")
        .order("name");

    if (error) {
        console.warn(error);
        return;
    }

    categories = data || [];

    const select = document.getElementById("categoryFilter");

    select.innerHTML =
        '<option value="all">All Categories</option>' +
        categories
            .map(category => `
                <option value="${category.id}">
                    ${category.name}
                </option>
            `)
            .join("");

}


/* ==========================================================
   Load Products
========================================================== */

async function loadProducts() {

    const container = document.getElementById("products");

    container.innerHTML = "<p>Loading products...</p>";

    const { data, error } = await supabaseClient
        .from("products")
        .select("*, categories(name)")
        .order("created_at", {
            ascending: false
        });

    if (error) {

        container.innerHTML =
            "<p>Supabase config अभी बाकी है. config.js में URL और anon key डालें.</p>";

        return;
    }

    products = data || [];

    render();

}


/* ==========================================================
   Render Product List
========================================================== */

function render() {

    const keyword =
        document.getElementById("search")
            .value
            .toLowerCase();

    const category =
        document.getElementById("categoryFilter").value;

    const stock =
        document.getElementById("stockFilter").value;


    const rows = products.filter(product => {

        const text = [

            product.item_name,
            product.art_no,
            product.fabric,
            product.size,
            product.colors,
            product.description,
            product.categories?.name

        ]
            .join(" ")
            .toLowerCase();

        return (

            text.includes(keyword)

            &&

            (
                category === "all"

                ||

                String(product.category_id) === category
            )

            &&

            (
                stock === "all"

                ||

                (
                    stock === "yes"
                        ? product.in_stock
                        : !product.in_stock
                )
            )

        );

    });


    document.getElementById("products").innerHTML =

        rows.map(product => {

            const order = encodeURIComponent(

                `REDZED order enquiry
Item: ${safe(product.item_name)}
Art: ${safe(product.art_no)}
Size: ${safe(product.size)}
Dealer Price : ₹${safe(product.dealer_price)}
Fabric: ${safe(product.fabric)}`

            );

            return `

<article class="card">

    <img
        src="${product.main_image || placeholder}"
        alt="${safe(product.item_name)}">

    <div class="card-body">

        <span class="badge">
            ${product.categories?.name || "Product"}
        </span>

        <h3>
            ${safe(product.item_name)}
        </h3>

        <p>
            Art : ${safe(product.art_no) || "-"}
        </p>

        <p>
            Size : ${safe(product.size) || "-"}
            •
            Pcs : ${safe(product.pcs) || "-"}
        </p>

        <p>
            Fabric : ${safe(product.fabric) || "-"}
        </p>

        <p>
            Colors : ${safe(product.colors) || "-"}
        </p>

        <div class="price">
    ₹${safe(product.dealer_price) || "-"}
</div>

     <a class="wa" href="https://wa.me/91${CFG.DEFAULT_WHATSAPP?.number || ''}?text=${order}">
    WhatsApp Order
</a>
            

    </div>

</article>

`;

        }).join("")

        ||

        "<p>No products found.</p>";

}


/* ==========================================================
   Update WhatsApp UI
========================================================== */

function updateWhatsAppUI() {

    if (!CFG.DEFAULT_WHATSAPP) return;

    const number = CFG.DEFAULT_WHATSAPP.number;

    const footer = document.querySelector(".wa-text");
    if (footer) {
        footer.textContent = number;
    }

    const headerLink = document.querySelector(".wa-link");
    if (headerLink) {
        headerLink.href = `https://wa.me/91${number}`;
    }

}
/* ==========================================================
   Event Binding
========================================================== */

[
    "search",
    "categoryFilter",
    "stockFilter"

].forEach(id => {

    document
        .getElementById(id)
        .addEventListener("input", render);

});


/* ==========================================================
   Application Startup
========================================================== */


async function initializeApp() {

    await loadSettings();

    await loadWhatsAppNumbers();

    updateWhatsAppUI();

    await loadCategories();

    await loadProducts();

}

initializeApp();