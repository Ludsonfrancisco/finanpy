---
name: Home landing page — structure and patterns
description: Documents the structure, sections, and design decisions for templates/pages/home.html (public landing page)
type: project
---

The public landing page lives at `templates/pages/home.html` and extends `layouts/base_public.html`.

It is composed of three vertical sections, all on `bg-slate-950`:

1. **Hero** — centered, `py-24 md:py-36`, gradient heading (`from-emerald-500 via-teal-500 to-cyan-500 bg-clip-text text-transparent`) split across two lines (gradient + plain `slate-100`), two CTA buttons side-by-side on `sm:flex-row` (primary emerald gradient + ghost `border-slate-700`).
2. **Features** — 3-column `md:grid-cols-3` grid of `bg-slate-900 rounded-2xl border border-slate-800` cards; icon in `bg-slate-800 rounded-xl h-12 w-12` container, colored per feature (`emerald-400`, `teal-400`, `cyan-400`); title `font-semibold text-slate-100 mt-4 mb-2`; description `text-sm text-slate-400`.
3. **Bottom CTA** — `border-t border-slate-800 pt-16 pb-24 text-center`, single emerald primary button linking to `users:signup`.

URL namespaces used: `users:signup`, `users:login` — consistent with `_topbar_public.html`.
Focus rings use `focus:ring-offset-slate-950` to match the dark background.

**Why:** Establishes the visual language for the public area and provides a conversion-oriented layout pattern that can be reused for future marketing sections.

**How to apply:** Any future public section additions (pricing, testimonials, FAQ) should follow the same section spacing (`px-6 py-24`) and background (`bg-slate-950`) with `max-w-5xl` or `max-w-3xl` content containers.
