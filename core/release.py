import os
import re
from typing import Mapping

SHA_PATTERN = re.compile(r'^[0-9a-f]{40}$')


class ReleaseVersionError(ValueError):
    pass


def read_app_version(environ: Mapping[str, str] | None = None) -> str:
    source = os.environ if environ is None else environ
    return source.get('APP_VERSION', 'development').strip()


def validate_app_version(version: str, *, debug: bool) -> str:
    if SHA_PATTERN.fullmatch(version):
        return version
    if debug and version == 'development':
        return version
    raise ReleaseVersionError('Application release version is invalid.')


def public_app_version(environ: Mapping[str, str] | None = None) -> str:
    return read_app_version(environ)
