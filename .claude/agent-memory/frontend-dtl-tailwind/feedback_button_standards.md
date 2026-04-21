---
name: Button and Spacing Standards — Enforced Conventions
description: Exact Tailwind class patterns for primary, secondary, and danger buttons; card padding; heading margin; and grid gap conventions used throughout the app area
type: feedback
---

Enforce these exact patterns on all app-area templates. Deviations were found and fixed during the 7.1 visual consistency audit.

**Primary button (all CTAs, form submit, "Nova X" links):**
`inline-flex items-center gap-2 rounded-xl bg-emerald-500 px-4 py-2 text-sm font-semibold text-white shadow transition hover:bg-emerald-600 focus:outline-none focus:ring-2 focus:ring-emerald-500/40`

**Secondary button (Cancelar, Limpar, back links):**
`inline-flex items-center gap-2 rounded-xl bg-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 shadow transition hover:bg-slate-600 focus:outline-none focus:ring-2 focus:ring-slate-500/40`
- Do NOT use `border border-slate-700 bg-slate-800` — use solid `bg-slate-700` instead.

**Danger button (confirm_delete submit):**
`inline-flex items-center gap-2 rounded-xl bg-rose-600 px-4 py-2 text-sm font-semibold text-white shadow transition hover:bg-rose-700 focus:outline-none focus:ring-2 focus:ring-rose-500/40`
- Do NOT use ghost/outline style (`border border-rose-700/50 bg-rose-900/30 text-rose-300`) for confirm_delete form buttons.

**Key spacing rules:**
- Page heading wrapper: `mb-8` (not `mb-6`)
- Card grid/flex gap: `gap-6`
- Standard card internal padding: `p-6`
- Exception: form field side-by-side pairs (e.g. type+currency, account+category) use `gap-4` — this is intentional tight layout for form grids.
- Exception: inline row layouts (icon+text, flex items inside a card) also use `gap-4`.

**Public-area submit buttons (signup.html, login.html):**
Use the gradient hero style (`bg-gradient-to-r from-emerald-500 to-teal-500`) with `py-2.5` — intentionally larger for public CTAs matching the landing page hero aesthetic. Do not flatten these to the app-area standard.

**Why:** Standardized during sprint 7.1.1–7.1.3 visual consistency audit. Mixed `px-5 py-2.5` vs `px-4 py-2`, missing `shadow`, inconsistent secondary button patterns (border+bg-slate-800 vs bg-slate-700), and one confirm_delete using ghost danger style instead of solid rose-600 were all found and corrected.

**How to apply:** Every new template or edit to an existing template in the authenticated area must use these exact class strings verbatim. Do not add `justify-center` to non-full-width buttons; only add it when the button spans full width.
