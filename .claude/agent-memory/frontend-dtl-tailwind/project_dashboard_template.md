---
name: Dashboard Template — Metric Cards and Transactions Table
description: Patterns used in dashboard/index.html for metric cards with icons, responsive transactions table, and empty state with url-as-variable workaround
type: project
---

The dashboard template (templates/dashboard/index.html) established these patterns:

**Metric cards** use `border-t-2` accent color on top combined with `border border-slate-700` on the remaining three sides. The Tailwind utility ordering matters: `border border-t-2 border-slate-700 border-t-{color}` — list `border-t-2` immediately after `border` so the top shorthand wins. Each card has a `bg-gradient-to-br from-slate-800 to-slate-900` background and `hover:border-slate-600` transition. Icons sit in a small `rounded-xl` badge (`h-9 w-9`) with a tinted background (`bg-slate-700/60`, `bg-emerald-500/10`, `bg-rose-500/10`).

**Transactions table** uses progressive disclosure columns:
- Data + Descrição + Valor — always visible
- Categoria — `hidden sm:table-cell`
- Conta — `hidden md:table-cell`
- Tipo — `hidden lg:table-cell`

Row type detection uses `transaction.type == 'income'` (string comparison). Color badge on Tipo column uses `ring-1` for a subtle border instead of `border`.

**`{% url %}` as variable for include `with`**: DTL cannot nest `{% url %}` inside a `with` clause. Use `{% url 'namespace:name' as var %}` on its own line before `{% include ... with empty_action_url=var %}`.

**Why:** `_empty_state.html` renders `href="{{ empty_action_url }}"` — needs a pre-resolved string, not a tag.

**How to apply:** Any time the empty state partial needs a URL for its CTA, resolve with `{% url ... as var %}` first.
