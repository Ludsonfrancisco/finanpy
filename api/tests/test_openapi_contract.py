import json
from pathlib import Path

from django.conf import settings
from django.test import SimpleTestCase
from django.urls import URLPattern, URLResolver, get_resolver

OPENAPI_EXPECTATIONS = (
    ('version', '3.1.0'),
    ('security_scheme', 'opaqueBearer'),
    ('error_schema', 'ErrorEnvelope'),
    ('route_count', 16),
)

REQUIRED_SCHEMAS = {
    'ErrorEnvelope',
    'Device',
    'TokenPair',
    'Household',
    'FinancialOwner',
    'Account',
    'Category',
    'Transaction',
    'Bootstrap',
    'PushOperation',
    'PushResult',
    'SyncChange',
    'DeltaPage',
}


def api_routes(patterns=None, prefix=''):
    patterns = patterns or get_resolver().url_patterns
    routes = set()
    for pattern in patterns:
        route = prefix + str(pattern.pattern)
        if isinstance(pattern, URLResolver):
            routes.update(api_routes(pattern.url_patterns, route))
        elif isinstance(pattern, URLPattern) and route.startswith('api/v1/'):
            relative = route.removeprefix('api/v1')
            normalized = relative.replace('<uuid:device_uuid>', '{device_uuid}')
            routes.add(normalized)
    return routes


class OpenApiContractTest(SimpleTestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        contract_path = Path(settings.BASE_DIR) / 'docs' / 'openapi-v1.yaml'
        with contract_path.open(encoding='utf-8') as contract_file:
            cls.contract = json.load(contract_file)

    def test_openapi_version_and_metadata(self):
        self.assertEqual(self.contract['openapi'], '3.1.0')
        self.assertEqual(
            self.contract['info'],
            {'title': 'Lar Finance Private API', 'version': '1.0.0'},
        )
        self.assertEqual(self.contract['servers'], [{'url': '/api/v1'}])

    def test_opaque_bearer_security_scheme_does_not_claim_jwt(self):
        scheme = self.contract['components']['securitySchemes']['opaqueBearer']

        self.assertEqual(scheme['type'], 'http')
        self.assertEqual(scheme['scheme'], 'bearer')
        self.assertNotIn('bearerFormat', scheme)
        self.assertNotIn('jwt', json.dumps(scheme).lower())

    def test_error_and_resource_schemas_are_defined(self):
        schemas = self.contract['components']['schemas']

        self.assertTrue(REQUIRED_SCHEMAS.issubset(schemas))
        self.assertIn('ErrorEnvelope', schemas)

    def test_all_api_routes_are_represented(self):
        routes = api_routes()

        self.assertEqual(len(routes), 16)
        self.assertEqual(set(self.contract['paths']), routes)

    def test_every_response_documents_request_id_header(self):
        components = self.contract['components']['responses']
        for path, path_item in self.contract['paths'].items():
            for method, operation in path_item.items():
                if method == 'parameters':
                    continue
                for status, response in operation['responses'].items():
                    with self.subTest(path=path, method=method, status=status):
                        if '$ref' in response:
                            response = components[response['$ref'].rsplit('/', 1)[-1]]
                        self.assertIn('X-Request-ID', response.get('headers', {}))

    def test_openapi_expectations_are_documented(self):
        self.assertEqual(len(OPENAPI_EXPECTATIONS), 4)
