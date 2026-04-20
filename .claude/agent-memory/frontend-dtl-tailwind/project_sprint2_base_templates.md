---
name: Sprint 2.1 — Base Templates Structure
description: Documents the base template hierarchy, layout decisions, and key implementation details established in Sprint 2.1
type: project
---

Sprint 2.1 created the four foundational templates: `base.html`, `layouts/base_public.html`, `layouts/base_app.html`, and `partials/_messages.html`.

**Why:** These form the visual skeleton for all other templates in the project. Getting the inheritance chain and design tokens right here prevents rework in later sprints.

**How to apply:** All future templates must extend one of the two layout bases — never `base.html` directly.

## Key decisions

- Tailwind is configured inline via `tailwind.config` script block in `base.html` to register Inter as the `sans` font family, so `font-sans` resolves to Inter.
- `base_app.html` sidebar uses `hidden md:flex` so it collapses on mobile without JavaScript.
- The main content area in `base_app.html` is `flex-1 overflow-y-auto` so only the content scrolls, not the sidebar or topbar.
- The topbar avatar shows `{{ request.user.email|first|upper }}` as an initials fallback — no profile image required yet.
- Logout in the sidebar is a `<form method="post">` with `{% csrf_token %}` — not an anchor — to satisfy CSRF and Django's `LogoutView` which requires POST.
- `_messages.html` uses `message.tags` string comparison (`== 'success'`) rather than `message.level` constants, matching the default Django message tag strings. The `{% else %}` branch catches both `'info'` and any unknown tags as sky-colored.
- The dismiss button uses inline `onclick="this.parentElement.remove()"` — no JS framework, no build step.

## URL namespaces used in base_app.html sidebar

| Label | URL name |
|---|---|
| Dashboard | `dashboard:index` |
| Contas | `accounts:list` |
| Categorias | `categories:list` |
| Transações | `transactions:list` |
| Perfil | `profiles:edit` |
| Sair | `users:logout` |

These URL names must exist when the apps are wired up in later sprints.

## Partials extracted in sprint 2.1 (second pass)

The sidebar and topbar markup was extracted from `base_app.html` and `base_public.html` into standalone partials. The layout files now use `{% include %}` instead of inline markup:

- `partials/_sidebar.html` — full `<aside class="hidden md:flex ...">` block with brand + nav + logout POST form.
- `partials/_topbar_public.html` — sticky `<header>` with brand + Entrar/Cadastrar nav links.
- `partials/_topbar_app.html` — `<header class="flex h-16 ...">` with mobile brand, desktop spacer, and user avatar + email.
- `partials/_form_field.html` — receives `field` (BoundField). Renders label (with required `*` in rose-400), widget via `field.as_widget attrs={...}` with full input Tailwind classes, per-error spans in rose-400, help text in slate-500/xs.
- `partials/_empty_state.html` — receives optional context vars: `empty_title`, `empty_message`, `empty_action_url`, `empty_action_label`. Uses `|default` filter for fallbacks. CTA renders only if `empty_action_url` is set.
