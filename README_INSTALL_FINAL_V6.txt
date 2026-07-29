REDZED UNIVERSAL PRODUCTION — FINAL V6 VISUAL REFERENCE UPDATE

WHAT CHANGED
1. Lot No is now the main card header.
2. Art/Item appears as a smaller caption below Lot No.
3. Garment/Art image and Print reference images appear as thumbnails on every lot card.
4. The same thumbnails appear inside Production Submit and Alter/Remake/Damage screens.
5. Tap any thumbnail to open a mobile-friendly full-screen gallery.
6. Gallery supports left/right swipe, arrow keys, previous/next buttons and thumbnail scrolling.
7. Images are read from existing lot/product/print master URLs; files are not duplicated.
8. All V5 rules remain unchanged: mapped cut sizes, Alter quantity cap, initial fault image only, repair without image, Owner/Admin access, rate and submit controls.

INSTALL ORDER
1. Take a Supabase backup.
2. Run REDZED_UPM_FINAL_CONSOLIDATED_V6.sql in Supabase SQL Editor.
3. Replace real-universal-production-v72040.html in GitHub.
4. Replace real-universal-production-v72040.js in GitHub.
5. Upload redzed-alter-v5.js.
6. Keep/replace redzed-alter-v1.css with the supplied copy.
7. The HTML now loads redzed-alter-v5.js; old redzed-alter-v4.js is no longer required by this page.
8. Wait for GitHub Pages deployment and use Ctrl+Shift+R.

IMAGE MAPPING
The V6 SQL function reads existing image URL fields from:
- rr_upm_lot_board_v1 JSON
- Public product/print/art/style master tables matched by Art No

It recognizes common names such as garment_image_url, art_image_url, product_image_url,
front_image, print_image_urls, artwork_images, design images and logo/placement images.

If a thumbnail says “image not mapped”, the source master record does not contain a readable
HTTP/HTTPS image URL under a recognized image field. In that case update the Product/Print Master
mapping; do not upload the same image again in Production.

TEST
1. Open a lot with Product Master garment image and Print Master print images.
2. Confirm Lot No is the large header and Art/Item is the caption.
3. Confirm garment and print thumbnails appear on the lot card.
4. Open Production Submit and confirm the same references appear.
5. Open Alter/Remake/Damage and Register Alter; confirm the same references appear.
6. Test swipe in full-screen view on mobile.
