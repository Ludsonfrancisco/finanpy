import hashlib
import sqlite3
from contextlib import closing
from datetime import UTC, date, datetime, time
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch
from zoneinfo import ZoneInfo

import boto3
from botocore.exceptions import ClientError
from botocore.stub import ANY, Stubber
from django.test import SimpleTestCase

from core.backup_catalog import (
    build_deploy_object_key,
    parse_deploy_object_key,
)
from core.backup_config import R2BackupConfig
from core.r2_storage import (
    DeployRemoteObject,
    R2Storage,
    RemoteObjectConflict,
    RemoteVerificationError,
)
from core.remote_backup import execute_deploy_backup


def fixed_utc_now():
    return datetime(2026, 8, 21, 18, 30, 45, 123456, tzinfo=UTC)


def backup_config(*, prefix):
    return R2BackupConfig(
        endpoint_url='https://example.invalid',
        access_key_id='test-access',
        secret_access_key='test-secret',
        bucket='test-bucket',
        prefix=prefix,
        schedule_time=time(3, 0),
        time_zone=ZoneInfo('America/Sao_Paulo'),
    )


def create_valid_sqlite(path):
    with closing(sqlite3.connect(path)) as database:
        database.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY)')
        database.commit()


def deploy_remote_object():
    return DeployRemoteObject(
        key=build_deploy_object_key('production', 'b' * 40, fixed_utc_now()),
        backup_date=fixed_utc_now().date(),
        size=1,
        sha256='c' * 64,
    )


class DeployBackupTest(SimpleTestCase):
    def test_key_is_unique_per_sha_and_utc_microsecond(self):
        now = datetime(2026, 8, 21, 18, 30, 45, 123456, tzinfo=UTC)
        key = build_deploy_object_key('production', 'a' * 40, now)
        self.assertEqual(
            key,
            'production/deploy/'
            + 'a' * 40
            + '/20260821T183045123456Z/2026/08/21.sqlite3',
        )

    def test_deploy_key_round_trips_and_rejects_invalid_keys(self):
        version = 'a' * 40
        key = build_deploy_object_key('production', version, fixed_utc_now())

        self.assertEqual(
            parse_deploy_object_key('production', key),
            (version, fixed_utc_now(), date(2026, 8, 21)),
        )
        self.assertIsNone(
            parse_deploy_object_key('production', key.replace(version, 'A' * 40))
        )
        self.assertIsNone(
            parse_deploy_object_key(
                'production', key.replace('/2026/08/21.sqlite3', '/2026/08/20.sqlite3')
            )
        )

    def test_verified_deploy_backup_does_not_run_daily_retention(self):
        with TemporaryDirectory() as directory:
            source = Path(directory, 'db.sqlite3')
            create_valid_sqlite(source)
            storage = Mock()
            storage.upload_deploy_and_verify.return_value = deploy_remote_object()

            outcome = execute_deploy_backup(
                config=backup_config(prefix='production'),
                storage=storage,
                database_path=source,
                now=fixed_utc_now(),
                version='b' * 40,
            )

            self.assertEqual(outcome.status, 'created')
            self.assertEqual(outcome.deleted_keys, ())
            storage.list_managed.assert_not_called()
            storage.delete.assert_not_called()

    def test_process_control_exceptions_are_preserved_during_copy(self):
        with TemporaryDirectory() as directory:
            source = Path(directory, 'db.sqlite3')
            create_valid_sqlite(source)
            for exception_type in (KeyboardInterrupt, SystemExit):
                with self.subTest(exception_type=exception_type.__name__), patch(
                    'core.remote_backup.backup_sqlite',
                    side_effect=exception_type(),
                ):
                    with self.assertRaises(exception_type):
                        execute_deploy_backup(
                            config=backup_config(prefix='production'),
                            storage=Mock(),
                            database_path=source,
                            now=fixed_utc_now(),
                            version='b' * 40,
                        )

    def test_process_control_exceptions_are_preserved_during_upload(self):
        with TemporaryDirectory() as directory:
            source = Path(directory, 'db.sqlite3')
            create_valid_sqlite(source)
            for exception_type in (KeyboardInterrupt, SystemExit):
                storage = Mock()
                storage.upload_deploy_and_verify.side_effect = exception_type()
                with self.subTest(exception_type=exception_type.__name__):
                    with self.assertRaises(exception_type):
                        execute_deploy_backup(
                            config=backup_config(prefix='production'),
                            storage=storage,
                            database_path=source,
                            now=fixed_utc_now(),
                            version='b' * 40,
                        )


