# TEST71 CB Requirement Receipt V2

Implemented 2026-10-04, based on TEST71 HEAD `94a29ca697477388822c2f541baa43c99362a020`.
Scope: CB requirement presentation, file sharing, reference viewer and share-event audit. No Appx/Cutting calculations, allocations, accounts, master assignments or purchase quantities are changed.

## User flow

CB requirement button → `RECEIPT · SHARE` → saved quantity refresh → receipt preview → `SHARE JPG + PHOTOS` or `SHARE PDF` → device share chooser → choose WhatsApp/contact/group.

The receipt has a stable reference number, date/time, revision and send type, CB/item, mode, mapped supplier when present, required quantity, separate Appx and Cutting PCS, difference, profile details and numbered named reference images. It is a requirement/order slip, not a payment receipt or tax invoice.

App receipt thumbnails open the large-image viewer with next/previous, zoom, open original and individual image share. PDF thumbnails have internal links to embedded full-image pages; those pages have a back-to-receipt link. These embedded PDF images remain available offline. A flat JPG cannot contain clickable image links: the JPG share includes the separate numbered reference photos for opening individually.

All currently enrolled Art, Print, Sticker, Metal ID and colour images are collected for the relevant profiles. Material media are included when the material category links to a material master with an image. Enrolled accessories are included even on a MATERIAL receipt. DUE/NA accessory assignments are not invented. Identical image URLs are deduplicated with their labels retained. There is no eight-image truncation. Source PDF references are preserved as additional PDF attachments, not converted into a fake image.

## Sharing fixes

- The CB-only capture handler is installed by the existing action-return script before inline CB handlers. It intercepts requirement buttons and disconnects the old direct/text-only callback. Other forms keep the original return behavior.
- The existing autosave/refresh handler is awaited before reading receipt data.
- All asynchronous data loading and file preparation finishes before the final Share button click. The native share call is synchronous with that fresh click.
- JPG and PDF use separate, homogeneous file batches rather than mixed image/document sharing. Caption details are also present inside the receipt.
- No mapped recipient phone is required; the recipient is chosen in the target app.
- No text-only WhatsApp fallback or automatic download-and-mark-SENT path is used by the new buttons.
- Cancel, failed native share, unsupported file sharing and failed reference loads do not mark SENT. Failed references are reported with Retry rather than silently omitted.
- Unsupported sharing offers explicit file-saving links and an Open Receipt in New Tab link.
- Share records use a unique event ID, a snapshot token and file metadata. A failed record can be retried without re-sharing files. A changed requirement is not marked sent from a stale receipt.
- Native share success indicates handoff to the selected application, not WhatsApp delivery or proof of which recipient was chosen.

## Database

Applied migration: `20261004081001_test71_cb_receipt_clickable_files_v2` on the connected REDZED database.
New RPCs: `rr_cb_requirement_receipt_context_v2`, `rr_cb_requirement_receipt_record_v2`.
Both use the existing active Owner/Admin authority guard, explicit search paths and authenticated-only execute permissions (PUBLIC/anon revoked). Optional audit columns are added to the existing send-log table. No parallel purchase engine or new public media bucket is created.

Read-only live verification for CB 1011 S4 confirmed enrolled FCL2 Art, MSTK1 Sticker and C1 Colour images. The material receipt now collects the enrolled sticker as well. No Print or Metal ID assignment was found for that particular S4, so the implementation does not infer enrollment from words in the Art name.
Existing CB 1011 values remained S2 Rib 597 / 2.985 KG, S3 Rib 415 / 2.075 KG, S4 Collar/Cuff 398 / 19.900 KG and MSTK1 398 PCS; Cutting PCS was still empty. No synthetic cutting rows or WhatsApp messages were persisted during this change.

## Executed verification

`tests/e2e/test71_cb_receipt_browser.py` ran against real Chromium DOM, Canvas, JPEG and PDF generation, with deterministic labelled QA images and mocked Supabase/native-share boundaries. It uses no production credentials or outbound WhatsApp sending.

18 renderer/share checks passed: enrolled image types; mobile width; clickable receipt image; zoom; next image; nonempty JPEG bytes and fresh user activation; one record after native handoff; separate PDF MIME; no runtime errors; cancel; share error; unsupported sharing; missing-image failure; absent supplier phone/name; 6.2-second preparation then fresh share click; idempotent record retry without resend; more than eight images; original PDF attachments.

7 router checks passed: old callback disconnected; original autosave refresh awaited; new receipt route; web-share delegation; double-click guard; close to same CB; unrelated forms unchanged.

PDF verification passed with PyMuPDF 1.26.7: six test pages, six embedded image objects, ten valid internal links and five original-image URI links. Summary and full-image pages were rendered and visually inspected. Test imagery is explicitly marked QA, not a representation of production garment media.

Re-run with Playwright/Chromium, Pillow and PyMuPDF installed:

```bash
python tests/e2e/test71_cb_receipt_browser.py
```

`CHROMIUM_PATH` can select an installed Chromium binary. `RECEIPT_QA_OUT` optionally selects the output directory; otherwise reports use a temporary directory.

## Verification boundary

These are focused browser/renderer/router tests, not a full-repository regression run. Positive authenticated end-to-end RPC calls and actual WhatsApp attachment receipt on the user's Android device were not exercised by this environment. The backend schema/media queries and execute permissions were checked without impersonating a user. Native chooser availability, target app behavior and final delivery must not be inferred from a Vercel deployment status or a successful mocked share test.


## V2.1 convergence — 2026-10-04

The concurrent V2 viewer/router and authorized media/audit RPCs are retained. One requirement now shares exactly one selected JPG or PDF. JPG consolidates all summary pages; very long slips offer PDF rather than truncating images. Original PDF references are embedded as file attachments within the receipt PDF, not extra WhatsApp files. Supplier is always shown, and the editable short note rebuilds both files. Native share success no longer auto-marks SENT: the user must press भेज दिया · OK. Download/cancel alone do not mark SENT.

Executed after convergence: 22 receipt/browser checks, 7 router checks, PDF embedding/link validation and retained projection gate passed. Full static suite: 305 total, 219 passed, 86 pre-existing failures, zero newly failing test names versus f94298028c720cd6538892da36350a28e7a2538e. This is not a full TEST71 release approval or evidence of delivery to an actual Android WhatsApp recipient.
