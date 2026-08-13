import hashlib
from datetime import date
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

import boto3
from botocore.exceptions import ClientError
from botocore.stub import ANY, Stubber
from django.test import SimpleTestCase

from core.backup_config import R2BackupConfig
from core.r2_storage import (
    R2Storage,
    RemoteObject,
    RemoteObjectConflict,
    RemoteObjectInvalid,
    RemoteVerificationError,
)


class R2StorageTest(SimpleTestCase):
    bucket = 'lar-finance-backups'
    key = 'production/backups/2026/08/lar-finance-2026-08-12.sqlite3'
    backup_date = date(2026, 8, 12)
    content = b'data'
    sha256 = hashlib.sha256(content).hexdigest()

    def setUp(self):
        self.client = boto3.client(
            service_name='s3',
            endpoint_url='https://account.invalid',
            aws_access_key_id='fake-access-id',
            aws_secret_access_key='fake-secret',
            region_name='auto',
        )
        self.storage = R2Storage(
            client=self.client,
            bucket=self.bucket,
            prefix='production',
        )
        self.stubber = Stubber(self.client)

    def valid_head(self, *, key=None, backup_date=None, size=4, sha256=None):
        key = key or self.key
        backup_date = backup_date or self.backup_date
        sha256 = sha256 or self.sha256
        self.stubber.add_response(
            'head_object',
            {
                'ContentLength': size,
                'Metadata': {
                    'sha256': sha256,
                    'size': str(size),
                    'backup-date': backup_date.isoformat(),
                    'retention': 'daily',
                },
            },
            {'Bucket': self.bucket, 'Key': key},
        )

    def test_from_config_builds_the_r2_client_with_exact_credentials(self):
        config = R2BackupConfig.from_env(
            {
                'R2_BACKUP_ENDPOINT_URL': 'https://account.invalid',
                'R2_BACKUP_ACCESS_KEY_ID': 'fake-access-id',
                'R2_BACKUP_SECRET_ACCESS_KEY': 'fake-secret',
                'R2_BACKUP_BUCKET': self.bucket,
            }
        )
        sentinel_client = object()

        with patch(
            'core.r2_storage.boto3.client', return_value=sentinel_client
        ) as client:
            storage = R2Storage.from_config(config)

        client.assert_called_once_with(
            service_name='s3',
            endpoint_url='https://account.invalid',
            aws_access_key_id='fake-access-id',
            aws_secret_access_key='fake-secret',
            region_name='auto',
        )
        self.assertIs(storage.client, sentinel_client)
        self.assertEqual(storage.bucket, self.bucket)
        self.assertEqual(storage.prefix, 'production')

    def test_head_returns_none_for_nosuchkey_code(self):
        self.stubber.add_client_error(
            'head_object',
            service_error_code='NoSuchKey',
            http_status_code=400,
            expected_params={'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber:
            self.assertIsNone(self.storage.head_managed(self.key))

    def test_head_returns_none_for_http_404_status(self):
        self.stubber.add_client_error(
            'head_object',
            service_error_code='Unknown',
            http_status_code=404,
            expected_params={'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber:
            self.assertIsNone(self.storage.head_managed(self.key))

    def test_head_returns_none_for_textual_404_code(self):
        self.stubber.add_client_error(
            'head_object',
            service_error_code='404',
            http_status_code=400,
            expected_params={'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber:
            self.assertIsNone(self.storage.head_managed(self.key))

    def test_head_propagates_notfound_code_without_http_404(self):
        self.stubber.add_client_error(
            'head_object',
            service_error_code='NotFound',
            http_status_code=400,
            expected_params={'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber, self.assertRaises(ClientError):
            self.storage.head_managed(self.key)

    def test_head_propagates_http_500(self):
        self.stubber.add_client_error(
            'head_object',
            service_error_code='InternalError',
            http_status_code=500,
            expected_params={'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber, self.assertRaises(ClientError):
            self.storage.head_managed(self.key)

    def test_head_does_not_treat_authentication_failure_as_absence(self):
        self.stubber.add_client_error(
            'head_object',
            service_error_code='AccessDenied',
            service_message='denied',
            http_status_code=403,
            expected_params={'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber, self.assertRaises(ClientError):
            self.storage.head_managed(self.key)

    def test_head_rejects_missing_metadata(self):
        self.stubber.add_response(
            'head_object',
            {'ContentLength': 4, 'Metadata': {}},
            {'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber, self.assertRaises(RemoteObjectInvalid):
            self.storage.head_managed(self.key)

    def test_head_rejects_non_lowercase_or_wrong_length_sha256(self):
        for invalid_sha256 in ('a' * 63, 'A' * 64, 'g' * 64):
            with self.subTest(sha256=invalid_sha256):
                self.valid_head(sha256=invalid_sha256)
                with self.stubber, self.assertRaises(RemoteObjectInvalid):
                    self.storage.head_managed(self.key)

    def test_head_rejects_non_string_sha256_metadata(self):
        for invalid_sha256 in (None, 42, []):
            with self.subTest(sha256=invalid_sha256):
                response = {
                    'ContentLength': 4,
                    'Metadata': {
                        'sha256': invalid_sha256,
                        'size': '4',
                        'backup-date': '2026-08-12',
                        'retention': 'daily',
                    },
                }
                with patch.object(self.client, 'head_object', return_value=response):
                    with self.assertRaises(RemoteObjectInvalid):
                        self.storage.head_managed(self.key)

    def test_head_rejects_size_metadata_that_disagrees_with_content_length(self):
        self.stubber.add_response(
            'head_object',
            {
                'ContentLength': 4,
                'Metadata': {
                    'sha256': self.sha256,
                    'size': '5',
                    'backup-date': self.backup_date.isoformat(),
                    'retention': 'daily',
                },
            },
            {'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber, self.assertRaises(RemoteObjectInvalid):
            self.storage.head_managed(self.key)

    def test_head_rejects_backup_date_that_disagrees_with_key(self):
        self.valid_head(backup_date=date(2026, 8, 11))

        with self.stubber, self.assertRaises(RemoteObjectInvalid):
            self.storage.head_managed(self.key)

    def test_head_rejects_retention_that_disagrees_with_date(self):
        monthly_key = 'production/backups/2026/03/lar-finance-2026-03-01.sqlite3'
        self.stubber.add_response(
            'head_object',
            {
                'ContentLength': 4,
                'Metadata': {
                    'sha256': self.sha256,
                    'size': '4',
                    'backup-date': '2026-03-01',
                    'retention': 'daily',
                },
            },
            {'Bucket': self.bucket, 'Key': monthly_key},
        )

        with self.stubber, self.assertRaises(RemoteObjectInvalid):
            self.storage.head_managed(monthly_key)

    def test_upload_is_non_overwriting_and_confirms_the_remote_object(self):
        expected_metadata = {
            'sha256': self.sha256,
            'size': '4',
            'backup-date': '2026-08-12',
            'retention': 'daily',
        }
        self.stubber.add_response(
            'put_object',
            {},
            {
                'Bucket': self.bucket,
                'Key': self.key,
                'Body': ANY,
                'ContentType': 'application/vnd.sqlite3',
                'Metadata': expected_metadata,
                'IfNoneMatch': '*',
            },
        )
        self.stubber.add_response(
            'head_object',
            {'ContentLength': 4, 'Metadata': expected_metadata},
            {'Bucket': self.bucket, 'Key': self.key},
        )

        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / 'backup.sqlite3'
            path.write_bytes(self.content)
            with self.stubber:
                remote = self.storage.upload_and_verify(
                    path,
                    self.key,
                    self.backup_date,
                    self.sha256,
                )

        self.assertEqual(
            remote,
            RemoteObject(
                key=self.key,
                backup_date=self.backup_date,
                size=4,
                sha256=self.sha256,
                retention=frozenset({'daily'}),
            ),
        )

    def test_upload_uses_all_exact_retention_labels_for_monthly_sunday(self):
        backup_date = date(2026, 3, 1)
        key = 'production/backups/2026/03/lar-finance-2026-03-01.sqlite3'
        expected_metadata = {
            'sha256': self.sha256,
            'size': '4',
            'backup-date': '2026-03-01',
            'retention': 'daily,weekly,monthly',
        }
        self.stubber.add_response(
            'put_object',
            {},
            {
                'Bucket': self.bucket,
                'Key': key,
                'Body': ANY,
                'ContentType': 'application/vnd.sqlite3',
                'Metadata': expected_metadata,
                'IfNoneMatch': '*',
            },
        )
        self.stubber.add_response(
            'head_object',
            {'ContentLength': 4, 'Metadata': expected_metadata},
            {'Bucket': self.bucket, 'Key': key},
        )

        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / 'backup.sqlite3'
            path.write_bytes(self.content)
            with self.stubber:
                remote = self.storage.upload_and_verify(
                    path,
                    key,
                    backup_date,
                    self.sha256,
                )

        self.assertEqual(
            remote.retention,
            frozenset({'daily', 'weekly', 'monthly'}),
        )

    def test_upload_rejects_invalid_local_sha256_before_calling_r2(self):
        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / 'backup.sqlite3'
            path.write_bytes(self.content)
            with self.stubber, self.assertRaises(RemoteVerificationError):
                self.storage.upload_and_verify(
                    path, self.key, self.backup_date, 'A' * 64
                )

    def test_upload_rejects_key_that_disagrees_with_backup_date(self):
        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / 'backup.sqlite3'
            path.write_bytes(self.content)
            with self.stubber, self.assertRaises(RemoteVerificationError):
                self.storage.upload_and_verify(
                    path,
                    self.key,
                    date(2026, 8, 11),
                    self.sha256,
                )

    def test_upload_raises_when_remote_size_does_not_match(self):
        expected_metadata = {
            'sha256': self.sha256,
            'size': '4',
            'backup-date': '2026-08-12',
            'retention': 'daily',
        }
        self.stubber.add_response(
            'put_object',
            {},
            {
                'Bucket': self.bucket,
                'Key': self.key,
                'Body': ANY,
                'ContentType': 'application/vnd.sqlite3',
                'Metadata': expected_metadata,
                'IfNoneMatch': '*',
            },
        )
        self.stubber.add_response(
            'head_object',
            {
                'ContentLength': 5,
                'Metadata': expected_metadata,
            },
            {'Bucket': self.bucket, 'Key': self.key},
        )

        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / 'backup.sqlite3'
            path.write_bytes(self.content)
            with self.stubber, self.assertRaises(RemoteVerificationError):
                self.storage.upload_and_verify(
                    path,
                    self.key,
                    self.backup_date,
                    self.sha256,
                )

    def test_upload_raises_when_remote_hash_does_not_match(self):
        expected_metadata = {
            'sha256': self.sha256,
            'size': '4',
            'backup-date': '2026-08-12',
            'retention': 'daily',
        }
        self.stubber.add_response(
            'put_object',
            {},
            {
                'Bucket': self.bucket,
                'Key': self.key,
                'Body': ANY,
                'ContentType': 'application/vnd.sqlite3',
                'Metadata': expected_metadata,
                'IfNoneMatch': '*',
            },
        )
        self.stubber.add_response(
            'head_object',
            {
                'ContentLength': 4,
                'Metadata': expected_metadata | {'sha256': '0' * 64},
            },
            {'Bucket': self.bucket, 'Key': self.key},
        )

        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / 'backup.sqlite3'
            path.write_bytes(self.content)
            with self.stubber, self.assertRaises(RemoteVerificationError):
                self.storage.upload_and_verify(
                    path,
                    self.key,
                    self.backup_date,
                    self.sha256,
                )

    def test_upload_converts_non_string_remote_sha256_to_verification_error(self):
        expected_metadata = {
            'sha256': self.sha256,
            'size': '4',
            'backup-date': '2026-08-12',
            'retention': 'daily',
        }
        self.stubber.add_response(
            'put_object',
            {},
            {
                'Bucket': self.bucket,
                'Key': self.key,
                'Body': ANY,
                'ContentType': 'application/vnd.sqlite3',
                'Metadata': expected_metadata,
                'IfNoneMatch': '*',
            },
        )
        invalid_head = {
            'ContentLength': 4,
            'Metadata': expected_metadata | {'sha256': None},
        }

        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / 'backup.sqlite3'
            path.write_bytes(self.content)
            with self.stubber, patch.object(
                self.client,
                'head_object',
                return_value=invalid_head,
            ):
                with self.assertRaises(RemoteVerificationError):
                    self.storage.upload_and_verify(
                        path,
                        self.key,
                        self.backup_date,
                        self.sha256,
                    )

    def test_upload_sanitizes_precondition_failed_code_as_conflict(self):
        self.assert_upload_conflict(
            service_error_code='PreconditionFailed',
            http_status_code=400,
        )

    def test_upload_sanitizes_http_412_status_as_conflict(self):
        self.assert_upload_conflict(
            service_error_code='Unknown',
            http_status_code=412,
        )

    def assert_upload_conflict(self, *, service_error_code, http_status_code):
        expected_metadata = {
            'sha256': self.sha256,
            'size': '4',
            'backup-date': '2026-08-12',
            'retention': 'daily',
        }
        self.stubber.add_client_error(
            'put_object',
            service_error_code=service_error_code,
            service_message=(
                'https://account.invalid fake-access-id fake-secret sensitive-body'
            ),
            http_status_code=http_status_code,
            expected_params={
                'Bucket': self.bucket,
                'Key': self.key,
                'Body': ANY,
                'ContentType': 'application/vnd.sqlite3',
                'Metadata': expected_metadata,
                'IfNoneMatch': '*',
            },
        )

        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / 'backup.sqlite3'
            path.write_bytes(self.content)
            with self.stubber, self.assertRaises(RemoteObjectConflict) as raised:
                self.storage.upload_and_verify(
                    path,
                    self.key,
                    self.backup_date,
                    self.sha256,
                )

        message = str(raised.exception)
        self.assertNotIn('account.invalid', message)
        self.assertNotIn('fake-access-id', message)
        self.assertNotIn('fake-secret', message)
        self.assertNotIn('sensitive-body', message)

    def test_list_paginates_and_heads_only_managed_keys(self):
        second_key = 'production/backups/2026/08/lar-finance-2026-08-11.sqlite3'
        self.stubber.add_response(
            'list_objects_v2',
            {
                'IsTruncated': True,
                'NextContinuationToken': 'page-2',
                'Contents': [
                    {'Key': self.key},
                    {'Key': 'production/backups/manual.sqlite3'},
                ],
            },
            {'Bucket': self.bucket, 'Prefix': 'production/backups/'},
        )
        self.valid_head()
        self.stubber.add_response(
            'list_objects_v2',
            {'IsTruncated': False, 'Contents': [{'Key': second_key}]},
            {
                'Bucket': self.bucket,
                'Prefix': 'production/backups/',
                'ContinuationToken': 'page-2',
            },
        )
        self.valid_head(key=second_key, backup_date=date(2026, 8, 11))

        with self.stubber:
            remote_objects = self.storage.list_managed()

        self.assertEqual([item.key for item in remote_objects], [self.key, second_key])

    def test_list_fails_for_a_managed_key_with_invalid_metadata(self):
        self.stubber.add_response(
            'list_objects_v2',
            {'IsTruncated': False, 'Contents': [{'Key': self.key}]},
            {'Bucket': self.bucket, 'Prefix': 'production/backups/'},
        )
        self.stubber.add_response(
            'head_object',
            {'ContentLength': 4, 'Metadata': {}},
            {'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber, self.assertRaises(RemoteObjectInvalid):
            self.storage.list_managed()

    def test_list_fails_for_non_string_sha256_metadata(self):
        self.stubber.add_response(
            'list_objects_v2',
            {'IsTruncated': False, 'Contents': [{'Key': self.key}]},
            {'Bucket': self.bucket, 'Prefix': 'production/backups/'},
        )
        invalid_head = {
            'ContentLength': 4,
            'Metadata': {
                'sha256': 42,
                'size': '4',
                'backup-date': '2026-08-12',
                'retention': 'daily',
            },
        }

        with self.stubber, patch.object(
            self.client,
            'head_object',
            return_value=invalid_head,
        ):
            with self.assertRaises(RemoteObjectInvalid):
                self.storage.list_managed()

    def test_delete_uses_the_exact_bucket_and_key(self):
        self.stubber.add_response(
            'delete_object',
            {},
            {'Bucket': self.bucket, 'Key': self.key},
        )

        with self.stubber:
            self.storage.delete(self.key)
