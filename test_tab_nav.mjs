import { chromium } from 'playwright';

const BASE = 'http://localhost:8000';
const EMAIL = 'admin@admin.com';
const PASS  = 'admin';

// ─── helpers ───────────────────────────────────────────────────────────────

async function getFocusedInfo(page) {
  return page.evaluate(() => {
    const el = document.activeElement;
    if (!el || el === document.body) return null;
    const tag   = el.tagName.toLowerCase();
    const type  = el.getAttribute('type') || '';
    const name  = el.getAttribute('name') || el.getAttribute('id') || '';
    const label = el.getAttribute('aria-label') || el.getAttribute('placeholder') || '';
    const text  = el.innerText?.trim().slice(0, 40) || '';
    const style = window.getComputedStyle(el);
    const hasOutline =
      style.outlineStyle !== 'none' &&
      style.outlineWidth !== '0px' &&
      parseFloat(style.outlineWidth) > 0;
    // Tailwind focus:ring uses box-shadow
    const hasShadow = style.boxShadow && style.boxShadow !== 'none';
    const rect = el.getBoundingClientRect();
    const visible = rect.width > 0 && rect.height > 0;
    return { tag, type, name, label, text, hasOutline, hasShadow, visible };
  });
}

async function tabThrough(page, maxTabs = 30) {
  const steps = [];
  // start from body
  await page.evaluate(() => document.body.focus());
  for (let i = 0; i < maxTabs; i++) {
    await page.keyboard.press('Tab');
    const info = await getFocusedInfo(page);
    if (!info) continue;
    const hasFocusIndicator = info.hasOutline || info.hasShadow;
    steps.push({ ...info, hasFocusIndicator, index: i + 1 });
    // Stop cycling when we revisit the first element
    if (steps.length > 1 && info.name && info.name === steps[0].name) break;
  }
  return steps;
}

function describeEl(el) {
  const id = el.name || el.label || el.text || `${el.tag}[${el.type}]`;
  return `${el.tag}${el.type ? '[' + el.type + ']' : ''}(${id})`;
}

function reportForm(formName, steps, requiredNames) {
  const results = { form: formName, pass: true, issues: [] };

  if (steps.length === 0) {
    results.pass = false;
    results.issues.push('No focusable elements found via Tab');
    return results;
  }

  // Check each required field is reachable
  for (const req of requiredNames) {
    const found = steps.find(s =>
      s.name.includes(req) || s.label.toLowerCase().includes(req.toLowerCase()) ||
      s.text.toLowerCase().includes(req.toLowerCase())
    );
    if (!found) {
      results.pass = false;
      results.issues.push(`Field not reachable via Tab: "${req}"`);
    }
  }

  // Check focus indicators
  const noIndicator = steps.filter(s => !s.hasFocusIndicator && s.visible);
  if (noIndicator.length > 0) {
    results.pass = false;
    noIndicator.forEach(el => {
      results.issues.push(`No visible focus indicator on: ${describeEl(el)}`);
    });
  }

  // Check submit button reachable
  const hasSubmit = steps.some(s =>
    s.type === 'submit' || s.text.toLowerCase().includes('salvar') ||
    s.text.toLowerCase().includes('criar') || s.text.toLowerCase().includes('entrar') ||
    s.text.toLowerCase().includes('registrar') || s.text.toLowerCase().includes('atualizar') ||
    s.text.toLowerCase().includes('cadastrar')
  );
  if (!hasSubmit) {
    results.pass = false;
    results.issues.push('Submit button not reachable via Tab');
  }

  results.steps = steps;
  return results;
}

// ─── auth helper ───────────────────────────────────────────────────────────

async function login(page) {
  await page.goto(`${BASE}/users/login/`);
  await page.fill('input[name="username"]', EMAIL);
  await page.fill('input[name="password"]', PASS);
  await page.click('button[type="submit"]');
  await page.waitForURL('**/dashboard/**', { timeout: 5000 }).catch(() => {});
}

