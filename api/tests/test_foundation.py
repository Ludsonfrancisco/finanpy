from django.test import TestCase


class ApiFoundationTest(TestCase):
    def test_health_exposes_only_stable_public_fields(self):
        response = self.client.get('/api/v1/health/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {'status': 'ok', 'api_version': 'v1'})

    def test_method_not_allowed_uses_error_envelope(self):
        response = self.client.post('/api/v1/health/', data={}, content_type='application/json')

        self.assertEqual(response.status_code, 405)
        self.assertEqual(response.json()['error']['code'], 'method_not_allowed')
