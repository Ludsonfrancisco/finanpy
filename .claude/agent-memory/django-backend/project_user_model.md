---
name: Custom User model — initial implementation
description: Key decisions and gotchas from implementing the custom User model in the users app
type: project
---

`users.User` extends `AbstractUser` with `username = None`, `email` as `USERNAME_FIELD`, and a custom `UserManager`. Fields `created_at` / `updated_at` are present. `REQUIRED_FIELDS = []`.

`AUTH_USER_MODEL = 'users.User'` is declared in `core/settings.py` after `DEFAULT_AUTO_FIELD`.

**Why:** Django requires `AUTH_USER_MODEL` to be set before any migration that references the user table. The initial SQLite database had admin migrations applied against the default `auth.User`; the DB had to be dropped and re-created when the custom model was introduced.

**How to apply:** Any time a fresh environment is set up or the DB is stale against a prior `auth.User`, drop `db.sqlite3` before running `migrate`. Never edit already-applied migrations — drop and recreate instead during early dev.

Also fixed: `core/settings.py` line 39 was missing a comma after `'django.contrib.messages'` (implicit string concatenation bug — would silently merge two strings). `LANGUAGE_CODE` corrected to `'pt-br'`, `TIME_ZONE` to `'America/Sao_Paulo'`.
