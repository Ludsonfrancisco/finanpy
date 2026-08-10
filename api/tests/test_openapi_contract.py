import json
from pathlib import Path

from django.conf import settings
from django.test import SimpleTestCase
from django.urls import URLPattern, URLResolver, get_resolver
from rest_framework.permissions import AllowAny

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

OPENAPI_HTTP_METHODS = {'get', 'post', 'put', 'patch', 'delete'}


def runtime_api_operations(patterns=None, prefix=''):
    patterns = patterns or get_resolver().url_patterns
    operations = {}
    for pattern in patterns:
        route = prefix + str(pattern.pattern)
        if isinstance(pattern, URLResolver):
            operations.update(runtime_api_operations(pattern.url_patterns, route))
        elif isinstance(pattern, URLPattern) and route.startswith('api/v1/'):
            relative = route.removeprefix('api/v1')
            normalized = relative.replace('<uuid:device_uuid>', '{device_uuid}')
            view_class = pattern.callback.view_class
            methods = {
                method
                for method in view_class.http_method_names
                if method in OPENAPI_HTTP_METHODS
                and callable(getattr(view_class, method, None))
            }
            is_public = (
                not view_class.authentication_classes
                and any(
                    issubclass(permission, AllowAny)
                    for permission in view_class.permission_classes
                )
            )
            operations[normalized] = {
                method: [] if is_public else [{'opaqueBearer': []}]
                for method in methods
            }
    return operations


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
        routes = runtime_api_operations()

        self.assertEqual(len(routes), 16)
        self.assertEqual(set(self.contract['paths']), set(routes))

    def test_path_http_methods_are_exact(self):
        expected = {
            path: set(methods) for path, methods in runtime_api_operations().items()
        }
        actual = {
            path: set(path_item).difference({'parameters'})
            for path, path_item in self.contract['paths'].items()
        }

        self.assertEqual(actual, expected)

    def test_operation_security_is_explicit_and_exact(self):
        for path, methods in runtime_api_operations().items():
            for method, expected in methods.items():
                with self.subTest(path=path, method=method):
                    self.assertEqual(
                        self.contract['paths'][path][method].get('security'),
                        expected,
                    )

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
