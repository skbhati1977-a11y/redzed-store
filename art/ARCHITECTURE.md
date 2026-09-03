# Art Master Architecture — v9148

## Page flow

1. Artwork Images
2. Art Details
3. Craft Features & Material
4. Current Art Process Cost
5. Other Margin / Final Art Cost
6. Saved Arts management

This ordering is the canonical owner workflow and should remain visible in the UI.

## State ownership

The Art controller owns categories, Arts, summaries, media references, queued local images, selected Art Icon, manual material requirements, category Basic-rate state, and edit state.

## Cost model

Each process has a category-level **Basic** rate and an Art-level **Extra** rate. Row Total is `Basic + Extra`. Current Process Cost is the sum of all process totals. Final Art Cost is `Current Process Cost + Other Margin`.

Category Basic rates are normally locked once established. Unlocking them is an explicit owner action because changed Basic rates affect future Arts/products while historical products remain unchanged.

## Material model

Material requirements combine:

- automatically-derived requirements from Art Category and Craft Features; and
- owner-added custom requirements.

Automatic requirements should not be removable as manual chips. Custom requirements can be removed without altering category/craft derivation.

## Media model

An Art can have multiple images and one preferred Art Icon. New local files are queued before save; persisted media comes from Supabase. Viewer behavior is shared with the REAL FACTORY master viewer.

## Integration boundaries

The module depends on shared `RR` helpers, Caption Builder, Supabase client/configuration, Art category RPCs, Art persistence RPCs/tables, and media storage. Keep those interfaces stable during UI refactors.

## Refactor policy

Prefer small responsibility-based extractions. Do not create `v9149`, `v9150`, etc. copies of the same canonical source solely for code organization. Git branches/commits provide rollback and history. Cache-busting query versions may still be bumped when a production deployment changes browser assets.
