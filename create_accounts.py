"""
Playwright script to create bank accounts in Finanpy.
"""
import asyncio
import os
from playwright.async_api import async_playwright

BASE_URL = 'http://127.0.0.1:8000'
LOGIN_EMAIL = 'ludsonfrancisco1010@gmail.com'
LOGIN_PASSWORD = '12345678'
CREATE_URL = f'{BASE_URL}/accounts/new/'
LIST_URL = f'{BASE_URL}/accounts/'

ACCOUNTS = [
    'Cartão Nubank Ludson',
    'Cartão Inter Ludson',
    'Cartão Itaú Ludson',
    'Cartão Santander Ludson',
    'Cartão Mercado Pago Ludson',
    'Cartão Inter Ericka',
    'Cartão Nubank Ericka',
]

SCREENSHOTS_DIR = 'screenshots'
os.makedirs(SCREENSHOTS_DIR, exist_ok=True)


async def login(page):
    print('Navigating to login page...')
    await page.goto(f'{BASE_URL}/login/')
    await page.wait_for_load_state('networkidle')
    await page.screenshot(path=f'{SCREENSHOTS_DIR}/00_login_page.png')

    # Django form fields: id_username or id_email depending on config
    # Fill email
    email_field = page.locator('input[type="email"]').first
    if await email_field.count() == 0:
        email_field = page.locator('input[name="username"]').first
    await email_field.fill(LOGIN_EMAIL)

    await page.fill('input[type="password"]', LOGIN_PASSWORD)
    await page.screenshot(path=f'{SCREENSHOTS_DIR}/01_login_filled.png')
    await page.click('button[type="submit"]')
    await page.wait_for_load_state('networkidle')
    await page.screenshot(path=f'{SCREENSHOTS_DIR}/02_after_login.png')
    print(f'After login URL: {page.url}')


async def create_account(page, name, index):
    print(f'\n[{index}/7] Creating account: {name}')
    await page.goto(CREATE_URL)
    await page.wait_for_load_state('networkidle')

    # Django ModelForm generates id_<fieldname> IDs
    # Fill name field
    await page.fill('#id_name', name)

    # Select type = credit (Cartão de crédito)
    await page.select_option('#id_type', value='credit')

    # Fill initial balance = 0
    await page.fill('#id_initial_balance', '0')

    # Fill currency = BRL
    currency = page.locator('#id_currency')
    await currency.fill('')
    await currency.fill('BRL')

    await page.screenshot(
        path=f'{SCREENSHOTS_DIR}/account_{index:02d}_filled.png'
    )

    # Submit the form
    await page.click('button[type="submit"]')
    await page.wait_for_load_state('networkidle')
    final_url = page.url
    await page.screenshot(
        path=f'{SCREENSHOTS_DIR}/account_{index:02d}_result.png'
    )
    print(f'After save URL: {final_url}')

    # Check for form errors on the page
    error_locator = page.locator('.text-rose-400, .errorlist')
    errors = await error_locator.all_text_contents()
    if errors:
        visible_errors = [e.strip() for e in errors if e.strip()]
        if visible_errors:
            print(f'  FORM ERRORS: {visible_errors}')
            return False

    # Success: we should have been redirected away from /new/
    if 'new' not in final_url:
        print(f'  OK - redirected to {final_url}')
        return True
    else:
        print(f'  POSSIBLY FAILED - still on create page')
        return False


async def list_accounts(page):
    print('\nNavigating to accounts list...')
    await page.goto(LIST_URL)
    await page.wait_for_load_state('networkidle')
    await page.screenshot(path=f'{SCREENSHOTS_DIR}/final_accounts_list.png')
    print(f'Screenshot saved: {SCREENSHOTS_DIR}/final_accounts_list.png')

    content = await page.content()
    found = []
    not_found = []
    for account_name in ACCOUNTS:
        if account_name in content:
            found.append(account_name)
        else:
            not_found.append(account_name)

    return found, not_found


async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(viewport={'width': 1280, 'height': 900})
        page = await context.new_page()

        # Login
        await login(page)

        # Verify login succeeded
        if '/login' in page.url:
            print('ERROR: Login failed! Still on login page.')
            await browser.close()
            return

        print(f'\nLogin successful. Current URL: {page.url}')

        # Create each account
        results = []
        for i, name in enumerate(ACCOUNTS, start=1):
            success = await create_account(page, name, i)
            results.append((name, 'OK' if success else 'FAILED'))

        # List all accounts
        found, not_found = await list_accounts(page)

        print('\n=== CREATION RESULTS ===')
        for name, status in results:
            print(f'  [{status}] {name}')

        print(f'\n=== LIST VERIFICATION ===')
        print(f'  Found in list ({len(found)}/7):')
        for name in found:
            print(f'    + {name}')
        if not_found:
            print(f'  NOT found in list:')
            for name in not_found:
                print(f'    - {name}')

        await browser.close()


if __name__ == '__main__':
    asyncio.run(main())