class DeployStorageTest(SimpleTestCase):
    bucket = 'test-bucket'
    prefix = 'production'
    backup_date = date(2026, 8, 21)
    version = 'a' * 40
    content = b'data'
    sha256 = hashlib.sha256(content).hexdigest()

    def setUp(self):
        self.client = boto3.client(
            service_name='s3',
            endpoint_url='https://example.invalid',
            aws_access_key_id='test-access',
            aws_secret_access_key='test-secret',
            region_name='auto',
        )
        self.storage = R2Storage(
            client=self.client,
            bucket=self.bucket,
            prefix=self.prefix,
        )
        self.stubber = Stubber(self.client)
        self.key = build_deploy_object_key(
            self.prefix,
            self.version,
            fixed_utc_now(),
        )

    def _temporary_backup(self, directory):
        path = Path(directory, 'backup.sqlite3')
        path.write_bytes(self.content)
        return path

    def _expected_metadata(self, path, *, sha256=None):
        return {
            'sha256': sha256 or self.sha256,
            'size': str(path.stat().st_size),
            'backup-date': '2026-08-21',
            'kind': 'deploy',
        }

    def test_upload_uses_conditional_create_and_exact_metadata(self):
        with TemporaryDirectory() as directory:
            path = self._temporary_backup(directory)
            expected_metadata = self._expected_metadata(path)
            expected_put = {
                'Bucket': self.bucket,
                'Key': self.key,
                'Body': ANY,
                'ContentType': 'application/vnd.sqlite3',
                'Metadata': expected_metadata,
                'IfNoneMatch': '*',
            }
            self.stubber.add_response('put_object', {}, expected_put)
            self.stubber.add_response(
                'head_object',
                {
                    'ContentLength': path.stat().st_size,
                    'Metadata': expected_metadata,
                },
                {'Bucket': self.bucket, 'Key': self.key},
            )

            with self.stubber:
                remote = self.storage.upload_deploy_and_verify(
                    path,
                    self.key,
                    self.backup_date,
                    self.sha256,
                )

        self.assertEqual(
            remote,
            DeployRemoteObject(
                key=self.key,
                backup_date=self.backup_date,
                size=len(self.content),
                sha256=self.sha256,
            ),
        )

    def test_upload_rejects_preexisting_key(self):
        with TemporaryDirectory() as directory:
            path = self._temporary_backup(directory)
            self.stubber.add_client_error(
                'put_object',
                service_error_code='PreconditionFailed',
                http_status_code=412,
                expected_params={
                    'Bucket': self.bucket,
                    'Key': self.key,
                    'Body': ANY,
                    'ContentType': 'application/vnd.sqlite3',
                    'Metadata': self._expected_metadata(path),
                    'IfNoneMatch': '*',
                },
            )

            with self.stubber, self.assertRaises(RemoteObjectConflict):
                self.storage.upload_deploy_and_verify(
                    path,
                    self.key,
                    self.backup_date,
                    self.sha256,
                )

    def test_upload_rejects_invalid_remote_metadata(self):
        with TemporaryDirectory() as directory:
            path = self._temporary_backup(directory)
            expected_metadata = self._expected_metadata(path)
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
                    'ContentLength': path.stat().st_size,
                    'Metadata': self._expected_metadata(path, sha256='f' * 64),
                },
                {'Bucket': self.bucket, 'Key': self.key},
            )

            with self.stubber, self.assertRaises(RemoteVerificationError):
                self.storage.upload_deploy_and_verify(
                    path,
                    self.key,
                    self.backup_date,
                    self.sha256,
                )

    def test_upload_does_not_hide_forbidden(self):
        self._assert_upload_client_error_escapes('AccessDenied', 403)

    def test_upload_does_not_hide_server_error(self):
        self._assert_upload_client_error_escapes('InternalError', 500)

    def _assert_upload_client_error_escapes(self, error_code, status_code):
        with TemporaryDirectory() as directory:
            path = self._temporary_backup(directory)
            self.stubber.add_client_error(
                'put_object',
                service_error_code=error_code,
                http_status_code=status_code,
                expected_params={
                    'Bucket': self.bucket,
                    'Key': self.key,
                    'Body': ANY,
                    'ContentType': 'application/vnd.sqlite3',
                    'Metadata': self._expected_metadata(path),
                    'IfNoneMatch': '*',
                },
            )

            with self.stubber, self.assertRaises(ClientError) as raised:
                self.storage.upload_deploy_and_verify(
                    path,
                    self.key,
                    self.backup_date,
                    self.sha256,
                )

        self.assertEqual(
            raised.exception.response['ResponseMetadata']['HTTPStatusCode'],
            status_code,
        )

    def test_daily_catalog_never_lists_deploy_prefix(self):
        daily_key = (
            'production/backups/2026/08/lar-finance-2026-08-21.sqlite3'
        )
        daily_metadata = {
            'sha256': self.sha256,
            'size': str(len(self.content)),
            'backup-date': '2026-08-21',
            'retention': 'daily',
        }
        self.stubber.add_response(
            'list_objects_v2',
            {
                'IsTruncated': False,
                'Contents': [{'Key': daily_key}, {'Key': self.key}],
            },
            {'Bucket': self.bucket, 'Prefix': 'production/backups/'},
        )
        self.stubber.add_response(
            'head_object',
            {'ContentLength': len(self.content), 'Metadata': daily_metadata},
            {'Bucket': self.bucket, 'Key': daily_key},
        )

        with self.stubber:
            objects = self.storage.list_managed()

        self.assertEqual([remote.key for remote in objects], [daily_key])
