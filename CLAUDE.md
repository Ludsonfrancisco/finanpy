# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Activate virtualenv (Windows)
.venv\Scripts\activate
# or if using venv/
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run migrations
python manage.py migrate

# Start dev server
python manage.py runserver

# Create superuser
python manage.py createsuperuser

# Run tests
python manage.py test

# Run tests for a single app
python manage.py test accounts

# Run tests for a single class/method
python manage.py test accounts.tests.AccountModelTest.test_current_balance

# Generate migrations after model changes
python manage.py makemigrations
```

## Architecture

Finanpy is a monolithic Django 5.2 application for personal finance management. Users register with email (no username), manage bank accounts, categories, and transactions, and view a consolidated dashboard.

### App structure

| App | Responsibility |
|---|---|
| `core` | Global settings (`core/settings.py`), root URL conf (`core/urls.py`), WSGI/ASGI |
| `users` | Custom `User` model: email as `USERNAME_FIELD`, no `username` field |
| `profiles` | `Profile` 1:1 with `User`, auto-created via `post_save` signal |
| `accounts` | Bank accounts with `initial_balance` and computed `current_balance` |
| `categories` | Income/expense categories with color and icon |
| `transactions` | Financial transactions linked to an account and category |

### Data relationships

```
User ──── Profile      (1:1, signal-created)
User ──── Account      (1:N)
User ──── Category     (1:N)
User ──── Transaction  (1:N)
Account ── Transaction (1:N)
Category ─ Transaction (1:N)
```

### Two visual contexts

- **Public area** — uses `templates/layouts/base_public.html` (landing, signup, login)
- **Authenticated area** — uses `templates/layouts/base_app.html` (sidebar + topbar layout)

All authenticated views require `LoginRequiredMixin`. Reusable partials live in `templates/partials/`.

## Code conventions

- **Python:** PEP-8, single quotes, code in English, UI text in pt-BR
- **Views:** always Class-Based Views (`ListView`, `CreateView`, `UpdateView`, `DeleteView`)
- **Data isolation:** every view that reads or mutates user data must scope the queryset to `request.user`:
  ```python
  def get_queryset(self):
      return super().get_queryset().filter(user=self.request.user)
  ```
- **Signals:** declared in `<app>/signals.py`, registered in `<app>/apps.py` via `ready()`
- **Models:** always include `created_at` and `updated_at` fields
- **URL namespacing:** `accounts:list`, `categories:create`, etc.
- **Templates:** always inherit from a base layout; never inline raw HTML pages

## Design system

TailwindCSS via CDN (no build step). Core palette:

| Token | Class |
|---|---|
| Primary action | `emerald-500` / `emerald-600` |
| Income (positive) | `emerald-400` |
| Expense (negative) | `rose-400` / `rose-500` |
| App background | `slate-950` |
| Card background | `slate-900` |
| Input background | `slate-800` |
| Border | `slate-700` |
| Body text | `slate-100` |
| Muted text | `slate-400` |
| Hero gradient | `from-emerald-500 via-teal-500 to-cyan-500` |

Font: **Inter** (Google Fonts). Border radius: `rounded-xl` for inputs/buttons, `rounded-2xl` for cards.

## Settings notes

- `AUTH_USER_MODEL` must be set to `'users.User'` before any migration that references `User`
- `LANGUAGE_CODE` should be `'pt-br'`, `TIME_ZONE` should be `'America/Sao_Paulo'`
- `TEMPLATES['DIRS']` must include `BASE_DIR / 'templates'`; `APP_DIRS` should be `False` once a global `templates/` dir is in use
- `LOGIN_REDIRECT_URL = '/dashboard/'`, `LOGOUT_REDIRECT_URL = '/'`
- TailwindCSS is loaded via CDN — no npm or build tooling required in the MVP
