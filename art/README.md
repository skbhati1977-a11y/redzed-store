# REDZED Art Master

Professional module map for the current **v9148** Art Master.

## Production entry point

The public GitHub Pages entry point remains at `/real-art-master.html` so existing links and bookmarks keep working.

## Current production assets

- `/real-art-master.html` — page structure and production entry point
- `/real-art-master-final.css` — Art Master-specific presentation
- `/real-art-master.js` — Art Master application/controller logic
- `/real-caption-builder.css` and `/real-caption-builder.js` — reusable craft-feature builder
- `/real-master-viewer.css` — reusable media viewer
- `/real-style.css` and `/real-common.js` — shared REAL FACTORY UI/runtime
- `/config.js` — Supabase configuration

## Functional areas

### Media
Camera/gallery selection, artwork preview, Art Icon selection, saved media references, and full-screen viewer.

### Details & categories
Art number, category, design name, factory instructions, category creation, and category default design name.

### Craft & materials
Caption Builder integration plus automatic and manually-added material requirements.

### Costing
Category Basic rates, per-Art Extra rates, lock/unlock behavior, process totals, Other Margin, and Final Art Cost.

### Saved Arts
Load, search, category filter, preview, edit, refresh, and summary statistics.

## Organization rules

1. `v9148` is the current production baseline.
2. Keep the public entry point stable; do not move it without a redirect/migration plan.
3. Shared REAL FACTORY assets stay shared rather than being copied into Art-specific folders.
4. New Art-only code should use the `art-` naming prefix and stay separate from shared `rr-` components.
5. Database/RPC behavior must remain backward compatible with existing Arts and Products.
6. Existing Products must not be recalculated when Art/category costs change; updated costs apply to future product creation according to the existing business rule.
7. Avoid version-copy files for routine edits. Git history is the version history; update the canonical production files and bump their cache query only when deployment requires it.

## Recommended internal boundaries

When the controller needs further refactoring, split by responsibility rather than by version:

- `art-state` — in-memory state and selectors
- `art-categories` — categories and Basic rates
- `art-costing` — process rows, totals and margin
- `art-materials` — derived/manual requirements
- `art-media` — uploads, icon and viewer
- `art-form` — validation/create/edit/save orchestration
- `art-list` — saved cards, search and filters

Do this incrementally so production behavior remains testable after every change.
