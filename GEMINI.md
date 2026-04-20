# GEMINI.md - Finanpy Context & Guidelines

## Project Overview
**Finanpy** is a premium, full-stack personal finance management system built with **Django 5.2** and **TailwindCSS**. It follows a monolithic architecture designed for simplicity and ease of use, prioritizing a modern "SaaS-level" visual identity.

- **Status:** MVP in development (Sprint 4 completed: Auth, Profiles, Accounts, and Dashboard are functional).
- **Core Tech:** Python 3.12+, Django 5.2, SQLite, TailwindCSS (via CDN), Inter Font.
- **Architecture:** Domain-driven Django apps (`users`, `profiles`, `accounts`, `categories`, `transactions`).

## Getting Started

### Development Environment
1.  **Activate Virtualenv:**
    - Windows: `.venv\Scripts\activate` or `venv\Scripts\activate`
2.  **Install Dependencies:** `pip install -r requirements.txt`
3.  **Environment Variables:** Copy `.env.example` to `.env` and configure `SECRET_KEY`, `DEBUG`, and `ALLOWED_HOSTS`.
4.  **Database:** `python manage.py migrate`
5.  **Run Server:** `python manage.py runserver`

### Key Commands
- **Migrations:** `python manage.py makemigrations` / `migrate`
- **Tests:** `python manage.py test`
- **Superuser:** `python manage.py createsuperuser`
- **Linting:** `ruff check .` (Configured for single quotes in `ruff.toml`)

## Development Conventions

### Coding Standards
- **Python Style:** Strict PEP-8 adherence. Use **single quotes** (`'`) for strings.
- **Language:** Code (variables, classes, comments) in **English**; UI text (templates, messages) in **Portuguese (pt-BR)**.
- **Views:** Always use **Class-Based Views (CBVs)**. Use `LoginRequiredMixin` for all authenticated routes.
- **Data Isolation:** Every view must filter data by the current user:
  ```python
  def get_queryset(self):
      return super().get_queryset().filter(user=self.request.user)
  ```
- **Models:** Every model must include `created_at` and `updated_at` timestamps.
- **Signals:** Keep signals in `signals.py` within each app; register them in `apps.py` via the `ready()` method.
- **URLs:** Use app-level namespacing (e.g., `accounts:list`).

### Design System (TailwindCSS)
- **Palette:** Primary (`emerald-500/600`), Background (`slate-950`), Cards (`slate-900`), Borders (`slate-700`).
- **Typography:** **Inter** font via Google Fonts.
- **UI Components:**
    - Inputs/Buttons: `rounded-xl` (12px).
    - Cards/Modals: `rounded-2xl` (16px).
    - Success/Income: `emerald-400`.
    - Error/Expense: `rose-400/500`.

## Project Structure
- `core/`: Settings, root URLs, and global views (Landing Page, Dashboard).
- `users/`: Custom `User` model using **email** as the primary identifier (no username).
- `profiles/`: User profiles (1:1 with `User`), auto-created via signals.
- `accounts/`: Bank account management (Current Balance = Initial + Transactions).
- `categories/`: Transaction categories (In development).
- `transactions/`: Financial records (In development).
- `templates/`:
    - `layouts/`: `base_public.html` (Landing) and `base_app.html` (Dashboard/App).
    - `partials/`: Reusable components (`_sidebar.html`, `_form_field.html`, etc.).
- `docs/`: Product Requirements Document (PRD), Design System, and Coding Standards.

## Documentation Reference
- `PRD.md`: Full product requirements and user stories.
- `TASKS.md`: Sprint-based task list and progress tracking.
- `CLAUDE.md`: Specific instructions for AI agents working on this project.
