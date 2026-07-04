# AI Site Architect: Generative Content Architecture

> **Maturity: Experimental.** GleamCMS and the AI Architect are product layers built on top of AaronDB, not part of the core database contract. See `docs/feature_maturity.md`.

The **AI Site Architect** (introduced in v2.2.0) evolves GleamCMS from a static theme generator into a structural site composer. It enables autonomous agents and users to generate full landing pages with logical flow, premium layouts, and high-end visual flourishes.

## 🧬 Principles

1.  **Site Story**: A site is not a collection of headers; it is a narrative. The Architect generates 4-5 sections (Hero, Features, Stats, CTA, Content) that logically flow.
2.  **Manifestation as Facts**: Every section is saved as a discrete `Post` fact in GleamDB. The Architect doesn't just "show" a site; it "builds" it in the database.
3.  **Generative Flourishes**: Design is de-complected from rendering. The Architect specifies high-end CSS flares (e.g., "Glassmorphic hero with gold accent bar"), and the engine manifests them.

## 🛠️ Implementation Details

### Sectional Taxonomy
The `Post` record includes a `section_type` field that directs the rendering engine:
- `hero`: High-impact value proposition with split-layout support.
- `features`: Grid-based benefit blocks.
- `stats`: Highlighted numerical data (e.g., "1.2M Total Impact").
- `cta`: Call-to-action closure.
- `content`: Standard long-form content.

### Sequential Manifestation
To preserve the "Site Story" order regardless of publication time, the Architect uses **Indexed Fact Slugs**:
- `my-site-1-hero`
- `my-site-2-features`
- `my-site-3-stats`
- ...

The `archive_view` sorts by these slugs to ensure the narrative remains intact.

### WP-Level Flourishes
GleamCMS integrates professional-grade UI patterns triggered by AI specifications:
- **Scroll Reveal**: Uses `IntersectionObserver` to animate sections into view as the user interacts.
- **Grid Rhythm**: Spacing scales (`airy`, `compact`) are automatically applied to the grid system.
- **Custom Flourish Injection**: Sanitized CSS injection allows the AI to apply unique styles (gradients, shadows, hover states) per site.

## 🚀 Usage Guide

### Triggering a Site Generation
The Architect is exposed via the `/api/ai/design` endpoint.

```bash
curl -X POST http://localhost:4000/api/ai/design \
  -H "Authorization: Bearer sovereign-token-2026" \
  -d '{"prompt": "A professional landing page for a boutique coffee roastery."}'
```

The system will:
1.  Generate a full Site Specification via Gemini.
2.  Manifest 4-5 sections as Posts in GleamDB.
3.  Configure the site's theme (colors, fonts, flourishes).
4.  Optionally trigger a static build of the new site.

## 🧙🏾‍♂️ Philosophy
> "Is the complexity of a page worth its utility? By breaking a site into facts, we make the design as queryable and mutable as the data itself." — Rich Hickey (inspired)
