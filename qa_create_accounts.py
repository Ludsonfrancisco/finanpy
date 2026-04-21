"""
Playwright script to create bank accounts in Finanpy.
Run with: python qa_create_accounts.py
"""
import asyncio
from playwright.async_api import async_playwright

LOGIN_URL  = 'http://127.0.0.1:8000/login/'
CREATE_URL = 'http://127.0.0.1:8000/accounts/new/'
LIST_URL   = 'http://127.0.0.1:8000/accounts/'

EMAIL    = 'ludsonfrancisco1010@gmail.com'
PASSWORD = '12345678'

ACCOUNTS = [
    {'name': 'Cartão Nubank Ludson',        'type': 'credit', 'initial_balance': '0', 'currency': 'BRL'},
    {'name': 'Cartão Inter Ludson',         'type': 'credit', 'initial_balance': '0', 'currency': 'BRL'},
    {'name': 'Cartão Itaú Ludson',          'type': 'credit', 'initial_balance': '0', 'currency': 'BRL'},
    {'name': 'Cartão Santander Ludson',     'type': 'credit', 'initial_balance': '0', 'currency': 'BRL'},
    {'name': 'Cartão Mercado Pago Ludson',  'type': 'credit', 'initial_balance': '0', 'currency': 'BRL'},
    {'name': 'Cartão Inter Ericka',         'type': 'credit', 'initial_balance': '0', 'currency': 'BRL'},
    {'name': 'Cartão Nubank Ericka',        'type': 'credit', 'initial_balance': '0', 'currency': 'BRL'},
]


async def ensure_logged_in(page):
    """Re-login if we are no longer authenticated."""
    current = page.url
    if 'login' in current or current == 'http://127.0.0.1:8000/' or '/login/' in current:
        print('   [!] Session lost — re-logging in...')
        await page.goto(LOGIN_URL)
        await page.wait_for_load_state('networkidle')
        # Try common email/username field selectors
        for sel in ['input[name="username"]', 'input[name="email"]', 'input[type="email"]']:
            if await page.locator(sel).count() > 0:
                await page.fill(sel, EMAIL)
                break
        await page.fill('input[type="password"]', PASSWORD)
        await page.click('button[type="submit"]')
        await page.wait_for_load_state('networkidle')
        print(f'   Re-login result URL: {page.url}')


