import tempfile
from pathlib import Path

from django.core.management import call_command
from django.test import Client, SimpleTestCase, override_settings


class ProductionStaticFilesTest(SimpleTestCase):
    def test_collected_design_tokens_are_served_with_debug_disabled(self):
        with tempfile.TemporaryDirectory() as directory:
            with override_settings(DEBUG=False, STATIC_ROOT=Path(directory)):
                call_command('collectstatic', interactive=False, verbosity=0)
                response = Client().get('/static/css/design-tokens.css')
                body = b''.join(response.streaming_content).decode()
                response.close()

        self.assertEqual(response.status_code, 200)
        self.assertIn('--lar-color-surface-canvas:', body)
