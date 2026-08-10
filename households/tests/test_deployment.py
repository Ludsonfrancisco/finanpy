from pathlib import Path

from django.test import SimpleTestCase

from core.settings import BASE_DIR


class SQLiteDeploymentConfigurationTest(SimpleTestCase):
    def test_sqlite_deployments_use_one_gunicorn_worker(self):
        worker_argument = r'--workers(?:["\']?\s*,?\s*)["\']?1\b'

        for manifest_name in ('Dockerfile', 'docker-compose.yml'):
            manifest = Path(BASE_DIR, manifest_name).read_text(encoding='utf-8')

            self.assertRegex(manifest, worker_argument)
