---
name: Accounts app URL patterns
description: The account creation URL is /accounts/new/ not /accounts/create/ — verified from accounts/urls.py
type: feedback
---

The correct URL for account creation is `/accounts/new/` (name: `accounts:create`), not `/accounts/create/`.

**Why:** Task spec said `/accounts/create/` but the actual URLconf uses `path('new/', ..., name='create')`. Always verify against `accounts/urls.py`.

**How to apply:** When navigating to account forms in tests or automation, use `reverse('accounts:create')` → `/accounts/new/`.
