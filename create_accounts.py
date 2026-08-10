"""Backward-compatible entry point for the environment-driven QA script."""

import asyncio

from qa_create_accounts import main

if __name__ == '__main__':
    asyncio.run(main())
