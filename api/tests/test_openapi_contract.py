import json
from pathlib import Path
from unittest.mock import patch

from django.conf import settings
from django.test import SimpleTestCase
from django.urls import URLPattern, URLResolver, get_resolver
from rest_framework.authentication import SessionAuthentication
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.settings import api_settings
from rest_framework.views import APIView

from api.authentication import DeviceTokenAuthentication
from api.permissions import IsDeviceSession

OPENAPI_EXPECTATIONS = (
    ('version', '3.1.0'),
    ('security_scheme', 'opaqueBearer'),
    ('error_schema', 'ErrorEnvelope'),
    ('route_count', 21),
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
    'ImportBatch',
}

OPENAPI_HTTP_METHODS = {'get', 'post', 'put', 'patch', 'delete'}


def effective_view_setting(view_class, setting_name, default):
    for parent in view_class.__mro__:
        if parent is APIView:
            break
        if setting_name in parent.__dict__:
            return parent.__dict__[setting_name]
    return default


def runtime_security(view_class, route):
    authentication_classes = tuple(
        effective_view_setting(
            view_class,
            'authentication_classes',
            api_settings.DEFAULT_AUTHENTICATION_CLASSES,
        )
    )
    permission_classes = tuple(
        effective_view_setting(
            view_class,
            'permission_classes',
            api_settings.DEFAULT_PERMISSION_CLASSES,
        )
    )
    if not authentication_classes and permission_classes == (AllowAny,):
        return []

    assert authentication_classes == (DeviceTokenAuthentication,), (
        f'{route} must use only DeviceTokenAuthentication.'
    )
    assert permission_classes in {
        (IsAuthenticated,),
        (IsDeviceSession,),
    }, (
        f'{route} must use a known private permission: '
        'IsAuthenticated or IsDeviceSession.'
    )
    return [{'opaqueBearer': []}]


def runtime_api_operations(patterns=None, prefix=''):
    patterns = patterns or get_resolver().url_patterns
    operations = {}
    for pattern in patterns:
        route = prefix + str(pattern.pattern)
        if isinstance(pattern, URLResolver):
            operations.update(runtime_api_operations(pattern.url_patterns, route))
        elif isinstance(pattern, URLPattern) and route.startswith('api/v1/'):
            relative = route.removeprefix('api/v1')
            normalized = relative.replace('<uuid:device_uuid>', '{device_uuid}').replace(
                '<uuid:batch_uuid>', '{batch_uuid}'
            )
            view_class = pattern.callback.view_class
            methods = {
                method
                for method in view_class.http_method_names
                if method in OPENAPI_HTTP_METHODS
                and callable(getattr(view_class, method, None))
            }
            security = runtime_security(view_class, normalized)
            operations[normalized] = {
                method: security for method in methods
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

    def test_cursor_is_issued_only_by_bootstrap_and_delta_responses(self):
        push_schema = self.contract['paths']['/sync/push/']['post']['responses'][
            '200'
        ]['content']['application/json']['schema']
        schemas = self.contract['components']['schemas']

        self.assertEqual(push_schema['required'], ['results'])
        self.assertEqual(set(push_schema['properties']), {'results'})
        self.assertNotIn('cursor', json.dumps(push_schema))
        cursor_response_schemas = {
            name
            for name, schema in schemas.items()
            if 'cursor' in schema.get('properties', {})
        }
        self.assertEqual(cursor_response_schemas, {'Bootstrap', 'DeltaPage'})

    def test_all_api_routes_are_represented(self):
        routes = runtime_api_operations()

        self.assertEqual(len(routes), 21)
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

    def test_runtime_contract_rejects_non_device_authentication(self):
        callback = get_resolver().resolve('/api/v1/devices/').func

        with patch.object(
            callback.view_class,
            'authentication_classes',
            [SessionAuthentication],
        ):
            with self.assertRaisesRegex(
                AssertionError,
                'DeviceTokenAuthentication',
            ):
                runtime_api_operations()

    def test_runtime_contract_rejects_empty_private_permissions(self):
        callback = get_resolver().resolve('/api/v1/devices/').func

        with patch.object(callback.view_class, 'permission_classes', []):
            with self.assertRaisesRegex(
                AssertionError,
                'private permission',
            ):
                runtime_api_operations()

    def test_runtime_contract_rejects_allow_any_private_permission(self):
        callback = get_resolver().resolve('/api/v1/devices/').func

        with patch.object(callback.view_class, 'permission_classes', [AllowAny]):
            with self.assertRaisesRegex(
                AssertionError,
                'private permission',
            ):
                runtime_api_operations()

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

    def test_import_routes_use_private_device_security(self):
        import_paths = {
            '/imports/ofx/preview/',
            '/imports/{batch_uuid}/',
            '/imports/{batch_uuid}/bind-account/',
            '/imports/{batch_uuid}/confirm/',
            '/imports/{batch_uuid}/cancel/',
        }
        self.assertTrue(import_paths.issubset(self.contract['paths']))
        for path in import_paths:
            for operation in self.contract['paths'][path].values():
                if isinstance(operation, dict) and 'operationId' in operation:
                    self.assertEqual(operation['security'], [{'opaqueBearer': []}])
