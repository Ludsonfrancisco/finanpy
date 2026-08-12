import re
from dataclasses import dataclass, field
from datetime import datetime, time
from typing import Mapping
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


class BackupConfigurationError(ValueError):
    pass


@dataclass(frozen=True)
class R2BackupConfig:
    endpoint_url: str
    access_key_id: str = field(repr=False)
    secret_access_key: str = field(repr=False)
    bucket: str
    prefix: str
    schedule_time: time
    time_zone: ZoneInfo
    retry_seconds: int = 3600
    daily_retention: int = 14
    weekly_retention: int = 8
    monthly_retention: int = 12

    @classmethod
    def from_env(cls, environ: Mapping[str, str]) -> 'R2BackupConfig':
        required_names = (
            'R2_BACKUP_ENDPOINT_URL',
            'R2_BACKUP_ACCESS_KEY_ID',
            'R2_BACKUP_SECRET_ACCESS_KEY',
            'R2_BACKUP_BUCKET',
        )
        values = {name: environ.get(name, '').strip() for name in required_names}
        missing = [name for name, value in values.items() if not value]
        if missing:
            raise BackupConfigurationError(
                f'Missing backup configuration: {", ".join(missing)}'
            )

        endpoint_url = values['R2_BACKUP_ENDPOINT_URL']
        try:
            parsed_endpoint = urlsplit(endpoint_url)
            endpoint_is_valid = (
                parsed_endpoint.scheme == 'https'
                and parsed_endpoint.hostname is not None
            )
        except ValueError:
            endpoint_is_valid = False
        if not endpoint_is_valid:
            raise BackupConfigurationError(
                'R2_BACKUP_ENDPOINT_URL must be a valid HTTPS URL.'
            )

        prefix = environ.get('R2_BACKUP_PREFIX', 'production').strip().strip('/')
        if not prefix:
            raise BackupConfigurationError('R2_BACKUP_PREFIX must not be empty.')

        schedule_text = environ.get('R2_BACKUP_TIME', '03:00').strip()
        if not re.fullmatch(r'\d{2}:\d{2}', schedule_text):
            raise BackupConfigurationError('R2_BACKUP_TIME must use HH:MM.')
        try:
            schedule_time = datetime.strptime(schedule_text, '%H:%M').time()
        except ValueError as error:
            raise BackupConfigurationError('R2_BACKUP_TIME must use HH:MM.') from error

        zone_name = environ.get('R2_BACKUP_TIME_ZONE', 'America/Sao_Paulo').strip()
        try:
            time_zone = ZoneInfo(zone_name)
        except (ValueError, ZoneInfoNotFoundError) as error:
            raise BackupConfigurationError('R2_BACKUP_TIME_ZONE is invalid.') from error

        return cls(
            endpoint_url=endpoint_url,
            access_key_id=values['R2_BACKUP_ACCESS_KEY_ID'],
            secret_access_key=values['R2_BACKUP_SECRET_ACCESS_KEY'],
            bucket=values['R2_BACKUP_BUCKET'],
            prefix=prefix,
            schedule_time=schedule_time,
            time_zone=time_zone,
        )
