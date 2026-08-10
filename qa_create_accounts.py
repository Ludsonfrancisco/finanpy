"""Create synthetic QA accounts without embedding credentials or personal data.

Required environment variables:

- ``FINANPY_QA_EMAIL``
- ``FINANPY_QA_PASSWORD``

Optional variables:

- ``FINANPY_QA_BASE_URL`` (defaults to the local development server)
- ``FINANPY_QA_ACCOUNT_NAMES`` (comma-separated synthetic names)
"""

import asyncio
import os

from playwright.async_api import async_playwright


def required_environment(name):
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f'Required environment variable is missing: {name}')
    return value


def account_names():
    raw_names = os.environ.get(
        'FINANPY_QA_ACCOUNT_NAMES',
        'Conta QA Corrente,Cartão QA Crédito',
    )
    return [name.strip() for name in raw_names.split(',') if name.strip()]


async def main():
    base_url = os.environ.get('FINANPY_QA_BASE_URL', 'http://127.0.0.1:8000').rstrip('/')
    email = required_environment('FINANPY_QA_EMAIL')
    password = required_environment('FINANPY_QA_PASSWORD')

    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        page = await browser.new_page(viewport={'width': 1280, 'height': 900})

        await page.goto(f'{base_url}/login/')
        await page.locator('input[name="username"]').fill(email)
        await page.locator('input[type="password"]').fill(password)
        await page.locator('button[type="submit"]').click()
        await page.wait_for_load_state('networkidle')

        if '/login/' in page.url:
            await browser.close()
            raise RuntimeError('QA login failed; verify the supplied environment variables.')

        for name in account_names():
            await page.goto(f'{base_url}/accounts/new/')
            await page.locator('input[name="name"]').fill(name)
            await page.select_option('select[name="type"]', 'checking')
            await page.locator('input[name="initial_balance"]').fill('0')
            await page.locator('input[name="currency"]').fill('BRL')
            await page.locator('button[type="submit"]').click()
            await page.wait_for_load_state('networkidle')

        await browser.close()


if __name__ == '__main__':
    asyncio.run(main())