// ─── main ──────────────────────────────────────────────────────────────────

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page    = await context.newPage();
  const allResults = [];

  // ── 1. Signup form ────────────────────────────────────────────────────────
  console.log('\n=== 1. Signup form (/users/signup/) ===');
  await page.goto(`${BASE}/users/signup/`);
  const signupSteps = await tabThrough(page, 30);
  console.log('Focused elements:', signupSteps.map(describeEl));
  allResults.push(reportForm(
    '/users/signup/',
    signupSteps,
    ['email', 'password', 'confirm']
  ));

  // ── 2. Login form ─────────────────────────────────────────────────────────
  console.log('\n=== 2. Login form (/users/login/) ===');
  await page.goto(`${BASE}/users/login/`);
  const loginSteps = await tabThrough(page, 20);
  console.log('Focused elements:', loginSteps.map(describeEl));
  allResults.push(reportForm(
    '/users/login/',
    loginSteps,
    ['email', 'password']
  ));

  // ── authenticate for protected forms ─────────────────────────────────────
  await login(page);

  // ── 3. Create Account ─────────────────────────────────────────────────────
  console.log('\n=== 3. Create Account (/accounts/create/) ===');
  await page.goto(`${BASE}/accounts/create/`);
  const accCreateSteps = await tabThrough(page, 30);
  console.log('Focused elements:', accCreateSteps.map(describeEl));
  allResults.push(reportForm(
    '/accounts/create/',
    accCreateSteps,
    ['name', 'balance']
  ));

  // ── 4. Edit Account ───────────────────────────────────────────────────────
  // Find first account pk
  console.log('\n=== 4. Edit Account (/accounts/<pk>/edit/) ===');
  await page.goto(`${BASE}/accounts/`);
  const editLink = page.locator('a[href*="/accounts/"][href*="/edit/"]').first();
  let editHref = null;
  try {
    editHref = await editLink.getAttribute('href', { timeout: 3000 });
  } catch (e) { /* no accounts yet */ }

  if (editHref) {
    await page.goto(`${BASE}${editHref}`);
    const accEditSteps = await tabThrough(page, 30);
    console.log('Focused elements:', accEditSteps.map(describeEl));
    allResults.push(reportForm('/accounts/<pk>/edit/', accEditSteps, ['name', 'balance']));
  } else {
    allResults.push({ form: '/accounts/<pk>/edit/', pass: false, issues: ['No accounts found to edit — skipped'], steps: [] });
    console.log('No accounts to edit — skipped');
  }

  // ── 5. Create Category ────────────────────────────────────────────────────
  console.log('\n=== 5. Create Category (/categories/create/) ===');
  await page.goto(`${BASE}/categories/create/`);
  const catCreateSteps = await tabThrough(page, 30);
  console.log('Focused elements:', catCreateSteps.map(describeEl));
  allResults.push(reportForm(
    '/categories/create/',
    catCreateSteps,
    ['name', 'type']
  ));

  // ── 6. Create Transaction ─────────────────────────────────────────────────
  console.log('\n=== 6. Create Transaction (/transactions/create/) ===');
  await page.goto(`${BASE}/transactions/create/`);
  const txSteps = await tabThrough(page, 40);
  console.log('Focused elements:', txSteps.map(describeEl));
  allResults.push(reportForm(
    '/transactions/create/',
    txSteps,
    ['title', 'amount', 'date', 'account', 'category']
  ));

  // ── 7. Edit Profile ───────────────────────────────────────────────────────
  console.log('\n=== 7. Edit Profile (/profiles/edit/) ===');
  await page.goto(`${BASE}/profiles/edit/`);
  const profileSteps = await tabThrough(page, 30);
  console.log('Focused elements:', profileSteps.map(describeEl));
  allResults.push(reportForm(
    '/profiles/edit/',
    profileSteps,
    ['first_name', 'last_name', 'phone']
  ));

  // ── 8. Categories list — Edit/Delete button visibility on focus ───────────
  console.log('\n=== 8. Categories list — focus visibility of Edit/Delete buttons ===');
  await page.goto(`${BASE}/categories/`);
  // Tab until we hit an Edit or Delete button inside a card
  let catCardResult = { form: '/categories/ (card buttons)', pass: false, issues: ['Edit/Delete buttons not reached or not visible on focus'], steps: [] };

  await page.evaluate(() => document.body.focus());
  let foundEditBtn = false;
  for (let i = 0; i < 50; i++) {
    await page.keyboard.press('Tab');
    const info = await getFocusedInfo(page);
    if (!info) continue;
    const isEditOrDelete = info.text.toLowerCase().includes('edit') ||
      info.text.toLowerCase().includes('editar') ||
      info.text.toLowerCase().includes('delet') ||
      info.text.toLowerCase().includes('exclu') ||
      info.name.includes('edit') || info.name.includes('delete');
    if (isEditOrDelete) {
      // Check if the button is actually visible
      const visible = await page.evaluate(() => {
        const el = document.activeElement;
        const rect = el.getBoundingClientRect();
        const style = window.getComputedStyle(el);
        return {
          visible: rect.width > 0 && rect.height > 0,
          opacity: style.opacity,
          display: style.display,
          visibility: style.visibility,
        };
      });
      foundEditBtn = true;
      console.log('Edit/Delete button state on focus:', visible);
      if (visible.visible && visible.opacity !== '0' && visible.display !== 'none') {
        catCardResult = { form: '/categories/ (card buttons)', pass: true, issues: [], steps: [info] };
      } else {
        catCardResult = {
          form: '/categories/ (card buttons)',
          pass: false,
          issues: [`Button focused but not visually shown — opacity:${visible.opacity}, display:${visible.display}, visibility:${visible.visibility}`],
          steps: [info]
        };
      }
      break;
    }
  }
  if (!foundEditBtn) {
    catCardResult.issues = ['No Edit/Delete button reached via Tab on /categories/ list (may have no categories, or buttons are not focusable)'];
  }
  allResults.push(catCardResult);

  await browser.close();

  // ─── PRINT FINAL REPORT ────────────────────────────────────────────────────
  console.log('\n\n' + '='.repeat(70));
  console.log('TAB NAVIGATION TEST RESULTS — Finanpy');
  console.log('='.repeat(70));
  for (const r of allResults) {
    const status = r.pass ? '✔ PASS' : '✘ FAIL';
    console.log(`\n${status}  ${r.form}`);
    if (r.steps && r.steps.length > 0) {
      console.log(`  Tab order (${r.steps.length} elements): ` +
        r.steps.map((s, i) => `${i+1}.${describeEl(s)}`).join(' → '));
    }
    if (r.issues && r.issues.length > 0) {
      r.issues.forEach(iss => console.log(`  ISSUE: ${iss}`));
    }
  }
  console.log('\n' + '='.repeat(70));

  // Summary
  const passed = allResults.filter(r => r.pass).length;
  const failed = allResults.filter(r => !r.pass).length;
  console.log(`\nSummary: ${passed} PASS  /  ${failed} FAIL  (total: ${allResults.length})`);
})();
