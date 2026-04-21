---
name: Playwright submit button trap — sidebar logout form
description: The sidebar has a logout POST form with button[type="submit"] that fires before form Save buttons in DOM order. Always use text-scoped selectors for submit.
type: feedback
---

Never use `page.click('button[type="submit"]')` in Playwright tests for this app.

The sidebar (`templates/partials/_sidebar.html`) contains a logout `<form method="post" action="...logout...">` with `<button type="submit">`. Because the sidebar renders before the main content area in DOM order, an unscoped `button[type="submit"]` selector matches the logout button first — logging the user out instead of saving the form.

**Why:** Discovered during account creation automation. Every form submit was clicking the sidebar logout button, destroying the session and redirecting to `/`.

**How to apply:** Always scope submit button clicks to the button text or to the specific form:
- Preferred: `page.click('button[type="submit"]:has-text("Salvar")')`
- Alternative: `page.locator('form[method="post"]:not([action*="logout"]) button[type="submit"]').click()`
- Applies to ALL authenticated pages — any page that includes the sidebar layout (`base_app.html`) has this trap.
