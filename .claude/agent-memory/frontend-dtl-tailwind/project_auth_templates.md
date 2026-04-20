---
name: Auth Templates — signup.html and login.html
description: Patterns, decisions, and conventions established when building the signup and login auth pages for Finanpy.
type: project
---

Both templates live at `templates/users/signup.html` and `templates/users/login.html`.

**Key decisions:**

- Extend `layouts/base_public.html` — the layout wraps both topbar and footer, so the template's `{% block content %}` owns the full-page centering div (`min-h-screen bg-slate-950 flex items-center justify-center px-4 py-16`).
- The card is `max-w-md w-full` inside that wrapper, using the standard card class: `bg-slate-900 rounded-2xl border border-slate-800 p-8 shadow-xl shadow-black/30`.
- The "Finanpy" brand at the top of each card uses the hero gradient (`from-emerald-500 via-teal-500 to-cyan-500`) as a `bg-clip-text text-transparent` link to `{% url 'home' %}`.
- Forms iterate via `{% for field in form %}` — the `SignUpForm` and `LoginForm` widgets already have Tailwind classes injected in `__init__`, so `{{ field }}` is rendered directly without adding any class.
- Labels are rendered manually via `{{ field.label }}` bound to `for="{{ field.id_for_label }}"` instead of `{{ field.label_tag }}` — this avoids Django appending a colon and allows clean Tailwind styling on the `<label>` element.
- Field errors: iterated manually (`{% for error in field.errors %}<li>{{ error }}</li>{% endfor %}`) inside a `<ul class="list-none">` wrapper div styled `text-rose-400 text-sm mt-1`. Avoids the unstyled `<ul>` that `{{ field.errors }}` would emit.
- Non-field errors rendered above the fields inside a rose-tinted alert div.
- `help_text` rendered only on signup (password complexity hint) in `text-xs text-slate-500`.
- `novalidate` on `<form>` to let Django handle all validation server-side.
- `{% include 'partials/_messages.html' %}` inside the card, above the form.
- Footer link (outside the card) uses `text-slate-400` base with `text-emerald-400 hover:text-emerald-300` anchor.

**Why:** Keeps a consistent centered auth UX pattern that matches the public landing page's dark aesthetic without introducing any extra layout partials.

**How to apply:** Use this card-centered pattern for any future public-area single-action page (e.g., password reset). Always inject Tailwind on form widgets in Python rather than in templates to keep templates clean.