async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(viewport={'width': 1280, 'height': 900})
        page = await context.new_page()

        # Capture all console messages
        page.on('console', lambda msg: print(f'   [console:{msg.type}] {msg.text}') if msg.type in ('error', 'warning') else None)

        # ── Login ──────────────────────────────────────────────────────────────
        print('Navigating to login page...')
        await page.goto(LOGIN_URL)
        await page.wait_for_load_state('networkidle')
        await page.screenshot(path='qa_screenshot_01_login.png')

        # Inspect what input fields are present
        inputs = await page.locator('input').all()
        for inp in inputs:
            name = await inp.get_attribute('name')
            typ  = await inp.get_attribute('type')
            print(f'  Login form input: name={name} type={typ}')

        # Fill email — try username first (Django default auth form uses 'username')
        email_sel = None
        for sel in ['input[name="username"]', 'input[name="email"]', 'input[type="email"]']:
            if await page.locator(sel).count() > 0:
                email_sel = sel
                break
        print(f'  Using email selector: {email_sel}')
        await page.fill(email_sel, EMAIL)
        await page.fill('input[type="password"]', PASSWORD)
        await page.click('button[type="submit"]')
        await page.wait_for_load_state('networkidle')
        await page.screenshot(path='qa_screenshot_02_after_login.png')
        print(f'After login — URL: {page.url}')

        if 'dashboard' not in page.url and 'accounts' not in page.url:
            print('ERROR: Login may have failed. Current URL:', page.url)
            await browser.close()
            return

        # ── Create accounts ────────────────────────────────────────────────────
        results = []
        for i, acc in enumerate(ACCOUNTS, start=1):
            print(f'\n[{i}/{len(ACCOUNTS)}] Creating: {acc["name"]}')
            await page.goto(CREATE_URL)
            await page.wait_for_load_state('networkidle')

            current_url = page.url
            print(f'   Create page URL: {current_url}')

            # If redirected to login, re-authenticate
            if 'login' in current_url:
                print('   Redirected to login — re-authenticating...')
                for sel in ['input[name="username"]', 'input[name="email"]', 'input[type="email"]']:
                    if await page.locator(sel).count() > 0:
                        await page.fill(sel, EMAIL)
                        break
                await page.fill('input[type="password"]', PASSWORD)
                await page.click('button[type="submit"]')
                await page.wait_for_load_state('networkidle')
                print(f'   Re-login URL: {page.url}')
                await page.goto(CREATE_URL)
                await page.wait_for_load_state('networkidle')
                print(f'   Create page URL after re-login: {page.url}')

            # Debug: list all inputs on the form page
            inputs = await page.locator('input').all()
            for inp in inputs:
                name = await inp.get_attribute('name')
                typ  = await inp.get_attribute('type')
                print(f'   Form input: name={name} type={typ}')

            selects = await page.locator('select').all()
            for sel in selects:
                name = await sel.get_attribute('name')
                print(f'   Form select: name={name}')

            # Fill name
            name_input = page.locator('input[name="name"]')
            await name_input.wait_for(state='visible', timeout=10000)
            await name_input.fill(acc['name'])

            # Select type
            await page.select_option('select[name="type"]', acc['type'])

            # Fill initial_balance
            await page.locator('input[name="initial_balance"]').fill(acc['initial_balance'])

            # Fill currency (clear first, then type)
            cur = page.locator('input[name="currency"]')
            await cur.click()
            await cur.press('Control+a')
            await cur.fill(acc['currency'])

            # Screenshot before submit
            await page.screenshot(path=f'qa_screenshot_form_{i:02d}.png')

            # Submit — use text 'Salvar' to avoid hitting the sidebar logout button
            await page.click('button[type="submit"]:has-text("Salvar")')
            await page.wait_for_load_state('networkidle')

            current_url = page.url
            print(f'   After submit — URL: {current_url}')

            # Check for success (redirect to accounts list)
            success = 'accounts' in current_url and 'new' not in current_url
            results.append({'name': acc['name'], 'success': success, 'url': current_url})
            await page.screenshot(path=f'qa_screenshot_result_{i:02d}.png')

            if not success:
                # Capture any error messages
                try:
                    errors = await page.locator('.text-rose-400, .errorlist, [class*="error"]').all_text_contents()
                    if errors:
                        print(f'   Form errors: {errors}')
                except Exception:
                    pass

        # ── List page ──────────────────────────────────────────────────────────
        print('\nNavigating to accounts list...')
        await page.goto(LIST_URL)
        await page.wait_for_load_state('networkidle')
        await page.screenshot(path='qa_screenshot_final_list.png')

        body_text = await page.inner_text('body')
        found = [acc['name'] for acc in ACCOUNTS if acc['name'] in body_text]
        missing = [acc['name'] for acc in ACCOUNTS if acc['name'] not in body_text]

        print(f'\nAccounts visible on list page ({len(found)}/{len(ACCOUNTS)}):')
        for name in found:
            print(f'  + {name}')
        if missing:
            print(f'Missing from list page:')
            for name in missing:
                print(f'  ! {name}')

        await browser.close()

        # ── Summary ────────────────────────────────────────────────────────────
        print('\n' + '='*60)
        print('CREATION RESULTS:')
        ok_count = 0
        for r in results:
            status = 'OK  ' if r['success'] else 'FAIL'
            if r['success']:
                ok_count += 1
            print(f'  [{status}] {r["name"]}')
        print(f'\nTotal created successfully: {ok_count}/{len(ACCOUNTS)}')
        print('='*60)
        print('Screenshots saved with prefix qa_screenshot_*.png')


if __name__ == '__main__':
    asyncio.run(main())
