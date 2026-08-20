"""
WSGI config for core project.

It exposes the WSGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/5.2/howto/deployment/wsgi/
"""

import logging
import os
import sys

from django.core.wsgi import get_wsgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'core.settings')

application = get_wsgi_application()

# Execute automatic database migrations on Gunicorn startup
if any('gunicorn' in arg.lower() for arg in sys.argv):
    try:
        from django.core.management import call_command

        call_command('migrate', interactive=False)
    except Exception as exc:
        logging.getLogger('django').exception(
            'Auto-migration on WSGI startup failed: %s', exc
        )
