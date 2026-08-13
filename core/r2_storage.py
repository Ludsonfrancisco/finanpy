import re
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Self

import boto3
from botocore.exceptions import ClientError

from core.backup_catalog import CatalogObject, parse_managed_key, retention_labels
from core.backup_config import R2BackupConfig

SQLITE_CONTENT_TYPE = 'application/vnd.sqlite3'
SHA256_PATTERN = re.compile(r'[0-9a-f]{64}')
RETENTION_ORDER = ('daily', 'weekly', 'monthly')


class R2StorageError(RuntimeError):
    pass


class RemoteObjectInvalid(R2StorageError):
    pass


class RemoteVerificationError(R2StorageError):
    pass


class RemoteObjectConflict(R2StorageError):
    pass


@dataclass(frozen=True)
class RemoteObject(CatalogObject):
    size: int
    sha256: str
    retention: frozenset[str]


class R2Storage:
    def __init__(self, client: Any, bucket: str, prefix: str):
        self.client = client
        self.bucket = bucket
        self.prefix = prefix

    @classmethod
    def from_config(cls, config: R2BackupConfig) -> Self:
        client = boto3.client(
            service_name='s3',
            endpoint_url=config.endpoint_url,
            aws_access_key_id=config.access_key_id,
            aws_secret_access_key=config.secret_access_key,
            region_name='auto',
        )
        return cls(client=client, bucket=config.bucket, prefix=config.prefix)

    def head_managed(self, key: str) -> RemoteObject | None:
        key_date = parse_managed_key(self.prefix, key)
        if key_date is None:
            return None

        try:
            response = self.client.head_object(Bucket=self.bucket, Key=key)
        except ClientError as error:
            error_code = error.response.get('Error', {}).get('Code')
            status_code = error.response.get('ResponseMetadata', {}).get(
                'HTTPStatusCode'
            )
            if status_code == 403 or (
                isinstance(status_code, int) and 500 <= status_code <= 599
            ):
                raise
            if status_code == 404 or error_code in {'404', 'NoSuchKey'}:
                return None
            raise

        return self._parse_head(key, key_date, response)

    def upload_and_verify(
        self,
        path: str | Path,
        key: str,
        backup_date: date,
        sha256: str,
    ) -> RemoteObject:
        if SHA256_PATTERN.fullmatch(sha256) is None:
            raise RemoteVerificationError('Local backup SHA-256 is invalid.')
        if parse_managed_key(self.prefix, key) != backup_date:
            raise RemoteVerificationError('Backup key and date do not match.')

        backup_path = Path(path)
        size = backup_path.stat().st_size
        expected_retention = retention_labels(backup_date)
        metadata = {
            'sha256': sha256,
            'size': str(size),
            'backup-date': backup_date.isoformat(),
            'retention': self._serialize_retention(expected_retention),
        }
        try:
            with backup_path.open('rb') as body:
                self.client.put_object(
                    Bucket=self.bucket,
                    Key=key,
                    Body=body,
                    ContentType=SQLITE_CONTENT_TYPE,
                    Metadata=metadata,
                    IfNoneMatch='*',
                )
        except ClientError as error:
            error_code = error.response.get('Error', {}).get('Code')
            status_code = error.response.get('ResponseMetadata', {}).get(
                'HTTPStatusCode'
            )
            if error_code == 'PreconditionFailed' or status_code == 412:
                raise RemoteObjectConflict(
                    'A remote object already exists for this backup key.'
                ) from None
            raise

        try:
            remote = self.head_managed(key)
        except RemoteObjectInvalid:
            raise RemoteVerificationError(
                'Remote backup verification failed.'
            ) from None
        expected = RemoteObject(
            key=key,
            backup_date=backup_date,
            size=size,
            sha256=sha256,
            retention=expected_retention,
        )
        if remote != expected:
            raise RemoteVerificationError('Remote backup verification failed.')
        return remote

    def list_managed(self) -> list[RemoteObject]:
        objects = []
        paginator = self.client.get_paginator('list_objects_v2')
        for page in paginator.paginate(
            Bucket=self.bucket,
            Prefix=f'{self.prefix}/backups/',
        ):
            for item in page.get('Contents', []):
                key = item.get('Key')
                if not isinstance(key, str):
                    continue
                if parse_managed_key(self.prefix, key) is None:
                    continue
                remote = self.head_managed(key)
                if remote is not None:
                    objects.append(remote)
        return objects

    def delete(self, key: str) -> None:
        self.client.delete_object(Bucket=self.bucket, Key=key)

    def _parse_head(
        self,
        key: str,
        key_date: date,
        response: dict[str, Any],
    ) -> RemoteObject:
        try:
            content_length = response['ContentLength']
            metadata = response['Metadata']
            size_text = metadata['size']
            sha256 = metadata['sha256']
            backup_date_text = metadata['backup-date']
            retention_text = metadata['retention']

            if (
                isinstance(content_length, bool)
                or not isinstance(content_length, int)
                or content_length < 0
            ):
                raise ValueError
            size = int(size_text)
            backup_date = date.fromisoformat(backup_date_text)
        except (KeyError, TypeError, ValueError):
            raise RemoteObjectInvalid('Remote object metadata is invalid.') from None

        expected_retention = retention_labels(key_date)
        if (
            str(size) != size_text
            or size != content_length
            or not isinstance(sha256, str)
            or SHA256_PATTERN.fullmatch(sha256) is None
            or backup_date.isoformat() != backup_date_text
            or backup_date != key_date
            or retention_text != self._serialize_retention(expected_retention)
        ):
            raise RemoteObjectInvalid('Remote object metadata is invalid.')

        return RemoteObject(
            key=key,
            backup_date=backup_date,
            size=size,
            sha256=sha256,
            retention=expected_retention,
        )

    @staticmethod
    def _serialize_retention(labels: frozenset[str]) -> str:
        return ','.join(label for label in RETENTION_ORDER if label in labels)
